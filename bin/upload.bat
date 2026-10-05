@echo off
powershell.exe -NoProfile -File "%~dp0upload.ps1" %*
exit /b %ERRORLEVEL%
