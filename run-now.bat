@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvars64.bat"
set PATH=D:\tmp;C:\Users\EMMA\flutter\bin;%PATH%
set TEMP=D:\tmp\flutter-temp
set TMP=D:\tmp\flutter-temp
set PUB_CACHE=D:\pub-cache
if not exist "%TEMP%" mkdir "%TEMP%"
cd /d "c:\Users\EMMA\New folder (2)\scholaxia"
flutter run -d windows
