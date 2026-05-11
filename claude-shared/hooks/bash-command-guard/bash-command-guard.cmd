:<<"::CMDLITERAL"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bash-command-guard.ps1"
exit /b %ERRORLEVEL%
::CMDLITERAL
exec bash "$(dirname "$0")/bash-command-guard.sh"
