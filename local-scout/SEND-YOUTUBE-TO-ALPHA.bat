@echo off
cd /d "%~dp0"
echo Checking for latest Alpha Scout fix...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/drrohanvirani/alpha-sniper-cockpit/alpha-local-scout-v1/local-scout/SEND-YOUTUBE-TO-ALPHA.ps1' -OutFile '%~dp0SEND-YOUTUBE-TO-ALPHA.ps1' } catch { Write-Host 'Update skipped - using local copy.' }"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0SEND-YOUTUBE-TO-ALPHA.ps1"
echo.
pause
