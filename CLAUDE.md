# CLAUDE.md — MRA Shop Floor Dashboard

Guidance for Claude when working in this repository.

## Source-of-truth files (reference these ongoing)

The working files for this project live in **SharePoint**, not in this repo.
When running as Claude Code on the web (an ephemeral cloud container), the
user's local/OneDrive‑synced path is **not** accessible:

- Local (user's machine, NOT reachable from web sessions):
  `C:\Users\rmiller\TGCS\MRA Site Project - Documents\MRA Claude Code\01 claude bot`
  (the user sometimes refers to this as `01.1 RL Claude Bot`)

Instead, reach the same files through the **Microsoft 365 MCP** connection:

- SharePoint folder: **MRA Claude Code / 01 claude bot**
  `https://snptechnical.sharepoint.com/sites/MRASiteProject/Shared Documents/MRA Claude Code/01 claude bot`
- `read_resource` URI for the folder:
  `file:///b!vl1e4q2FdkShRDOfvSZR1M0xeaP9rW9KoRIXfk51DQyZ1vl6LeUVQ61wNNrTNu0w/01IUZ65BXUKHIFYARM6RFL45G4DKQOE5BA`

Folder contents:

| Item | What it is |
|---|---|
| `MRA_Shop_Board_v6_9_7.xlsx` | The live workbook `Export-Data.ps1` reads to generate `data.js` |
| `MRA_Shop_Board_v6_9_7_BACKUP.xlsx` | Backup copy of the workbook |
| `dashboard/` | Working copy of the dashboard files (`MRA_Dashboard.html`, `data.js`, etc.) |
| `.claude/` | Claude config for the local working folder |

### How to access via the Microsoft 365 MCP

1. If item IDs have changed, re-locate the folder:
   `sharepoint_folder_search` with `name: "MRA Site Project"` (or `"01 claude bot"`)
   and pick the result whose `webUrl` ends in `/MRA Claude Code/01 claude bot`.
2. List/read folder contents with `read_resource` using the folder URI above.
3. Read individual files with `read_resource` using their `file:///{driveId}/{itemId}` URIs.

> Note: SharePoint item IDs can change if files are moved/recreated. The `webUrl`
> and the `sharepoint_folder_search` lookup are the durable way to find them.

## This repository

This repo (`tandem-engineering-group/mra-files`) holds the deployable dashboard:

| File | What it is |
|---|---|
| `MRA_Dashboard.html` | The entire dashboard — static HTML + JS, no build step |
| `data.js` | Auto-generated data snapshot loaded at runtime (polled every 30s) |
| `index.html` | One-line redirect to the dashboard |
| `Export-Data.ps1` | Reads the Excel workbook → writes `data.js` → pushes to Azure |
| `INSTRUCTIONS.md` | Full deploy/maintenance runbook (Azure details, known bugs) |

Live site: `https://mrashopdash.z13.web.core.windows.net/`
See `INSTRUCTIONS.md` for the complete Azure deployment runbook.
