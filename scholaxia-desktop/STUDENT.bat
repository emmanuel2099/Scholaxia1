@echo off
title Scholaxia Student
cd /d "%~dp0"

REM Use live source (run_desktop.py) so you always see latest HTML/CSS/JS changes.
REM Set SCHOLAXIA_USE_EXE=1 to force the old packaged .exe instead.
if "%SCHOLAXIA_USE_EXE%"=="1" if exist "dist\win-unpacked\ScholaxiaStudent.exe" (
  start "" "%~dp0dist\win-unpacked\ScholaxiaStudent.exe"
  exit /b 0
)

if exist "..\venv\Scripts\python.exe" (
  "..\venv\Scripts\python.exe" run_desktop.py
  exit /b 0
)

python run_desktop.py
exit /b %ERRORLEVEL%
