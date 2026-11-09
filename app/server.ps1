# AI Offline - the small local server behind the app window.
# Serves the page, saves chats and settings inside the AI Offline folder, runs the first-time setup,
# and starts/stops the AI engine. Listens on 127.0.0.1 only and refuses requests from other websites.
param([switch]$NoBrowser)
. (Join-Path $PSScriptRoot 'common.ps1')
Initialize-AIODirs

function Log([string]$m) { Write-AIOLog 'server.log' $m }

# ---------------------------------------------------------------- one instance only
$listener = $null
$port = 0
$basePort = [int]$Config.ports.ui
foreach ($p in $basePort..($basePort + 9)) {
    if (Test-AIOHttp "http://127.0.0.1:$p/api/local/ping" 1200) {
        # already running: just show the window
        if (-not $NoBrowser) { Open-AIOBrowser "http://127.0.0.1:$p/" }
        exit 0
    }
    try {
        $l = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $p)
        $l.Start()
        $listener = $l; $port = $p
        break
    } catch { }
}
if (-not $listener) {
    Show-AIOMessage "AI Offline could not start: ports $($Config.ports.ui)-$($Config.ports.ui + 9) are all in use.`nRestart the computer and try again."
    exit 1
}
Log "server started on port $port (pid $PID)"
Write-AIOText $AIO.ServerFile (ConvertTo-AIOJson ([ordered]@{ port = $port; pid = $PID; started = (Get-Date).ToString('s') }))
$origin = "http://127.0.0.1:$port"

if (Test-AIOInstalled) { Start-AIOOllama | Out-Null }
if (-not $NoBrowser) { Open-AIOBrowser "$origin/" }

# ---------------------------------------------------------------- HTTP helpers
$utf8 = [Text.UTF8Encoding]::new($false)
$mime = @{
    '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'; '.svg' = 'image/svg+xml'; '.png' = 'image/png'; '.ico' = 'image/x-icon'
    '.woff2' = 'font/woff2'; '.txt' = 'text/plain; charset=utf-8'; '.md' = 'text/plain; charset=utf-8'; '.webp' = 'image/webp'
}
$csp = "default-src 'self'; connect-src 'self' $($AIO.OllamaUrl); img-src 'self' data: blob:; style-src 'self' 'unsafe-inline'; font-src 'self'; script-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'"

function New-Response([int]$status, [string]$type, [byte[]]$body) { @{ status = $status; type = $type; body = $body } }
function Json-Response($value, [int]$status = 200) { New-Response $status 'application/json; charset=utf-8' $utf8.GetBytes((ConvertTo-AIOJson $value)) }
function Raw-Json([string]$text, [int]$status = 200) { New-Response $status 'application/json; charset=utf-8' $utf8.GetBytes($text) }
function Error-Response([int]$status, [string]$message) { Json-Response @{ error = $message } $status }

function Send-Response($stream, $res) {
    $reason = @{ 200 = 'OK'; 204 = 'No Content'; 400 = 'Bad Request'; 403 = 'Forbidden'; 404 = 'Not Found'; 405 = 'Method Not Allowed'; 409 = 'Conflict'; 413 = 'Payload Too Large'; 500 = 'Internal Server Error' }[$res.status]
    if (-not $reason) { $reason = 'OK' }
    $body = $res.body
    if ($null -eq $body) { $body = [byte[]]@() }
    $head = "HTTP/1.1 $($res.status) $reason`r`nContent-Type: $($res.type)`r`nContent-Length: $($body.Length)`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nReferrer-Policy: no-referrer`r`n"
    if ($res.type -like 'text/html*') { $head += "Content-Security-Policy: $csp`r`nX-Frame-Options: DENY`r`n" }
    $head += "Connection: close`r`n`r`n"
    $h = [Text.Encoding]::ASCII.GetBytes($head)
    $stream.Write($h, 0, $h.Length)
    if ($body.Length) { $stream.Write($body, 0, $body.Length) }
    $stream.Flush()
}

