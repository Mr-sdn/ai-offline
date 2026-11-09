@echo off
rem AI Offline - double-click to start. The first time, it sets everything up.
setlocal
if not exist "%~dp0app\server.ps1" goto notextracted
start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0app\server.ps1"
exit /b 0

:notextracted
echo.
echo   AI Offline has to be unzipped first.
echo   Right-click the ZIP file, choose "Extract All", open the new folder
echo   and double-click "AI Offline.bat" there.
echo.
pause
exit /b 1
