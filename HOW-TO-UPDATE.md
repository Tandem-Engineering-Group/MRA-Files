# 📋 MRA Dashboard — How to Update It

Live site: https://mrashopdash.z13.web.core.windows.net/

## Routine (every time the schedule changes)
1. Open **MRA_Shop_Board_v6_9_7.xlsx**, make changes, **Save** (Ctrl+S).
2. In the **dashboard** folder, **double-click `dashboard.bat`**.
3. Wait ~30 sec, refresh the live site. Done.

No GitHub, no uploading. You only ever touch the Excel file — never edit the
dashboard or `data.js` by hand. Always **save Excel before** running it.

Success looks like AzCopy printing **"Final Job Status: Completed."**

## Automatic updates (every 15 minutes)
A Windows scheduled task ("MRA Dashboard Auto-Push") runs the push every 15
minutes **while the PC is on and you're logged in** (it won't run overnight —
fine for day-only ops). You can still double-click `dashboard.bat` any time for
an instant update between runs.

Files that make it work (all in the `dashboard` folder):
- `Export-Data.ps1` — reads the workbook, writes `data.js`
- `azcopy.exe` — uploads `data.js` to Azure (no admin needed)
- `azure-target.txt` — the upload token (keep private; ~2-year expiry)
- `dashboard.bat` — manual one-click update
- `Update-Auto.ps1` — silent runner used by the scheduled task
- `Install-AutoPush.bat` — run once to create/refresh the 15-minute schedule
- `auto-log.txt` — log of the latest auto-run (for troubleshooting)

## If pushes stop working
- **Token expired** (after ~2 years): the upload starts failing — ask Claude to
  regenerate `azure-target.txt`.
- **Files went online-only** (OneDrive cloud icon): right-click the `dashboard`
  folder → **Always keep on this device**.

## Deploying dashboard *code* changes (rare)
`data.js` is the live data. The dashboard page itself (`MRA_Dashboard.html`) is
deployed separately via GitHub → Actions → "Deploy to Azure Static Website" →
Run workflow → mode = `live`. See INSTRUCTIONS.md for the full Azure runbook.
