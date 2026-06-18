@echo off
title Push Employee-of-the-Month photo
cd /d "%~dp0"

echo(
echo  Pushing eotm.png to the MRA dashboard...
echo(

if not exist ".\eotm.png" (
  echo  ERROR: eotm.png is not in this folder.
  echo  Put the new winner's photo here, named exactly  eotm.png  , then run this again.
  echo(
  pause
  exit /b 1
)
if not exist ".\azcopy.exe"        ( echo  ERROR: azcopy.exe not found in this folder. & pause & exit /b 1 )
if not exist ".\azure-target.txt"  ( echo  ERROR: azure-target.txt not found in this folder. & pause & exit /b 1 )

powershell -NoProfile -ExecutionPolicy Bypass -Command "$u = (Get-Content '.\azure-target.txt' -Raw).Trim() -replace 'data\.js\?','eotm.png?'; & '.\azcopy.exe' copy '.\eotm.png' $u --overwrite=true"

echo(
echo  If you see  'Final Job Status: Completed'  above, the photo is LIVE.
echo  Refresh the wall view (press the refresh / F5) to see it.
echo(
pause
