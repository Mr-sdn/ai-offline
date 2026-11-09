# AI Offline - shared paths and helpers. Dot-sourced by the other scripts.
# Everything lives inside the AI Offline folder, so the folder can be moved or copied to another PC.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$AIO = @{}
$AIO.App = $PSScriptRoot
$AIO.Root = Split-Path -Parent $PSScriptRoot
$AIO.UI = Join-Path $AIO.App 'ui'
$AIO.Runtime = Join-Path $AIO.Root 'runtime'
$AIO.Data = Join-Path $AIO.Root 'data'
$AIO.Logs = Join-Path $AIO.Data 'logs'
$AIO.Store = Join-Path $AIO.Data 'store'
$AIO.Downloads = Join-Path $AIO.Data 'downloads'
$AIO.AgentHome = Join-Path $AIO.Data 'agent'
$AIO.Models = if ($env:AIO_MODELS) { $env:AIO_MODELS } else { Join-Path $AIO.Root 'models' }
$AIO.OllamaExe = if ($env:AIO_OLLAMA_EXE) { $env:AIO_OLLAMA_EXE } else { Join-Path $AIO.Runtime 'ollama\ollama.exe' }
$AIO.OpenCodeExe = if ($env:AIO_OPENCODE_EXE) { $env:AIO_OPENCODE_EXE } else { Join-Path $AIO.Runtime 'opencode\opencode.exe' }
$AIO.SetupFile = Join-Path $AIO.Data 'setup.json'
$AIO.InstalledFile = Join-Path $AIO.Data 'installed.json'
$AIO.ServerFile = Join-Path $AIO.Data 'server.json'

