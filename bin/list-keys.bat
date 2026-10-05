@echo off
powershell.exe -NoProfile -File "%~dp0list-keys.ps1" %*
exit /b %ERRORLEVEL%
