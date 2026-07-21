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
REM Prefer D: copy (no spaces; C: often full). Sync lean Flutter sources if present.
set "SRC=c:\Users\EMMA\New folder (2)\scholaxia"
set "DST=D:\tmp\scholaxia-win-build"
if not exist "%DST%\pubspec.yaml" (
  mkdir "%DST%" 2>nul
  robocopy "%SRC%" "%DST%" /E /NFL /NDL /NJH /NJS /nc /ns /np /XD build .dart_tool .git scholaxia-desktop node_modules android ios macos linux web .idea venv dist admin-dashboard discord-community sia-web app scripts >nul
)
cd /d "%DST%"
if exist "build\" rmdir "build" 2>nul
if not exist "build" mklink /J "build" "D:\tmp\scholaxia-build" >nul
where nuget >nul 2>&1
if errorlevel 1 (
  echo nuget.exe not found. Expected at D:\tmp\nuget.exe
  exit /b 1
)
call flutter pub get
if errorlevel 1 exit /b 1
call flutter run -d windows
exit /b %ERRORLEVEL%
