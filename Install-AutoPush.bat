@echo off
REM One-time setup: schedule the dashboard auto-push every 15 minutes.
REM Runs only while you are logged in. No admin rights needed.
set "PS=powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%~dp0Update-Auto.ps1\""
schtasks /Create /SC MINUTE /MO 15 /TN "MRA Dashboard Auto-Push" /TR "%PS%" /F
set RC=%ERRORLEVEL%
echo.
if "%RC%"=="0" (
  echo SUCCESS - the dashboard will auto-update every 15 minutes while this PC is on and you are logged in.
  echo You can still double-click dashboard.bat any time for an instant update.
) else (
  echo NOTE: task creation returned code %RC%. Copy the message above and send it to Claude.
)
echo.
pause
