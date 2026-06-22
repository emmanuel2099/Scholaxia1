@echo off
title Scholaxia Admin Console
cd /d "%~dp0"

if exist "Scholaxia Student.exe" (
  start "" "%~dp0Scholaxia Student.exe" --admin
  exit /b 0
)

if exist "node_modules\.bin\electron.cmd" (
  call "%~dp0node_modules\.bin\electron.cmd" . --admin
  exit /b 0
)

python run_desktop.py --admin
