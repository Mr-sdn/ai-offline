# AI Offline - opens the coding agent (OpenCode) in a terminal, inside a project folder.
# Used by "More\Coding agent in a folder.bat" and the right-click menu.
param([string]$Dir, [switch]$Pick)
. (Join-Path $PSScriptRoot 'common.ps1')
Initialize-AIODirs
$ErrorActionPreference = 'Continue'

function Stop-WithMessage([string]$text) {
    Write-Host ''
    Write-Host "  $text" -ForegroundColor Yellow
    Write-Host ''
    Read-Host '  Press Enter to close'
    exit 1
}

if (-not (Test-AIOInstalled) -or -not (Test-Path -LiteralPath $AIO.OpenCodeExe)) {
    Stop-WithMessage "AI Offline is not set up yet. Double-click 'AI Offline.bat' first."
}

if ($Pick) {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Choose the project folder for the AI coding agent'
    $dlg.ShowNewFolderButton = $true
    if ($dlg.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { exit 0 }
    $Dir = $dlg.SelectedPath
}
if (-not $Dir) { $Dir = [Environment]::GetFolderPath('MyDocuments') }
if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { Stop-WithMessage "Folder not found: $Dir" }

Write-Host '  Starting the AI engine...' -ForegroundColor DarkGray
if (-not (Start-AIOOllama -Wait)) { Stop-WithMessage 'The AI engine did not start. See data\logs\ollama.log in the AI Offline folder.' }
$main = Write-AIOAgentConfig
if (-not $main) { Stop-WithMessage "No AI model is installed. Open 'AI Offline' and download one under Models." }

Set-AIOEnvironment
Set-Location -LiteralPath $Dir
$Host.UI.RawUI.WindowTitle = "AI coding agent ($main) - $Dir"
Write-Host "  Model: $main   Folder: $Dir" -ForegroundColor DarkGray
Write-Host '  Inside: /new = new chat, /sessions = old chats, /models = change model, Ctrl+C = exit' -ForegroundColor DarkGray
& $AIO.OpenCodeExe
