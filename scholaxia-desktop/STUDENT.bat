@echo off
title Scholaxia Student
cd /d "%~dp0"

if exist "dist\win-unpacked\ScholaxiaStudent.exe" (
  start "" "%~dp0dist\win-unpacked\ScholaxiaStudent.exe"
  exit /b 0
)

if exist "node_modules\.bin\electron.cmd" (
  call "%~dp0node_modules\.bin\electron.cmd" .
  exit /b 0
)

if exist "..\venv\Scripts\python.exe" (
  "..\venv\Scripts\python.exe" run_desktop.py
  exit /b 0
)

python run_desktop.py
