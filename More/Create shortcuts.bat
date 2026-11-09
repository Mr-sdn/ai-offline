@echo off
rem Puts "AI Offline" on the desktop and in the Start menu.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\app\tools.ps1" -Action shortcuts
