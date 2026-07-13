@echo off
title Scholaxia — run on Windows (D: drive build)
call "C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvars64.bat"
if errorlevel 1 (
  echo Visual Studio C++ tools not found.
  pause
  exit /b 1
)

set "PATH=D:\tmp;C:\Users\EMMA\flutter\bin;%PATH%"
set "TEMP=D:\tmp\flutter-temp"
set "TMP=D:\tmp\flutter-temp"
set "PUB_CACHE=D:\pub-cache"
set "D_BUILD=D:\tmp\scholaxia-build"
set "D_WIN=D:\tmp\scholaxia-win-build"

if not exist "D:\tmp" mkdir "D:\tmp"
if not exist "%TEMP%" mkdir "%TEMP%"
if not exist "%D_BUILD%" mkdir "%D_BUILD%"
if not exist "%D_WIN%" mkdir "%D_WIN%"

cd /d "c:\Users\EMMA\New folder (2)\scholaxia"

REM Put Flutter build output on D: — C: is too low on space
if exist "build\" (
  rmdir "build" 2>nul
  if exist "build\" rd /s /q "build" 2>nul
)
if not exist "build" mklink /J "build" "%D_BUILD%" >nul

echo Building on D: (%D_BUILD%)
echo TEMP=%TEMP%
echo.

flutter pub get
if errorlevel 1 goto :fail

flutter run -d windows
if errorlevel 1 goto :fail
exit /b 0

:fail
echo.
echo Build failed. If you saw dl.google.com write errors, free space on C: or retry.
echo You can also install the APK from C:\Scholaxia-APK\ instead of Windows build.
pause
exit /b 1
