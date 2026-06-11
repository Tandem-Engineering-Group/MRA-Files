# CLAUDE.md — MRA Shop Floor Dashboard

Guidance for Claude when working in this repository.

## Source-of-truth files (reference these ongoing)

The working files for this project live in **SharePoint**, not in this repo.
When running as Claude Code on the web (an ephemeral cloud container), the
user's local/OneDrive‑synced path is **not** accessible:

- Local (user's machine, NOT reachable from web sessions):
  `C:\Users\rmiller\TGCS\MRA Site Project - Documents\MRA Claude Code\01.1 RL Claude Bot`

Instead, reach the same files through the **Microsoft 365 MCP** connection:

- SharePoint folder: **MRA Claude Code / 01.1 RL Claude Bot** (authoritative)
  `https://snptechnical.sharepoint.com/sites/MRASiteProject/Shared Documents/MRA Claude Code/01.1 RL Claude Bot`
- A near-duplicate sibling **`01 claude bot`** exists with the same files — the
  `01.1 RL Claude Bot` copy above is the one to use.

Folder contents:

| Item | What it is |
|---|---|
| `MRA_Shop_Board_v6_9_7.xlsx` | The live workbook `Export-Data.ps1` reads to generate `data.js` |
| `MRA_Shop_Board_v6_9_7_BACKUP.xlsx` | Backup copy of the workbook |
| `dashboard/` | Working copy of the dashboard files (`MRA_Dashboard.html`, `data.js`, etc.) |
| `.claude/` | Claude config for the local working folder |

Known `file:///{driveId}/{itemId}` URIs (driveId
`b!vl1e4q2FdkShRDOfvSZR1M0xeaP9rW9KoRIXfk51DQyZ1vl6LeUVQ61wNNrTNu0w`):

| File | itemId |
|---|---|
| `MRA_Shop_Board_v6_9_7.xlsx` | `01IUZ65BULECQM4AT7VNGIF3BPQ2F3PDCE` |
| `MRA_Shop_Board_v6_9_7_BACKUP.xlsx` | `01IUZ65BV6S2VXJERTUNAICO745NKX5XCZ` |
| `dashboard/MRA_Dashboard.html` | `01IUZ65BWGU4EPP4XKR5DKNTZUO2OZHYN7` |
| `dashboard/data.js` | `01IUZ65BWO2DH7YTDNKBEZER7F5F5UOBWB` |

### How to access via the Microsoft 365 MCP

1. To re-locate the folder/files (item IDs change if files are moved/recreated),
   use **`sharepoint_search`** (document search), e.g. `query: "MRA Dashboard"`,
   and pick results whose `webUrl` contains `/MRA Claude Code/01.1 RL Claude Bot/`.
   Note: `sharepoint_folder_search` is unreliable here — it often misses this
   folder. Prefer document search.
2. Read individual files with `read_resource` using their `file:///{driveId}/{itemId}` URIs.

> **MIME limitation:** the connector only returns allowed types. `.xlsx`, `.html`,
> `.json`, `.csv`, `.md`, images, and PDFs read fine, but **`.js` files (like
> `data.js`) are rejected** (`application/x-javascript` not allowed). To inspect
> the current data, read the source workbook (`.xlsx`) or use the `generatedAt`
> field surfaced in `sharepoint_search` results.

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
