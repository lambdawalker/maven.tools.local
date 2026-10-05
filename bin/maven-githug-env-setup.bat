@echo off
powershell.exe -NoProfile -File "%~dp0maven-github-env-setup.ps1" %*
exit /b %ERRORLEVEL%
