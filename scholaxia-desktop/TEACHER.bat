@echo off
title Scholaxia Student (desktop is student-only)
cd /d "%~dp0"
echo.
echo Scholaxia DESKTOP is for STUDENTS only.
echo Teachers use the Scholaxia web portal in your browser.
echo.
echo Starting STUDENT app...
echo.
if exist "..\venv\Scripts\python.exe" (
  "..\venv\Scripts\python.exe" run_desktop.py
) else (
  python run_desktop.py
)
pause
