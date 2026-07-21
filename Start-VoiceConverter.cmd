@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0QQ-Silk-Converter-GUI.ps1"
if errorlevel 1 (
  echo.
  echo The converter could not start. See the message above for details.
  pause
)
endlocal
