@echo off
cd /d "%~dp0"

if not exist "%~dp0install-windows.ps1" (
  echo.
  echo ==========================================
  echo STOP: You are running this from inside the ZIP.
  echo Click EXTRACT ALL first, open the extracted folder,
  echo then run RUN-ME-FIRST.bat again.
  echo ==========================================
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-windows.ps1"
if errorlevel 1 (
  echo.
  echo ==========================================
  echo SETUP DID NOT COMPLETE.
  echo Send a screenshot of the error to ChatGPT.
  echo ==========================================
  pause
  exit /b 1
)

echo.
echo ==========================================
echo SETUP COMPLETE. YOU ARE DONE.
echo ==========================================
pause
