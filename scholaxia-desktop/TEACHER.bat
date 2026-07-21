@echo off
title Scholaxia Teacher Portal
cd /d "D:\tmp\scholaxia-teacher-desktop"
set SCHOLAXIA_ASSET_FALLBACK=D:\tmp
if exist "..\..\venv\Scripts\python.exe" (
  "..\..\venv\Scripts\python.exe" run_desktop.py --teacher
) else if exist "..\venv\Scripts\python.exe" (
  "..\venv\Scripts\python.exe" run_desktop.py --teacher
) else (
  python run_desktop.py --teacher
)
