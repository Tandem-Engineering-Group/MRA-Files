@echo off
REM Double-click to APPLY the schedule merge (writes to the workbook).
REM Close MRA_Shop_Board_v6_9_7.xlsx in Excel first. A backup is made automatically.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Merge-Schedule.ps1" -Apply
echo.
echo ---- Finished. A copy of this output is on your Desktop (merge-APPLIED.txt). ----
pause
