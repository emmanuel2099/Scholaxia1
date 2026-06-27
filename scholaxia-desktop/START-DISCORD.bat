@echo off
title Scholaxia Discord Community
cd /d "%~dp0..\..\discord-clone-nextjs"
if not exist "package.json" (
  echo Discord clone not found. Expected folder:
  echo   %~dp0..\..\discord-clone-nextjs
  pause
  exit /b 1
)
if not exist "node_modules" (
  echo Installing Discord dependencies...
  call npm install --legacy-peer-deps
)
if not exist "..\scholaxia-desktop\stream.env" (
  if not exist ".env.local" (
    echo.
    echo Add STREAM_CHAT_SECRET to scholaxia-desktop\stream.env
    echo   (copy stream.env.example — get secret from getstream.io dashboard)
    echo.
  )
)
echo Starting Discord Community on http://127.0.0.1:3001
echo Edit UI in this folder — Scholaxia student app embeds it in Community tab.
echo.
call npm run dev -- -p 3001
