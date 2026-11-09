@echo off
rem Adds "Open AI coding agent here" to the right-click menu of folders (only for your user).
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\app\tools.ps1" -Action add-menu
