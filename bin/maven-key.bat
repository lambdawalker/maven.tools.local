@echo off
powershell.exe -NoProfile -File "%~dp0maven-key.ps1" %*
exit /b %ERRORLEVEL%
