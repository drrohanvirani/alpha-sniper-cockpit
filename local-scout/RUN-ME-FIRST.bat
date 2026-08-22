@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-windows.ps1"
echo.
echo ==========================================
echo If you see SETUP COMPLETE above, you are DONE.
echo ==========================================
pause
