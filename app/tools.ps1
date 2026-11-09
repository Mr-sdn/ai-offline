# AI Offline - small maintenance actions used by the files in the "More" folder.
param([Parameter(Mandatory = $true)][ValidateSet('stop', 'add-menu', 'remove-menu', 'shortcuts', 'uninstall', 'console')][string]$Action)
. (Join-Path $PSScriptRoot 'common.ps1')
Initialize-AIODirs
$ErrorActionPreference = 'Continue'

function Get-Text([string]$key) {
    $strings = [IO.File]::ReadAllText((Join-Path $AIO.App 'strings.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
    $settings = Read-AIOJson (Join-Path $AIO.Store 'settings.json')
    $lang = if ($settings -and $settings.lang -eq 'fa') { 'fa' } else { 'en' }
    return $strings.$lang.$key
}

function Stop-All {
    $server = Read-AIOJson $AIO.ServerFile
    if ($server -and $server.pid) { Stop-Process -Id $server.pid -Force -ErrorAction SilentlyContinue }
    Stop-AIOEngine
    Remove-Item -LiteralPath $AIO.ServerFile -Force -ErrorAction SilentlyContinue
}

switch ($Action) {
    'stop' {
        Stop-All
        Write-Host '  AI Offline has stopped. Memory is free again.' -ForegroundColor Green
    }
    'add-menu' {
        Add-AIOContextMenu (Get-Text 'menuAgent')
        Write-Host '  Done. Right-click any folder (Windows 11: "Show more options") -> "Open AI coding agent here".' -ForegroundColor Green
    }
    'remove-menu' {
        Remove-AIOContextMenu
        Write-Host '  The right-click menu item was removed.' -ForegroundColor Green
    }
    'shortcuts' {
        New-AIOShortcuts $true $true
        Write-Host '  "AI Offline" is now on your desktop and in the Start menu.' -ForegroundColor Green
    }
    'uninstall' {
        Stop-All
        Remove-AIOShortcuts
        Remove-AIOContextMenu
        Write-Host ''
        Write-Host '  Shortcuts and menu items were removed. AI Offline never changed anything else on this PC.' -ForegroundColor Green
        Write-Host "  To remove everything (models included), delete this folder:" -ForegroundColor Green
        Write-Host "    $($AIO.Root)" -ForegroundColor White
        Start-Process explorer.exe -ArgumentList ('"' + (Split-Path -Parent $AIO.Root) + '"')
    }
    'console' {
        if (-not (Start-AIOOllama -Wait)) { Write-Host '  The AI engine did not start. See data\logs\ollama.log' -ForegroundColor Yellow }
        Set-AIOEnvironment
        $intro = 'echo. & echo   Ollama command line for AI Offline. Examples: & echo     ollama list                 installed models & echo     ollama run gemma4:e4b       chat in the terminal & echo     ollama pull qwen3.5:9b      download another model & echo     ollama launch claude        use Claude Code with a local model & echo.'
        Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList '/k', $intro -WorkingDirectory $AIO.Root
        exit 0
    }
}
Write-Host ''
Read-Host '  Press Enter to close'