# Returns the parsed request, or $null while it is still incomplete.
function Read-Request([IO.MemoryStream]$buf) {
    $bytes = $buf.GetBuffer(); $len = [int]$buf.Length
    $end = -1
    for ($i = 3; $i -lt $len; $i++) {
        if ($bytes[$i] -eq 10 -and $bytes[$i - 1] -eq 13 -and $bytes[$i - 2] -eq 10 -and $bytes[$i - 3] -eq 13) { $end = $i + 1; break }
    }
    if ($end -lt 0) { return $null }
    $lines = [Text.Encoding]::ASCII.GetString($bytes, 0, $end - 4) -split "`r`n"
    $first = $lines[0] -split ' '
    $headers = @{}
    foreach ($line in ($lines | Select-Object -Skip 1)) {
        $c = $line.IndexOf(':')
        if ($c -gt 0) { $headers[$line.Substring(0, $c).Trim().ToLower()] = $line.Substring($c + 1).Trim() }
    }
    $clen = 0
    if ($headers['content-length']) { $clen = [int]$headers['content-length'] }
    if ($clen -gt 64MB) { return @{ tooLarge = $true } }
    if ($len - $end -lt $clen) { return $null }
    $body = New-Object byte[] $clen
    if ($clen) { [Array]::Copy($bytes, $end, $body, 0, $clen) }
    $path = $first[1]; $query = ''
    $q = $path.IndexOf('?'); if ($q -ge 0) { $query = $path.Substring($q + 1); $path = $path.Substring(0, $q) }
    return @{ method = $first[0]; path = [Uri]::UnescapeDataString($path); query = $query; headers = $headers; body = $body }
}

# ---------------------------------------------------------------- routes
$script:running = $true
$script:setupPid = 0
$script:agentStarted = $false

function Get-Status {
    $hw = Get-AIOHardware
    $installed = Test-AIOInstalled
    $setup = Read-AIOJson $AIO.SetupFile
    $setupRunning = $false
    if ($setup -and $setup.state -eq 'running') {
        $setupRunning = [bool](Get-Process -Id $setup.pid -ErrorAction SilentlyContinue)
    }
    [ordered]@{
        app = 'ai-offline'
        version = $Config.version
        installed = $installed
        setupRunning = $setupRunning
        engine = [ordered]@{ url = $AIO.OllamaUrl; running = (Test-AIOOllama); version = $Config.downloads.ollama.version }
        agent = [ordered]@{ installed = (Test-Path -LiteralPath $AIO.OpenCodeExe); url = $AIO.AgentUrl }
        hardware = $hw
        recommended = (Get-AIORecommendedModel $hw)
        catalog = $Config.models
        extraModels = $Config.extraModels
        downloadMB = [ordered]@{
            engine = if ($hw.arch -eq 'arm64') { $Config.downloads.ollama.arm64.sizeMB } else { $Config.downloads.ollama.x64.sizeMB }
            gpu = if (@($hw.gpus | Where-Object { $_.vendor -eq 'amd' }).Count) { $Config.downloads.ollama.rocm.sizeMB } else { 0 }
            agent = $Config.downloads.opencode.x64.sizeMB
        }
        contextLength = (Get-AIOContextLength $hw.ramGB)
        repo = $Config.repo
    }
}

