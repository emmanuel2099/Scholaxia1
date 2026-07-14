@echo off
title Scholaxia Windows run
call "C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvars64.bat"
if errorlevel 1 (
  echo Visual Studio C++ tools not found.
  exit /b 1
)
set "PATH=D:\tmp;C:\Users\EMMA\flutter\bin;%PATH%"
set "TEMP=D:\tmp\flutter-temp"
set "TMP=D:\tmp\flutter-temp"
set "PUB_CACHE=D:\pub-cache"
if not exist "D:\tmp\flutter-temp" mkdir "D:\tmp\flutter-temp"
if not exist "D:\tmp\scholaxia-build" mkdir "D:\tmp\scholaxia-build"
cd /d "c:\Users\EMMA\New folder (2)\scholaxia"
if exist "build\" (
  rmdir "build" 2>nul
  if exist "build\" rd /s /q "build" 2>nul
)
if not exist "build" mklink /J "build" "D:\tmp\scholaxia-build" >nul
call flutter clean
call flutter pub get
if errorlevel 1 exit /b 1
call flutter run -d windows
exit /b %ERRORLEVEL%
