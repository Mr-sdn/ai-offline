@echo off
rem For advanced users: a command prompt where the ollama command uses AI Offline's engine and models.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\app\tools.ps1" -Action console
