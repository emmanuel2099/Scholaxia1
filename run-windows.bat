@echo off
REM Scholaxia Windows launcher — uses D: drive for temp/cache (C: may be low on space).
call "C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvars64.bat"
if errorlevel 1 (
  echo Could not load Visual Studio. Install "Desktop development with C++" in Visual Studio Installer.
  pause
  exit /b 1
)

set PATH=D:\tmp;C:\Users\EMMA\flutter\bin;%PATH%
set TEMP=D:\tmp\flutter-temp
set TMP=D:\tmp\flutter-temp
set PUB_CACHE=D:\pub-cache
if not exist "%TEMP%" mkdir "%TEMP%"

cd /d "%~dp0"
if exist "D:\tmp\scholaxia-win-build\pubspec.yaml" (
  cd /d "D:\tmp\scholaxia-win-build"
)

set EXE=build\windows\x64\runner\Debug\scholaxia.exe
if exist "%EXE%" if exist "build\windows\x64\runner\Debug\flutter_windows.dll" (
  echo Starting Scholaxia...
  start "" "%EXE%"
  exit /b 0
)

echo Building Scholaxia for Windows (first run takes ~10 min)...
flutter pub get
flutter run -d windows
if errorlevel 1 (
  echo.
  echo If build failed at INSTALL with "Program Files/scholaxia", run fix-windows-install.bat then try again.
)
pause
