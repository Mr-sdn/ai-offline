# AI Offline - first-time setup. Started in the background by server.ps1; the page shows its progress.
# Steps: download the AI engine (Ollama) and the coding agent (OpenCode), check them, unpack them,
# start the engine, download the chosen model, write the settings. Safe to run again: finished
# steps are skipped and interrupted downloads continue where they stopped.
param(
    [Parameter(Mandatory = $true)][string]$Model,
    [string]$Shortcuts = '1'
)
. (Join-Path $PSScriptRoot 'common.ps1')
Initialize-AIODirs

$hw = Get-AIOHardware
$arch = $hw.arch
$ollama = $Config.downloads.ollama.$arch
$agentKey = if ($arch -eq 'arm64') { 'arm64' } elseif ($hw.avx2) { 'x64' } else { 'x64-baseline' }
$agent = $Config.downloads.opencode.$agentKey
$needRocm = ($arch -eq 'x64') -and (@($hw.gpus | Where-Object { $_.vendor -eq 'amd' }).Count -gt 0)
$modelInfo = @($Config.models) + @($Config.extraModels) | Where-Object { $_.id -eq $Model } | Select-Object -First 1
$modelBytes = if ($modelInfo) { [double]$modelInfo.sizeGB * 1e9 } else { 0 }

$state = [ordered]@{
    state = 'running'
    pid = $PID
    model = $Model
    step = 'engine'
    error = $null
    detail = $null
    steps = [ordered]@{
        engine = [ordered]@{ status = 'waiting'; done = 0; total = [double]$ollama.sizeMB * 1MB; speed = 0 }
        gpu = [ordered]@{ status = if ($needRocm) { 'waiting' } else { 'skipped' }; done = 0; total = [double]$Config.downloads.ollama.rocm.sizeMB * 1MB; speed = 0 }
        agent = [ordered]@{ status = 'waiting'; done = 0; total = [double]$agent.sizeMB * 1MB; speed = 0 }
        prepare = [ordered]@{ status = 'waiting'; done = 0; total = 100; speed = 0 }
        start = [ordered]@{ status = 'waiting'; done = 0; total = 1; speed = 0 }
        model = [ordered]@{ status = 'waiting'; done = 0; total = $modelBytes; speed = 0 }
        finish = [ordered]@{ status = 'waiting'; done = 0; total = 1; speed = 0 }
    }
    updated = 0
}
$script:lastSave = [DateTime]::MinValue

function Save-State([switch]$Force) {
    $now = [DateTime]::UtcNow
    if (-not $Force -and ($now - $script:lastSave).TotalMilliseconds -lt 400) { return }
    $script:lastSave = $now
    $state.updated = [long]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
    Write-AIOText $AIO.SetupFile (ConvertTo-AIOJson $state)
}

function Set-Step([string]$id, [string]$status) {
    $state.steps[$id].status = $status
    if ($status -eq 'active') { $state.step = $id }
    if ($status -eq 'done') { $state.steps[$id].done = $state.steps[$id].total; $state.steps[$id].speed = 0 }
    Save-State -Force
}

function Log([string]$m) { Write-AIOLog 'setup.log' $m }

# ---------------------------------------------------------------- download with resume + retries
function Get-Download([string]$id, $item, [string]$fileName) {
    $dest = Join-Path $AIO.Downloads $fileName
    $part = "$dest.part"
    $step = $state.steps[$id]
    if ((Test-Path -LiteralPath $dest) -and ((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -eq $item.sha256.ToUpper())) {
        Log "already downloaded: $fileName"
        return $dest
    }
    Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
    $attempt = 0
    while ($true) {
        $attempt++
        $have = 0L
        if (Test-Path -LiteralPath $part) { $have = (Get-Item -LiteralPath $part).Length }
        $resp = $null; $in = $null; $out = $null
        try {
            Log "download $fileName (attempt $attempt, have $have bytes)"
            $req = [Net.HttpWebRequest]::Create($item.url)
            $req.UserAgent = "AI-Offline/$($Config.version)"
            $req.Timeout = 30000
            $req.ReadWriteTimeout = 60000
            if ($have -gt 0) { $req.AddRange([long]$have) }
            $resp = $req.GetResponse()
            if ($have -gt 0 -and [int]$resp.StatusCode -ne 206) { $have = 0L; Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue }
            $total = $have + $resp.ContentLength
            $step.total = [double]$total
            $in = $resp.GetResponseStream()
            $mode = if ($have -gt 0) { [IO.FileMode]::Append } else { [IO.FileMode]::Create }
            $out = [IO.File]::Open($part, $mode, [IO.FileAccess]::Write, [IO.FileShare]::Read)
            $buf = New-Object byte[] 262144
            $done = $have
            $mark = [DateTime]::UtcNow; $markBytes = $done; $speed = 0.0
            while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                $out.Write($buf, 0, $n)
                $done += $n
                $elapsed = ([DateTime]::UtcNow - $mark).TotalSeconds
                if ($elapsed -ge 0.5) {
                    $now = ($done - $markBytes) / $elapsed
                    $speed = if ($speed -gt 0) { $speed * 0.7 + $now * 0.3 } else { $now }
                    $mark = [DateTime]::UtcNow; $markBytes = $done
                    $step.done = [double]$done; $step.speed = [double]$speed
                    Save-State
                }
            }
            $out.Close(); $out = $null
            if ($done -lt $total) { throw "connection closed early ($done of $total bytes)" }
            $step.done = [double]$done; $step.speed = 0
            $state.detail = 'verify'
            Save-State -Force
            $hash = (Get-FileHash -LiteralPath $part -Algorithm SHA256).Hash
            if ($hash -ne $item.sha256.ToUpper()) {
                Remove-Item -LiteralPath $part -Force
                throw "checksum mismatch for $fileName"
            }
            Move-Item -LiteralPath $part -Destination $dest -Force
            $state.detail = $null
            return $dest
        } catch {
            Log "download error: $($_.Exception.Message)"
            if ($attempt -ge 8) { throw "download failed: $($_.Exception.Message)" }
            $state.detail = "retry:$attempt"
            $step.speed = 0
            Save-State -Force
            Start-Sleep -Seconds ([Math]::Min(30, 2 * $attempt))
        } finally {
            if ($out) { $out.Close() }
            if ($in) { $in.Close() }
            if ($resp) { $resp.Close() }
        }
    }
}