function Start-Setup($req) {
    $info = $utf8.GetString($req.body) | ConvertFrom-Json
    $model = [string]$info.model
    if ($model -notmatch '^[a-z0-9][a-z0-9._-]*(:[a-z0-9._-]+)?$') { return Error-Response 400 'bad model name' }
    $status = Read-AIOJson $AIO.SetupFile
    if ($status -and $status.state -eq 'running' -and (Get-Process -Id $status.pid -ErrorAction SilentlyContinue)) { return Json-Response @{ ok = $true; already = $true } }
    $shortcuts = if ($info.shortcuts -eq $false) { '0' } else { '1' }
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argList = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $AIO.App 'setup.ps1') + '" -Model ' + $model + ' -Shortcuts ' + $shortcuts
    $p = Start-Process -FilePath $ps -ArgumentList $argList -WindowStyle Hidden -PassThru
    $script:setupPid = $p.Id
    # the worker needs a few seconds to start; until it reports, show "starting"
    Write-AIOText $AIO.SetupFile (ConvertTo-AIOJson ([ordered]@{ state = 'running'; pid = $p.Id; model = $model; step = 'engine'; steps = @{}; detail = 'starting' }))
    Log "setup started (pid $($p.Id), model $model)"
    Json-Response @{ ok = $true }
}

function Stop-Setup {
    $status = Read-AIOJson $AIO.SetupFile
    if ($status -and $status.pid) { Stop-Process -Id $status.pid -Force -ErrorAction SilentlyContinue }
    if ($status) {
        $status.state = 'cancelled'
        Write-AIOText $AIO.SetupFile (ConvertTo-AIOJson $status)
    }
    Json-Response @{ ok = $true }
}

function Start-Agent {
    if (-not (Test-Path -LiteralPath $AIO.OpenCodeExe)) { return Error-Response 409 'agent-missing' }
    if (-not (Start-AIOOllama -Wait)) { return Error-Response 500 'engine-start-failed' }
    $main = Write-AIOAgentConfig
    if (-not $main) { return Error-Response 409 'no-models' }
    if (Test-AIOHttp "$($AIO.AgentUrl)/" 1500) { return Json-Response @{ ok = $true; url = "$($AIO.AgentUrl)/"; opened = $false } }
    Set-AIOEnvironment
    $userHome = [Environment]::GetFolderPath('UserProfile')
    Start-AIOHidden $AIO.OpenCodeExe "web --port $($Config.ports.agent) --hostname 127.0.0.1" 'agent.log' $userHome | Out-Null
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 500
        if (Test-AIOHttp "$($AIO.AgentUrl)/" 1500) { return Json-Response @{ ok = $true; url = "$($AIO.AgentUrl)/"; opened = $true } }
    }
    Error-Response 500 'agent-start-failed'
}

