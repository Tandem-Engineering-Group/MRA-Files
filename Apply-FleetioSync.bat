@echo off
REM ============================================================
REM  Apply-FleetioSync.bat  --  one-click "apply" for the
REM  Fleetio -> Shop Tasks sync. Keep this in the SAME folder as
REM  Sync-FleetioTasks.ps1. Double-click to write the new Fleetio
REM  tasks into the workbook (Excel must be CLOSED).
REM ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync-FleetioTasks.ps1" -Apply
echo.
echo Done. Review the messages above (and fleetio-sync-log.txt).
pause
