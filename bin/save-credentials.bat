@echo off
powershell.exe -NoProfile -File "%~dp0save-credentials.ps1" %*
exit /b %ERRORLEVEL%
