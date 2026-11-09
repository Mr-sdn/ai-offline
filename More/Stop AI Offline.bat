@echo off
rem Stops AI Offline and frees the memory it uses. Open it again any time with AI Offline.bat.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\app\tools.ps1" -Action stop
