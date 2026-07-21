@echo off
title Build Scholaxia Admin Windows Installer
cd /d "%~dp0"

echo.
echo Building Scholaxia ADMIN only (installer + portable)...
echo Output:
echo   dist-admin\Scholaxia-Admin-Setup-*.exe
echo   dist-admin\Scholaxia-Admin-Portable-*.exe
echo Student and teacher portals are NOT included.
echo.

if exist "D:\node.exe" (
  set "PATH=D:\;%PATH%"
  set "npm_config_cache=D:\tmp\npm-cache"
  set "TEMP=D:\tmp"
  set "TMP=D:\tmp"
)

if not exist "D:\tmp" mkdir "D:\tmp"
if not exist "D:\tmp\npm-cache" mkdir "D:\tmp\npm-cache"

if not exist "node_modules\electron-builder" (
  echo Installing build tools...
  call npm install
  if errorlevel 1 (
    echo Build failed. Free disk space and run again.
    exit /b 1
  )
)

call npm run build:admin
if errorlevel 1 (
  echo Admin build failed.
  exit /b 1
)

echo.
echo Creating complete run folder (includes ffmpeg.dll)...
set "READY=D:\tmp\Scholaxia-Admin-Ready"
if exist "%READY%" rmdir /s /q "%READY%"
mkdir "%READY%"
robocopy "dist-admin\win-unpacked" "%READY%" /E /NFL /NDL /NJH /NJS /nc /ns /np >nul
if not exist "%READY%\ffmpeg.dll" (
  echo WARNING: ffmpeg.dll missing from package.
  exit /b 1
)

powershell -NoProfile -Command ^
  "Compress-Archive -Path '%READY%\*' -DestinationPath 'dist-admin\Scholaxia-Admin-Complete.zip' -Force"

echo.
echo Done! Use ONE of these (Admin only):
echo   dist-admin\Scholaxia-Admin-Setup-1.0.1.exe
echo   dist-admin\Scholaxia-Admin-Complete.zip   ^(extract and run ScholaxiaAdmin.exe^)
echo   %READY%\ScholaxiaAdmin.exe
echo.
echo Do NOT copy ScholaxiaAdmin.exe alone — ffmpeg.dll must stay next to it.
echo.
exit /b 0
