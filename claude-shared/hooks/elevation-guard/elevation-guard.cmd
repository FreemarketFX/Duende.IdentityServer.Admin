:<<"::CMDLITERAL"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0elevation-guard.ps1"
exit /b %ERRORLEVEL%
::CMDLITERAL
exec bash "$(dirname "$0")/elevation-guard.sh"