# ---------------------------------------------------------------- unpack
function Expand-Zip([string]$zipPath, [string]$dest, [double]$from, [double]$to) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $root = [IO.Path]::GetFullPath($dest).TrimEnd('\') + '\'
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entries = @($zip.Entries)
        $total = 0.0; foreach ($e in $entries) { $total += $e.Length }
        $sofar = 0.0
        foreach ($e in $entries) {
            $target = [IO.Path]::GetFullPath((Join-Path $dest $e.FullName))
            if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw "bad path in archive: $($e.FullName)" }
            if ($e.FullName.EndsWith('/') -or $e.FullName.EndsWith('\')) {
                New-Item -ItemType Directory -Path $target -Force | Out-Null
                continue
            }
            $dir = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $target, $true)
            $sofar += $e.Length
            if ($total -gt 0) { $state.steps.prepare.done = $from + ($to - $from) * ($sofar / $total); Save-State }
        }
    } finally { $zip.Dispose() }
}

# ---------------------------------------------------------------- model download (through the engine)
function Get-Model([string]$name) {
    $step = $state.steps.model
    $attempt = 0
    while ($true) {
        $attempt++
        $resp = $null; $reader = $null
        try {
            Log "pull $name (attempt $attempt)"
            $req = [Net.HttpWebRequest]::Create("$($AIO.OllamaUrl)/api/pull")
            $req.Method = 'POST'
            $req.ContentType = 'application/json'
            $req.Proxy = $null
            $req.Timeout = 60000
            $req.ReadWriteTimeout = 600000
            $body = [Text.Encoding]::UTF8.GetBytes((ConvertTo-AIOJson @{ model = $name; stream = $true }))
            $req.ContentLength = $body.Length
            $s = $req.GetRequestStream(); $s.Write($body, 0, $body.Length); $s.Close()
            $resp = $req.GetResponse()
            $reader = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
            $layers = @{}
            $mark = [DateTime]::UtcNow; $markBytes = 0.0; $speed = 0.0
            while ($null -ne ($line = $reader.ReadLine())) {
                if (-not $line.Trim()) { continue }
                $msg = $line | ConvertFrom-Json
                if ($msg.error) { throw [string]$msg.error }
                if ($msg.digest -and $msg.total) { $layers[$msg.digest] = @([double]$msg.completed, [double]$msg.total) }
                $done = 0.0; $sum = 0.0
                foreach ($v in $layers.Values) { $done += $v[0]; $sum += $v[1] }
                $step.total = [Math]::Max($modelBytes, $sum)
                $step.done = $done
                $elapsed = ([DateTime]::UtcNow - $mark).TotalSeconds
                if ($elapsed -ge 0.5) {
                    $now = [Math]::Max(0, ($done - $markBytes)) / $elapsed
                    $speed = if ($speed -gt 0) { $speed * 0.7 + $now * 0.3 } else { $now }
                    $mark = [DateTime]::UtcNow; $markBytes = $done
                    $step.speed = $speed
                }
                $state.detail = if ($msg.status -match 'verifying|writing') { 'verify' } else { $null }
                Save-State
                if ($msg.status -eq 'success') { return }
            }
            throw 'the download stopped before it finished'
        } catch {
            $text = $_.Exception.Message
            Log "pull error: $text"
            if ($text -match 'file does not exist|not found|manifest unknown') { throw "model-not-found: $name" }
            if ($attempt -ge 8) { throw "model download failed: $text" }
            $state.detail = "retry:$attempt"
            $step.speed = 0
            Save-State -Force
            if (-not (Test-AIOOllama)) { Start-AIOOllama -Wait | Out-Null }
            Start-Sleep -Seconds ([Math]::Min(30, 2 * $attempt))
        } finally {
            if ($reader) { $reader.Close() }
            if ($resp) { $resp.Close() }
        }
    }
}

