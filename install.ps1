# AI Offline - one-line install (or update) for Windows:
#   irm https://raw.githubusercontent.com/Mr-sdn/ai-offline/main/install.ps1 | iex
# Downloads the latest release into X:\AI-Offline (the fixed drive with the most free space)
# and starts it. Set $env:AIO_DIR first to choose another folder. Running it again updates the
# app files and keeps your models, chats and settings.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$target = $env:AIO_DIR
if (-not $target) {
    $drive = [IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -eq 'Fixed' } | Sort-Object AvailableFreeSpace -Descending | Select-Object -First 1
    $target = Join-Path $drive.RootDirectory.FullName 'AI-Offline'
}
Write-Host ''
Write-Host '  AI Offline - private AI on your own computer' -ForegroundColor Green
Write-Host "  Folder: $target"
Write-Host ''

$zip = Join-Path $env:TEMP 'AI-Offline.zip'
$tmp = Join-Path $env:TEMP ('AI-Offline-' + [guid]::NewGuid().ToString('N'))
Write-Host '  Downloading the latest version...'
Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/Mr-sdn/ai-offline/releases/latest/download/AI-Offline.zip' -OutFile $zip
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)
$src = Join-Path $tmp 'AI-Offline'
if (-not (Test-Path $src)) { $src = $tmp }
New-Item -ItemType Directory -Force -Path $target | Out-Null
Copy-Item -Path (Join-Path $src '*') -Destination $target -Recurse -Force
Get-ChildItem -Path $target -Recurse -File -Include *.bat, *.ps1 | Unblock-File -ErrorAction SilentlyContinue
Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host '  Starting AI Offline. Follow the steps in the window that opens.' -ForegroundColor Green
Start-Process -FilePath (Join-Path $target 'AI Offline.bat') -WorkingDirectory $target
