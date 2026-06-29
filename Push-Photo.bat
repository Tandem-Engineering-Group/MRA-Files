@echo off
title Update Employee of the Month (photo + name)
cd /d "%~dp0"

if not exist ".\azcopy.exe"       ( echo  ERROR: azcopy.exe not found in this folder.       & pause & exit /b 1 )
if not exist ".\azure-target.txt" ( echo  ERROR: azure-target.txt not found in this folder. & pause & exit /b 1 )

echo(
echo  Updating Employee of the Month on the dashboard...
echo  (pushes eotm.png = photo, and eotm.txt = name / on-off, whichever are present)
echo(

powershell -NoProfile -ExecutionPolicy Bypass -Command "$base=(Get-Content '.\azure-target.txt' -Raw).Trim(); foreach($f in 'eotm.png','eotm.txt'){ if(Test-Path ('.\'+$f)){ Write-Host (' -> ' + $f); $u=$base -replace 'data\.js\?',($f+'?'); & '.\azcopy.exe' copy ('.\'+$f) $u --overwrite=true } }"

echo(
echo  Done. If you saw 'Final Job Status: Completed' above, it's LIVE.
echo  Refresh the wall view to see the change.
echo(
pause
