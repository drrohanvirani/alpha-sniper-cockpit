@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0SEND-YOUTUBE-TO-ALPHA.ps1"
echo.
pause
