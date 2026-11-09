@echo off
rem Opens the AI coding agent (OpenCode) in a terminal, inside a folder you choose.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\app\agent.ps1" -Pick
