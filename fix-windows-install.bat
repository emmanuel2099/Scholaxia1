@echo off
REM Fixes CMake install prefix pointing at C:\Program Files\scholaxia (needs admin).
setlocal
set BUILD=D:\tmp\scholaxia-win-build\build\windows\x64
set DEST=D:/tmp/scholaxia-win-build/build/windows/x64/runner/Debug
set CMAKE=C:\Program Files\Microsoft Visual Studio\18\Insiders\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe

if not exist "%BUILD%\cmake_install.cmake" (
  echo No Windows build found. Run run-windows.bat first.
  pause
  exit /b 1
)

powershell -NoProfile -Command "(Get-Content '%BUILD%\CMakeCache.txt' -Raw) -replace 'CMAKE_INSTALL_PREFIX:PATH=.*','CMAKE_INSTALL_PREFIX:PATH=%DEST%' | Set-Content '%BUILD%\CMakeCache.txt' -NoNewline"
powershell -NoProfile -Command "(Get-Content '%BUILD%\cmake_install.cmake' -Raw) -replace 'C:/Program Files/scholaxia','%DEST%' | Set-Content '%BUILD%\cmake_install.cmake' -NoNewline"

"%CMAKE%" -DBUILD_TYPE=Debug -P "%BUILD%\cmake_install.cmake"
if errorlevel 1 (
  echo Install step failed.
  pause
  exit /b 1
)

echo Done. DLLs and assets copied to runner\Debug. Run scholaxia.exe or run-windows.bat.
pause
