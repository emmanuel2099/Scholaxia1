@echo off
title Scholaxia Stream Chat Setup
cd /d "%~dp0"

if not exist "stream.env" (
  copy /Y "stream.env.example" "stream.env" >nul
  echo Created stream.env from template.
) else (
  echo stream.env already exists.
)

echo.
echo 1. Sign in at https://dashboard.getstream.io (free tier)
echo 2. Create or open your Chat app
echo 3. Copy the KEY and SECRET from App Access Keys
echo 4. Paste both in stream.env:
echo      STREAM_API_KEY=...
echo      STREAM_CHAT_SECRET=...
echo.
echo Opening stream.env in Notepad now...
start notepad "stream.env"
echo.
echo After saving, close Scholaxia and run: python run_desktop.py
pause
