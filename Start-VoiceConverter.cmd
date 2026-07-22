@echo off
setlocal
set "GUI_SCRIPT=%~dp0QQ-Silk-Converter-GUI.ps1"
if not exist "%GUI_SCRIPT%" set "GUI_SCRIPT=%~dp0scripts\QQ-Silk-Converter-GUI.ps1"

if not exist "%GUI_SCRIPT%" (
  echo.
  echo [Error] QQ-Silk-Converter-GUI.ps1 was not found.
  echo Please extract the complete Release ZIP instead of copying only this CMD file.
  pause
  exit /b 2
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%GUI_SCRIPT%"
if errorlevel 1 (
  echo.
  echo The converter could not start. See the message above for details.
  pause
  exit /b 1
)
endlocal