$Config = [IO.File]::ReadAllText((Join-Path $AIO.App 'config.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
$AIO.OllamaUrl = "http://127.0.0.1:$($Config.ports.ollama)"
$AIO.AgentUrl = "http://127.0.0.1:$($Config.ports.agent)"

function Initialize-AIODirs {
    foreach ($d in $AIO.Data, $AIO.Logs, $AIO.Store, $AIO.Downloads, $AIO.AgentHome, $AIO.Models) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}

function Write-AIOLog([string]$file, [string]$message) {
    try {
        $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $message
        [IO.File]::AppendAllText((Join-Path $AIO.Logs $file), $line + "`r`n", [Text.UTF8Encoding]::new($false))
    } catch { }
}

# Write a file in one step, so a reader never sees half of it.
function Write-AIOText([string]$path, [string]$text) {
    $tmp = "$path.$PID.tmp"
    [IO.File]::WriteAllText($tmp, $text, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

function ConvertTo-AIOJson($value) { $value | ConvertTo-Json -Depth 12 -Compress }

function Read-AIOJson([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    for ($i = 0; $i -lt 5; $i++) {
        try { return ([IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json) } catch { Start-Sleep -Milliseconds 60 }
    }
    return $null
}

# Settings for the engine and the coding agent. Child processes inherit them.
function Set-AIOEnvironment {
    $hw = Get-AIOHardware
    $env:OLLAMA_HOST = "127.0.0.1:$($Config.ports.ollama)"
    $env:OLLAMA_MODELS = $AIO.Models
    $env:OLLAMA_NO_CLOUD = '1'
    $env:OLLAMA_NOPRUNE = '1'
    if (-not $env:OLLAMA_CONTEXT_LENGTH) { $env:OLLAMA_CONTEXT_LENGTH = [string](Get-AIOContextLength $hw.ramGB) }
    $env:XDG_DATA_HOME = Join-Path $AIO.AgentHome 'data'
    $env:XDG_CONFIG_HOME = Join-Path $AIO.AgentHome 'config'
    $env:XDG_CACHE_HOME = Join-Path $AIO.AgentHome 'cache'
    $env:XDG_STATE_HOME = Join-Path $AIO.AgentHome 'state'
    $env:OPENCODE_CONFIG = Join-Path $AIO.AgentHome 'opencode.json'
    $env:OPENCODE_DISABLE_AUTOUPDATE = '1'
    $env:OPENCODE_DISABLE_MODELS_FETCH = '1'
    $env:OPENCODE_DISABLE_LSP_DOWNLOAD = '1'
    $env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'
    $env:DISABLE_AUTOUPDATER = '1'
    $dirs = @((Split-Path -Parent $AIO.OllamaExe), (Split-Path -Parent $AIO.OpenCodeExe))
    $env:PATH = ($dirs -join ';') + ';' + $env:PATH
}

function Get-AIOContextLength([double]$ramGB) {
    if ($ramGB -ge 30) { return 65536 }
    if ($ramGB -ge 22) { return 32768 }
    if ($ramGB -ge 12) { return 16384 }
    return 8192
}

# ---------------------------------------------------------------- hardware
$script:AIOHardware = $null
function Get-AIOHardware {
    if ($script:AIOHardware) { return $script:AIOHardware }
    $ramGB = 0
    try { $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1) } catch { }

    # Video memory: the registry has the real size (Win32_VideoController stops at 4 GB)
    $reg = @()
    try { $reg = @(Get-ItemProperty 'HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0*' -ErrorAction SilentlyContinue) } catch { }
    $gpus = @()
    try {
        foreach ($v in @(Get-CimInstance Win32_VideoController)) {
            $bytes = 0.0
            $r = $reg | Where-Object { $_.DriverDesc -eq $v.Name } | Select-Object -First 1
            if ($r) {
                foreach ($name in 'HardwareInformation.qwMemorySize', 'HardwareInformation.MemorySize') {
                    $val = $r.$name
                    if ($null -eq $val) { continue }
                    if ($val -is [byte[]]) {
                        if ($val.Length -ge 8) { $bytes = [double][BitConverter]::ToUInt64($val, 0) } elseif ($val.Length -ge 4) { $bytes = [double][BitConverter]::ToUInt32($val, 0) }
                    } else { $bytes = [double]$val }
                    if ($bytes -gt 0) { break }
                }
            }
            if ($bytes -le 0 -and $v.AdapterRAM) { $bytes = [double][uint32]$v.AdapterRAM }
            $vendor = 'other'
            if ($v.Name -match 'NVIDIA|GeForce|Quadro|RTX') { $vendor = 'nvidia' }
            elseif ($v.Name -match 'AMD|Radeon') { $vendor = 'amd' }
            elseif ($v.Name -match 'Intel') { $vendor = 'intel' }
            if ($v.Name -match 'Microsoft Basic|Remote Display|Virtual') { continue }
            $gpus += [pscustomobject]@{ name = [string]$v.Name; vendor = $vendor; vramGB = [math]::Round($bytes / 1GB, 1) }
        }
    } catch { }

    $cpu = ''
    try { $cpu = [string](Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim() } catch { }
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    $avx2 = $true
    try {
        if (-not ('AIO.Cpu' -as [type])) {
            Add-Type -Namespace AIO -Name Cpu -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool IsProcessorFeaturePresent(uint feature);'
        }
        $avx2 = [AIO.Cpu]::IsProcessorFeaturePresent(40)
    } catch { }

    $freeGB = 0
    try { $freeGB = [math]::Round(([IO.DriveInfo]::new([IO.Path]::GetPathRoot($AIO.Root))).AvailableFreeSpace / 1GB, 1) } catch { }

    $warnings = @()
    if ($AIO.Root -match '\\OneDrive') { $warnings += 'onedrive' }
    if ($AIO.Root.StartsWith($env:TEMP, [StringComparison]::OrdinalIgnoreCase)) { $warnings += 'temp' }

    $script:AIOHardware = [pscustomobject]@{
        ramGB = $ramGB
        gpus = $gpus
        cpu = $cpu
        arch = if ($arch -eq 'ARM64') { 'arm64' } else { 'x64' }
        avx2 = [bool]$avx2
        freeGB = $freeGB
        drive = [IO.Path]::GetPathRoot($AIO.Root)
        folder = $AIO.Root
        warnings = $warnings
    }
    return $script:AIOHardware
}

# The biggest model this PC can run comfortably and has room for.
function Get-AIORecommendedModel($hw) {
    $pick = $Config.models[0]
    foreach ($m in $Config.models) {
        if ($hw.ramGB -ge $m.minRamGB -and $hw.freeGB -ge ($m.sizeGB + 5)) { $pick = $m }
    }
    return $pick.id
}

# ---------------------------------------------------------------- processes
function Test-AIOHttp([string]$url, [int]$timeoutMs = 1500) {
    # Windows takes about a second to give up on a closed local port, so check the port quickly first
    try {
        $u = [Uri]$url
        $tcp = New-Object Net.Sockets.TcpClient
        $ok = $tcp.ConnectAsync($u.Host, $u.Port).Wait(400) -and $tcp.Connected
        $tcp.Close()
        if (-not $ok) { return $false }
    } catch { return $false }
    try {
        $req = [Net.HttpWebRequest]::Create($url)
        $req.Timeout = $timeoutMs
        $req.Proxy = $null
        $resp = $req.GetResponse()
        $resp.Close()
        return $true
    } catch [Net.WebException] {
        # an HTTP error still means something is listening
        return ($null -ne $_.Exception.Response)
    } catch { return $false }
}

function Test-AIOOllama { Test-AIOHttp "$($AIO.OllamaUrl)/api/version" }

function Test-AIOInstalled {
    (Test-Path -LiteralPath $AIO.OllamaExe) -and (Test-Path -LiteralPath $AIO.InstalledFile)
}

# Start a console program with no window; its output goes to a log file.
function Start-AIOHidden([string]$exe, [string]$arguments, [string]$logName, [string]$workDir) {
    $log = Join-Path $AIO.Logs $logName
    try { if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 5MB) { Move-Item -LiteralPath $log -Destination "$log.old" -Force } } catch { }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $psi.Arguments = '/d /c ""' + $exe + '" ' + $arguments + ' >> "' + $log + '" 2>&1"'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = if ($workDir) { $workDir } else { $AIO.Root }
    return [Diagnostics.Process]::Start($psi)
}

function Start-AIOOllama([switch]$Wait) {
    if (Test-AIOOllama) { return $true }
    if (-not (Test-Path -LiteralPath $AIO.OllamaExe)) { return $false }
    Set-AIOEnvironment
    Write-AIOLog 'server.log' "starting engine: $($AIO.OllamaExe)"
    Start-AIOHidden $AIO.OllamaExe 'serve' 'ollama.log' | Out-Null
    if (-not $Wait) { return $true }
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 500
        if (Test-AIOOllama) { return $true }
    }
    return $false
}

function Get-AIOProcesses([string]$exe) {
    $full = [IO.Path]::GetFullPath($exe)
    $name = [IO.Path]::GetFileNameWithoutExtension($exe)
    @(Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and ([IO.Path]::GetFullPath($_.Path) -eq $full) } catch { $false }
    })
}

function Stop-AIOEngine {
    foreach ($p in (Get-AIOProcesses $AIO.OpenCodeExe)) { try { Stop-Process -Id $p.Id -Force } catch { } }
    foreach ($p in (Get-AIOProcesses $AIO.OllamaExe)) { try { Stop-Process -Id $p.Id -Force } catch { } }
}

# ---------------------------------------------------------------- engine API
function Invoke-AIOOllama([string]$path, [string]$method = 'GET', $body = $null) {
    $p = @{ Uri = "$($AIO.OllamaUrl)$path"; Method = $method; UseBasicParsing = $true; TimeoutSec = 30 }
    if ($null -ne $body) { $p.Body = [Text.Encoding]::UTF8.GetBytes((ConvertTo-AIOJson $body)); $p.ContentType = 'application/json' }
    Invoke-RestMethod @p
}

function Get-AIOInstalledModels {
    try { return @((Invoke-AIOOllama '/api/tags').models) } catch { return @() }
}

# ---------------------------------------------------------------- coding agent
# Writes the OpenCode settings: only the local engine, every installed model, nothing online.
function Write-AIOAgentConfig {
    $installed = @(Get-AIOInstalledModels)
    $settings = Read-AIOJson (Join-Path $AIO.Store 'settings.json')
    $order = @($Config.models | ForEach-Object { $_.id })
    $names = @($installed | ForEach-Object { $_.name })
    # coding needs the strongest model, so the best installed one from the list wins
    $main = $null
    foreach ($id in $order) { if ($names -contains $id) { $main = $id } }
    if (-not $main -and $settings -and $settings.model -and ($names -contains $settings.model)) { $main = $settings.model }
    if (-not $main -and $names.Count) { $main = $names[0] }
    $small = $main
    foreach ($id in $order) { if ($names -contains $id) { $small = $id; break } }

    $ctx = [int](Get-AIOContextLength (Get-AIOHardware).ramGB)
    $models = [ordered]@{}
    foreach ($n in $names) {
        $entry = [ordered]@{
            name = $n
            tool_call = $true
            limit = [ordered]@{ context = $ctx; output = 8192 }
        }
        if ($n -like 'qwen3*') {
            $entry.reasoning = $true
            $entry.variants = [ordered]@{
                high = @{ disabled = $true }; medium = @{ disabled = $true }; low = @{ disabled = $true }
                none = @{ reasoningEffort = 'none' }
            }
        }
        $models[$n] = $entry
    }
    $cfg = [ordered]@{
        '$schema' = 'https://opencode.ai/config.json'
        autoupdate = $false
        share = 'disabled'
        enabled_providers = @('aioffline')
        provider = [ordered]@{
            aioffline = [ordered]@{
                name = 'AI Offline (this computer)'
                npm = '@ai-sdk/openai-compatible'
                options = [ordered]@{ baseURL = "$($AIO.OllamaUrl)/v1" }
                models = $models
            }
        }
    }
    if ($main) { $cfg.model = "aioffline/$main"; $cfg.small_model = "aioffline/$small" }
    Write-AIOText (Join-Path $AIO.AgentHome 'opencode.json') ($cfg | ConvertTo-Json -Depth 12)
    return $main
}

# ---------------------------------------------------------------- shortcuts
function Get-AIOLauncherArgs { '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $AIO.App 'server.ps1') + '"' }

function New-AIOShortcuts([bool]$desktop = $true, [bool]$startMenu = $true) {
    $sh = New-Object -ComObject WScript.Shell
    $targets = @()
    if ($desktop) { $targets += [Environment]::GetFolderPath('Desktop') }
    if ($startMenu) { $targets += [Environment]::GetFolderPath('Programs') }
    foreach ($dir in $targets) {
        $lnk = $sh.CreateShortcut((Join-Path $dir 'AI Offline.lnk'))
        $lnk.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $lnk.Arguments = Get-AIOLauncherArgs
        $lnk.WorkingDirectory = $AIO.Root
        $lnk.IconLocation = (Join-Path $AIO.UI 'icon.ico') + ',0'
        $lnk.WindowStyle = 7
        $lnk.Description = 'AI Offline - private AI on this computer'
        $lnk.Save()
    }
}

function Remove-AIOShortcuts {
    foreach ($dir in [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs')) {
        Remove-Item -LiteralPath (Join-Path $dir 'AI Offline.lnk') -Force -ErrorAction SilentlyContinue
    }
}

# Right-click a folder -> "Open AI coding agent here"
function Add-AIOContextMenu([string]$label) {
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $cmd = '"' + $ps + '" -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $AIO.App 'agent.ps1') + '" -Dir "%V"'
    foreach ($base in 'HKCU:\Software\Classes\Directory\shell', 'HKCU:\Software\Classes\Directory\Background\shell') {
        $k = "$base\AIOfflineAgent"
        New-Item -Path "$k\command" -Force | Out-Null
        Set-ItemProperty -Path $k -Name 'MUIVerb' -Value $label
        Set-ItemProperty -Path $k -Name 'Icon' -Value (Join-Path $AIO.UI 'icon.ico')
        Set-ItemProperty -Path "$k\command" -Name '(default)' -Value $cmd
    }
}

function Remove-AIOContextMenu {
    foreach ($base in 'HKCU:\Software\Classes\Directory\shell', 'HKCU:\Software\Classes\Directory\Background\shell') {
        Remove-Item -Path "$base\AIOfflineAgent" -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------- browser
# Opens the UI as an app window (Edge or Chrome) when possible, otherwise in the default browser.
function Open-AIOBrowser([string]$url) {
    if ($env:AIO_NO_BROWSER) { return }
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) {
            try { Start-Process -FilePath $c -ArgumentList "--app=$url", '--window-size=1280,860'; return } catch { }
        }
    }
    Start-Process $url
}

function Show-AIOMessage([string]$text, [string]$title = 'AI Offline') {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.MessageBox]::Show($text, $title, 'OK', 'Warning') | Out-Null
    } catch { Write-Host $text }
}
