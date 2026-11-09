@echo off
rem Stops AI Offline and removes its shortcuts and menu items. Then delete the folder to remove everything.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\app\tools.ps1" -Action uninstall
