@echo off
title Build Scholaxia Windows Installer
cd /d "%~dp0"

echo.
echo Building Scholaxia STUDENT app for Windows...
echo Admin and teacher portals are NOT included in this installer.
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

call npm run build:all
if errorlevel 1 (
  echo Build failed.
  pause
  exit /b 1
)

echo.
echo Done! Send these files to your friend:
echo   dist\Scholaxia Student Setup *.exe   ^(installer^)
echo   dist\Scholaxia-Portable.exe            ^(no install needed^)
echo   INSTALL-FOR-FRIEND.txt                 ^(instructions^)
echo.
pause