function Invoke-Route($req) {
    $path = $req.path
    $m = $req.method

    if (-not $path.StartsWith('/api/local/')) {
        if ($m -ne 'GET') { return Error-Response 405 'method not allowed' }
        if ($path -eq '/' -or $path -eq '') { $path = '/index.html' }
        $rel = $path.TrimStart('/').Replace('/', '\')
        $file = [IO.Path]::GetFullPath((Join-Path $AIO.UI $rel))
        if (-not $file.StartsWith($AIO.UI + '\', [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $file -PathType Leaf)) {
            return Error-Response 404 'not found'
        }
        $type = $mime[[IO.Path]::GetExtension($file).ToLower()]
        if (-not $type) { $type = 'application/octet-stream' }
        return New-Response 200 $type ([IO.File]::ReadAllBytes($file))
    }

    $route = $path.Substring('/api/local/'.Length)
    switch -Regex ($route) {
        '^ping$' { return Json-Response @{ app = 'ai-offline'; version = $Config.version } }
        '^status$' { return Json-Response (Get-Status) }
        '^setup$' {
            if ($m -eq 'POST') { return Start-Setup $req }
            $text = if (Test-Path -LiteralPath $AIO.SetupFile) { [IO.File]::ReadAllText($AIO.SetupFile, [Text.Encoding]::UTF8) } else { '{"state":"idle"}' }
            return Raw-Json $text
        }
        '^setup/cancel$' { return Stop-Setup }
        '^engine/start$' { return Json-Response @{ ok = (Start-AIOOllama -Wait) } }
        '^agent/start$' { return Start-Agent }
        '^agent/config$' { return Json-Response @{ model = (Write-AIOAgentConfig) } }
        '^shortcuts$' { New-AIOShortcuts $true $true; return Json-Response @{ ok = $true } }
        '^open-folder$' { Start-Process explorer.exe -ArgumentList ('"' + $AIO.Root + '"'); return Json-Response @{ ok = $true } }
        '^quit$' {
            $script:running = $false
            return Json-Response @{ ok = $true }
        }
        '^store/([a-z0-9][a-z0-9_.-]{0,100})$' {
            $file = Join-Path $AIO.Store ($Matches[1] + '.json')
            if ($m -eq 'GET') {
                if (Test-Path -LiteralPath $file) { return New-Response 200 'application/json; charset=utf-8' ([IO.File]::ReadAllBytes($file)) }
                return Raw-Json 'null'
            }
            if ($m -eq 'PUT') {
                $tmp = "$file.tmp"
                [IO.File]::WriteAllBytes($tmp, $req.body)
                Move-Item -LiteralPath $tmp -Destination $file -Force
                return Json-Response @{ ok = $true }
            }
            if ($m -eq 'DELETE') { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue; return Json-Response @{ ok = $true } }
            return Error-Response 405 'method not allowed'
        }
    }
    return Error-Response 404 'unknown route'
}

# Requests must come from this page: right Host, and for the API the custom header plus our origin.
function Test-Allowed($req) {
    $hostHeader = [string]$req.headers['host']
    if ($hostHeader -ne "127.0.0.1:$port" -and $hostHeader -ne "localhost:$port") { return $false }
    if ($req.path.StartsWith('/api/local/')) {
        if ($req.headers['x-aio'] -ne '1') { return $false }
        $o = [string]$req.headers['origin']
        if ($o -and $o -ne $origin -and $o -ne "http://localhost:$port") { return $false }
    }
    return $true
}

# ---------------------------------------------------------------- main loop
# A tiny event loop: it never waits on an idle connection, so one slow socket can't block the app.
$conns = New-Object Collections.ArrayList
$chunk = New-Object byte[] 65536
try {
    while ($script:running) {
        while ($listener.Pending()) {
            $c = $listener.AcceptTcpClient()
            $c.NoDelay = $true
            [void]$conns.Add(@{ client = $c; buf = New-Object IO.MemoryStream; since = [DateTime]::UtcNow })
        }
        $busy = $false
        foreach ($cx in @($conns)) {
            $client = $cx.client
            $drop = $false
            try {
                $ns = $client.GetStream()
                while ($client.Available -gt 0) {
                    $n = $ns.Read($chunk, 0, [Math]::Min($chunk.Length, $client.Available))
                    if ($n -le 0) { break }
                    $cx.buf.Write($chunk, 0, $n)
                    $busy = $true
                }
                $req = Read-Request $cx.buf
                if ($req) {
                    if ($req.tooLarge) { $res = Error-Response 413 'too large' }
                    elseif ($req.method -eq 'OPTIONS' -or -not (Test-Allowed $req)) { $res = Error-Response 403 'forbidden' }
                    else {
                        try { $res = Invoke-Route $req } catch {
                            Log "error on $($req.method) $($req.path): $($_.Exception.Message)"
                            $res = Error-Response 500 $_.Exception.Message
                        }
                    }
                    Send-Response $ns $res
                    $drop = $true
                } elseif (([DateTime]::UtcNow - $cx.since).TotalSeconds -gt 20) { $drop = $true }
            } catch { $drop = $true }
            if ($drop) {
                try { $client.Close() } catch { }
                $conns.Remove($cx)
            }
        }
        if (-not $busy) { Start-Sleep -Milliseconds 12 }
    }
} finally {
    Log 'server stopping'
    Start-Sleep -Milliseconds 200
    foreach ($cx in @($conns)) { try { $cx.client.Close() } catch { } }
    $listener.Stop()
    Stop-AIOEngine
    Remove-Item -LiteralPath $AIO.ServerFile -Force -ErrorAction SilentlyContinue
}
