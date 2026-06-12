@echo off
REM ============================================================
REM  MRA - Import Now (run by hand when team members drop files)
REM  1) imports everything in "Intake Inbox" into the master
REM     (this opens Excel - that's why it's manual, not scheduled)
REM  2) rebuilds data.js and pushes it to Azure right away
REM  Double-click this whenever you've got new intake files.
REM ============================================================
echo Importing intake files into the master workbook...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Import-Intake.ps1"
echo.
echo Rebuilding and pushing the dashboard...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-Auto.ps1"
echo.
echo Done. Check import-log.txt for what was imported.
pause
