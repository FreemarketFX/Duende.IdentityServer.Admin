:<<"::CMDLITERAL"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0version-check.ps1"
exit /b %ERRORLEVEL%
::CMDLITERAL
exec bash "$(dirname "$0")/version-check.sh"
