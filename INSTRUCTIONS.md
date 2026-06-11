# MRA Shop Floor Dashboard — AI Handover Instructions

You are being handed 5 files. Your job is to help deploy the MRA Shop Floor
dashboard to Azure exactly as described below. Everything has already been done
once — this document lets you replicate or maintain it.

---

## What these files are

| File | What it is |
|---|---|
| `MRA_Dashboard.html` | The entire dashboard — static HTML + JS, no framework, no build step |
| `data.js` | Auto-generated data snapshot loaded by the dashboard at runtime |
| `index.html` | One-line redirect so the root URL loads the dashboard |
| `Export-Data.ps1` | PowerShell script: reads the Excel workbook → writes data.js → pushes to Azure |
| `INSTRUCTIONS.md` | This file |

The dashboard is 100% static. No server-side code, no database, no API.
It loads `data.js` on startup, then polls `data.js` every 30 seconds for updates.

---

## Azure deployment (already done once — use these details)

| Setting | Value |
|---|---|
| Subscription | Azure subscription 1 — `29e7d922-5ea8-474a-b4bf-061a72ae7ce4` |
| Tenant | TGCS — `57714027-b784-4494-8412-6e3b00c9bf2c` |
| Resource group | `mra-dashboard-rg` (East US) |
| Storage account | `mrashopdash` |
| Container | `$web` (Azure static website container) |
| Live URL | `https://mrashopdash.z13.web.core.windows.net/` |
| az CLI path | `C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd` |

---

## Task 1 — Re-deploy all files to Azure

Run these commands in PowerShell (one at a time). Log in first if needed:

```powershell
# Login (use device code — most reliable)
az login --tenant "57714027-b784-4494-8412-6e3b00c9bf2c" --use-device-code
```

Then upload each file:

```powershell
$web = '$web'
$acct = 'mrashopdash'
$dir = 'C:\006 RM Deploy\claude bot - Copy\Downloads'

az storage blob upload --account-name $acct --container-name $web --name 'index.html'        --file "$dir\index.html"        --content-type 'text/html'               --overwrite --auth-mode key --only-show-errors
az storage blob upload --account-name $acct --container-name $web --name 'MRA_Dashboard.html' --file "$dir\MRA_Dashboard.html" --content-type 'text/html'               --overwrite --auth-mode key --only-show-errors
az storage blob upload --account-name $acct --container-name $web --name 'data.js'            --file "$dir\data.js"            --content-type 'application/javascript'  --overwrite --auth-mode key --only-show-errors
```

Verify it's live:
```powershell
curl -s -o $null -w "%{http_code}" "https://mrashopdash.z13.web.core.windows.net/"
# Should print: 200
```

---

## Task 2 — Set up static website hosting (only needed on a brand-new storage account)

If the storage account is new and static website hosting has not been enabled yet:

```powershell
az storage blob service-properties update `
  --account-name mrashopdash `
  --static-website `
  --index-document MRA_Dashboard.html `
  --404-document MRA_Dashboard.html
```

---

## Task 3 — Fix Export-Data.ps1 if the Azure push stops working

`Export-Data.ps1` ends with a section that uploads `data.js` to Azure after every
local refresh. The two things that can break it:

**1. az CLI not found**
The script uses the hardcoded path:
`C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd`
If az was installed elsewhere, update that path in the script.

**2. az login expired (MFA)**
Run the device-code login again (see Task 1). The script uses `--auth-mode key`
which auto-fetches the storage account key — it does NOT need an active az login
after the first setup, UNLESS the account key has been rotated.

---

## Task 4 — Add a logo

The dashboard loads `logo.png` from the same folder. It fails silently if missing.
To add one:
1. Drop a `logo.png` into the Downloads folder
2. Upload it:
```powershell
az storage blob upload --account-name mrashopdash --container-name '$web' `
  --name 'logo.png' --file "C:\006 RM Deploy\claude bot - Copy\Downloads\logo.png" `
  --content-type 'image/png' --overwrite --auth-mode key --only-show-errors
```

---

## How data refresh works end-to-end

```
Excel workbook  (C:\006 RM Deploy\MRA_Shop_Board_v6_9_7.xlsx)
      ↓
Export-Data.ps1  runs on a schedule (every 3 min via Windows Task Scheduler)
      ↓
dashboard\data.js  written locally
      ↓
az storage blob upload  (last section of Export-Data.ps1)
      ↓
Azure blob: mrashopdash/$web/data.js  updated
      ↓
Browser polls every 30 seconds → dashboard stays current
```

The scheduled task is set up by `Setup-AutoRefresh.ps1` (requires admin, one-time run).
Alternatively, `Start Dashboard.bat` does the same thing without admin rights as long
as that window stays open.

---

## Known bugs already fixed (do not re-introduce)

1. **Temp path short-name crash** — `$env:TEMP` returned a Windows 8.3 short name
   (`RL73BC~1.ADM`) that Remove-Item could not resolve.
   Fixed: use `[System.IO.Path]::GetTempPath()` instead of `$env:TEMP`.

2. **ErrorActionPreference blocks az CLI** — `$ErrorActionPreference = 'Stop'` at the
   top of the script caused a `NativeCommandError` when az.cmd wrote anything to stderr,
   even on success.
   Fixed: save/restore `$ErrorActionPreference` around the az call, set to `'Continue'`
   for that block only.

---

## Quick reference

| What | Command |
|---|---|
| Check live site | `curl https://mrashopdash.z13.web.core.windows.net/` |
| Re-login to Azure | `az login --tenant 57714027-b784-4494-8412-6e3b00c9bf2c --use-device-code` |
| Run data export manually | `powershell -ExecutionPolicy Bypass -File "...\dashboard\Export-Data.ps1"` |
| List blobs in $web | `az storage blob list --account-name mrashopdash --container-name '$web' --auth-mode key -o table` |
