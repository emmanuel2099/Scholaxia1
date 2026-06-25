@echo off
title Build Scholaxia Android APK (D: drive)
cd /d "%~dp0"

echo.
echo Building Scholaxia APK using D: drive...
echo.

set "FLUTTER_ROOT=D:\flutter_windows_3.38.4-stable\flutter"
set "PATH=%FLUTTER_ROOT%\bin;%PATH%"
set "PUB_CACHE=D:\tmp\pub-cache"
set "GRADLE_USER_HOME=D:\tmp\gradle-home"
set "ANDROID_HOME=D:\flutter-build\android-sdk"
set "ANDROID_SDK_ROOT=D:\flutter-build\android-sdk"
set "TEMP=D:\tmp"
set "TMP=D:\tmp"
set "D_BUILD=D:\tmp\scholaxia-build"
set "D_GRADLE=D:\tmp\scholaxia-android\.gradle"

if not exist "%FLUTTER_ROOT%\bin\flutter.bat" (
  echo Flutter not found at %FLUTTER_ROOT%
  pause
  exit /b 1
)

if not exist "D:\tmp" mkdir "D:\tmp"
if not exist "%D_BUILD%" mkdir "%D_BUILD%"
if not exist "%D_GRADLE%" mkdir "%D_GRADLE%"
if not exist "D:\tmp\pub-cache" mkdir "D:\tmp\pub-cache"
if not exist "D:\tmp\gradle-home" mkdir "D:\tmp\gradle-home"

REM Put Flutter build output on D: (junction)
if exist "build" (
  if exist "build\" (
    rmdir "build" 2>nul
    if exist "build" rd /s /q "build" 2>nul
  )
)
if not exist "build" mklink /J "build" "%D_BUILD%" >nul

echo Flutter : %FLUTTER_ROOT%
echo Gradle  : %GRADLE_USER_HOME%
echo SDK     : %ANDROID_HOME%
echo Build   : %D_BUILD%
echo.

call flutter pub get
if errorlevel 1 goto :fail

call flutter build apk --release --target-platform android-arm64 --android-project-cache-dir="%D_GRADLE%"
if errorlevel 1 goto :fail

echo.
echo Done! APK:
echo   %D_BUILD%\app\outputs\flutter-apk\app-release.apk
echo.
pause
exit /b 0

:fail
echo APK build failed.
pause
exit /b 1
