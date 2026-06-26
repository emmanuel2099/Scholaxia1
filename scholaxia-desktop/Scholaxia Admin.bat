@echo off
title Scholaxia Student (desktop is student-only)
cd /d "%~dp0"
echo.
echo Scholaxia DESKTOP is for STUDENTS only.
echo Admins use the Scholaxia web console in your browser.
echo.
if exist "Scholaxia Student.exe" (
  start "" "%~dp0Scholaxia Student.exe"
  exit /b 0
)
if exist "node_modules\.bin\electron.cmd" (
  call "%~dp0node_modules\.bin\electron.cmd" .
  exit /b 0
)
python run_desktop.py
