@echo off
title Build Scholaxia Student Windows Installer
cd /d "%~dp0"

echo.
echo Building Scholaxia STUDENT for Windows (installer + portable)...
echo Output:
echo   dist\Scholaxia-Student-Setup-*.exe
echo   dist\Scholaxia-Student-Portable-*.exe
echo Admin and teacher portals are NOT included.
echo.

if exist "D:\node.exe" (
  set "PATH=D:\;%PATH%"
  set "npm_config_cache=D:\tmp\npm-cache"
  set "TEMP=D:\tmp"
  set "TMP=D:\tmp"
)

if not exist "node_modules\electron-builder" (
  echo Installing build tools...
  call npm install
  if errorlevel 1 (
    echo Build failed. Free disk space and run again.
    pause
    exit /b 1
  )
)

call npm run build:installer
if errorlevel 1 (
  echo Build failed.
  pause
  exit /b 1
)

echo.
echo Done! Share ONLY this file with students:
echo   dist\Scholaxia-Student-Setup-*.exe
echo.
echo Also send INSTALL-FOR-FRIEND.txt with install instructions.
echo Do NOT share win-unpacked folder or START.bat.
echo.
pause
