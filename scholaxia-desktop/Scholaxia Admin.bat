@echo off
title Scholaxia Admin Console
cd /d "%~dp0"
if exist "..\venv\Scripts\python.exe" (
  "..\venv\Scripts\python.exe" run_desktop.py --admin
) else (
  python run_desktop.py --admin
)