# ---------------------------------------------------------------- run
try {
    Log "setup started: model=$Model arch=$arch agent=$agentKey rocm=$needRocm ram=$($hw.ramGB) free=$($hw.freeGB)"
    Save-State -Force
    $engineReady = Test-Path -LiteralPath $AIO.OllamaExe
    $agentReady = Test-Path -LiteralPath $AIO.OpenCodeExe

    if ($engineReady) { Set-Step 'engine' 'done'; $engineZip = $null } else {
        Set-Step 'engine' 'active'
        $engineZip = Get-Download 'engine' $ollama 'ollama.zip'
        Set-Step 'engine' 'done'
    }
    $rocmZip = $null
    if ($needRocm -and -not $engineReady) {
        Set-Step 'gpu' 'active'
        $rocmZip = Get-Download 'gpu' $Config.downloads.ollama.rocm 'ollama-rocm.zip'
        Set-Step 'gpu' 'done'
    } elseif ($needRocm) { Set-Step 'gpu' 'done' }
    if ($agentReady) { Set-Step 'agent' 'done'; $agentZip = $null } else {
        Set-Step 'agent' 'active'
        $agentZip = Get-Download 'agent' $agent 'opencode.zip'
        Set-Step 'agent' 'done'
    }

    Set-Step 'prepare' 'active'
    if ($engineZip) {
        $tmp = Join-Path $AIO.Runtime 'ollama.new'
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Expand-Zip $engineZip $tmp 0 70
        if ($rocmZip) { Expand-Zip $rocmZip $tmp 70 85 }
        $final = Join-Path $AIO.Runtime 'ollama'
        Remove-Item -LiteralPath $final -Recurse -Force -ErrorAction SilentlyContinue
        Move-Item -LiteralPath $tmp -Destination $final
    }
    if ($agentZip) {
        $tmp = Join-Path $AIO.Runtime 'opencode.new'
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Expand-Zip $agentZip $tmp 85 100
        $final = Join-Path $AIO.Runtime 'opencode'
        Remove-Item -LiteralPath $final -Recurse -Force -ErrorAction SilentlyContinue
        Move-Item -LiteralPath $tmp -Destination $final
    }
    # the zips are no longer needed
    foreach ($z in $engineZip, $rocmZip, $agentZip) { if ($z) { Remove-Item -LiteralPath $z -Force -ErrorAction SilentlyContinue } }
    Set-Step 'prepare' 'done'

    Set-Step 'start' 'active'
    if (-not (Start-AIOOllama -Wait)) { throw 'engine-start-failed' }
    Set-Step 'start' 'done'

    Set-Step 'model' 'active'
    $have = @(Get-AIOInstalledModels | ForEach-Object { $_.name })
    if ($have -notcontains $Model) { Get-Model $Model }
    Set-Step 'model' 'done'

    Set-Step 'finish' 'active'
    $settingsPath = Join-Path $AIO.Store 'settings.json'
    $settings = Read-AIOJson $settingsPath
    if (-not $settings) { $settings = [pscustomobject]@{} }
    $settings | Add-Member -NotePropertyName model -NotePropertyValue $Model -Force
    Write-AIOText $settingsPath (ConvertTo-AIOJson $settings)
    try { Write-AIOAgentConfig | Out-Null } catch { Log "agent config: $($_.Exception.Message)" }
    if ($Shortcuts -eq '1') { try { New-AIOShortcuts $true $true } catch { Log "shortcuts: $($_.Exception.Message)" } }
    Write-AIOText $AIO.InstalledFile (ConvertTo-AIOJson ([ordered]@{
        version = $Config.version; model = $Model; ollama = $Config.downloads.ollama.version
        opencode = $Config.downloads.opencode.version; date = (Get-Date).ToString('s')
    }))
    Set-Step 'finish' 'done'
    $state.state = 'done'
    $state.detail = $null
    Save-State -Force
    Log 'setup finished'
} catch {
    $msg = $_.Exception.Message
    Log "setup failed: $msg"
    $state.state = 'error'
    $state.error = $msg
    $state.steps[$state.step].status = 'error'
    $state.steps[$state.step].speed = 0
    Save-State -Force
    exit 1
}
