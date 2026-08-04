@echo off
cd /d "%~dp0"
echo Starting Scholaxia Vendor App...
flutter run -t lib/vendor_main.dart -d windows
