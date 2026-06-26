@echo off
title Scholaxia Student
cd /d "%~dp0"

REM Node.js on D: drive
set "NODE=D:\node.exe"
set "NPM=D:\npm.cmd"
set "PATH=D:\;%PATH%"
set "npm_config_cache=D:\tmp\npm-cache"
set "TEMP=D:\tmp"
set "TMP=D:\tmp"

if not exist "%NODE%" (
  echo Node not found at D:\node.exe
  echo Trying Python launcher instead...
  goto PYTHON
)

if not exist "node_modules\electron" (
  echo Installing dependencies ^(uses D: drive cache^)...
  call "%NPM%" install
  if errorlevel 1 (
    echo npm install failed - disk may be full. Using Python launcher...
    goto PYTHON
  )
)

echo Starting Scholaxia Electron app...
call "%~dp0node_modules\.bin\electron.cmd" .
exit /b 0

:PYTHON
if exist "..\venv\Scripts\python.exe" (
  echo Starting with Python WebView2...
  "..\venv\Scripts\python.exe" run_desktop.py
) else if exist "python" (
  python run_desktop.py
) else (
  echo Install Python or free disk space and run: D:\npm.cmd install
  pause
)
