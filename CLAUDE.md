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

## Pending / requested (not yet built — remind Rich)

- **Replace-by-project import** (deferred 2026-06-11, Rich said "hold for now but
  keep reminding me"). Today `Import-Intake.ps1` is **append-only** — re-uploading
  an edited intake template ADDS duplicate rows. Requested behavior: when a file
  comes in for *Project X*, clear X's existing `Project Tasks` rows first, then
  write the file's rows (so edit-offline → re-upload → schedule updates). Rule to
  convey: the template must contain that project's **complete** task list each time
  (it replaces, doesn't merge). Implementation sketch: from the master XML, collect
  the row numbers for each incoming project name; in COM, append the new rows, then
  `EntireRow.Delete` the old rows (descending). Remember this Excel's COM only
  accepts **strings** on `.Value` (dates → OADate serial string + `m/d/yyyy` format).
- **Publish the Projects-tab download button**: the "⬇ Download Intake Template"
  link + `MRA_Project_Intake_Template.xlsx` go live only after a deploy with
  `mode = live`.
- **Beefed-up template**: Rich is enhancing the intake template; when he sends it,
  make it the hosted standard (update `build_template.py`), keep sheet `Enter Here`
  + columns A–L, and auto-fill the Project name down every row.
- **Task-level Gantt bars** (level 3): draw each Project Task as its own bar when a
  project is expanded — do after the project data is cleaned up.
- **M365 tasking integration — Planner-per-person + email the assignee** (PARKED
  2026-06-16; Rich chose these two from Teams/Planner/Email/two-way). When a task is
  added/assigned on the dashboard, extend the **existing** Power Automate flow (add
  steps AFTER the Run script): Parse JSON the trigger body → Condition `action ==
  addTask` → look up the assignee's email → **send an Outlook email** + **create an
  assigned Planner task** (lands in their Teams ▸ Tasks app + phone, with due date).
  Prereq: a **roster** mapping each *assignee* → email. NOTE assignees (Sal, Doug =
  individuals; MasterWraps, Electricians, Vendor = outside groups → email only, no
  Planner) are a DIFFERENT list from the **login Users** (Rich, Luc). Also need a
  Planner plan (e.g. "MRA Shop Tasks" in the *MRA Site Project* team) or create one.
  Teams/Outlook/Planner connectors are reliable (unlike the Office Script step).
- **Activity Log "Who" not stamping** (STILL OPEN — worked on 2026-06-16 evening, not solved).
  The `ActivityLog` `Who` column (col B) logs **blank** on every action. What we tried this
  session, all of which did NOT fix it:
  - Rebuilt the Power Automate flow from scratch → **`MRA Sync V2`** (fresh HTTP trigger,
    workflow id `c7056430c8f645719ac5d29038822b04`; updated the dashboard `CLOSE_FLOW_URL`
    to it and redeployed via `mode=live`).
  - Created a **brand-new Office Script `MRA Sync 2`** (new name to dodge the compiled cache)
    containing the full merged code (see `MRA-Sync.ts`), and pointed the flow's Run script at it.
  - Confirmed via the flow run history: runs **Succeed (200)**, payload arrives correct
    (e.g. `{"action":"editJob","pin":"1974","user":"Rich Miller",...}` — so Rich's code 1974
    maps to "Rich Miller"), and **edits DO save + rows DO get logged** — but `Who` is still blank.
  - This is logically impossible for the merged code (its `who` is name | "Shop" | null, and
    null returns before logging) → means the **executed code ≠ the saved `MRA Sync 2` code**.
  Leading theories / next steps to try:
  1. **`MRA Sync 2` may not have actually SAVED its code** (Office Scripts shows pasted code in
     the editor but the cloud save can silently not persist). Re-open it, force **Save script**,
     watch for the saved confirmation, retest. Cheapest likely fix.
  2. If still blank → the genuine **Office Scripts compiled-cache** gremlin. Workaround:
     **stamp the name from the FLOW**, not the script — after Run script, add an Excel
     "Add a row"/"Update a row" writing `payload.user` into `Who` (downside: would double-log
     unless the script's own logging is also silenced). Flow connectors aren't subject to the
     Office Script cache.
  NOTE: write-back itself WORKS (edits save); only the `Who` column is cosmetically blank, so
  the log is a usable audit trail (action / time / project) minus the name. Parked at Rich's request.

## In progress / queued (2026-06-17)

- **Siemens DI Pedestal import** (from Rich's PDF "SIEMENS DI Preliminary Hard Date Schedule
  v1.06.10.2026"). Parsed to **15 tasks** across 5 phases (Project Planning / Creative Design /
  Production / Post Production / Launch). Decisions confirmed: fix spelling **Seimans → Siemens
  DI Pedestal** and **replace** its 2 existing rows (currently rows 318–319, Task IDs 317–318);
  PM=Megan Fraser; party → Assigned To (MRA / Siemens DI / Heitek / Combined); dates 2026 → Finish
  (two ranges get Start+Finish); Completed→`Completed`, Upcoming/Future→`Not Started`; milestones
  ◆ = "Pedestal Completion" (Jul 31) + "Upcoming Event · Boston, MA" (Aug 5). NOT yet written.
- **Medtronic import** (from "Medtronic_Production_Schedule_v4.06.05.2026.xlsx", sheet `2026`).
  GREEN-LIT by Rich: **wipe all ~101 old Medtronic rows, replace** with this schedule. Structure:
  **bold col-A items = Phases** (Contract Items, Scope of Work & Schedule, Budget, Conceptual
  Exhibit & Display Design, Interior Graphic Design, Exterior Graphic Design, … more below row 80),
  tasks in col B, **Start=col I, Finish=col J**, PM=Megan Fraser. **Assigned To = best-effort from
  the color legend** (Rich will correct via dropdowns): Copper=MRA · Blue=Medtronic · Green=Learning
  Undefeated · Red=IXL/TSS · Yellow=Brinkbit · Purple=Combined Effort · Grey=Other. CAUTION: the bar
  colors are theme-based and don't extract cleanly via openpyxl — needs raw-XML/theme resolution or
  a best guess. NOT yet written. Plan: build both imports into the workbook in one pass and send the
  file to Rich to review before he saves (the safe pattern; avoid mass raw-XML row deletion risk).
- **Assigned-To dropdowns** (Rich doing offline): he's standardizing the Assigned-To values via Excel
  data-validation dropdowns and will rename assignees. Job: treat one canonical assignee list as truth
  and **flag mismatches** (typos, a color/name with no home). Canonical names seen so far: MRA, MRA Shop,
  Medtronic, Learning Undefeated, IXL/TSS, Brinkbit, Combined Effort, Siemens DI, Heitek, Sal,
  MasterWraps, Electricians, Doug, Vendor + people (Megan Fraser, Al Karloff, Gino Bitonti…). Ask Rich
  where the master dropdown list lives (a tab, or the validation on the Assigned-To column).
- **MRA Shop load highlight = DONE** (rev 3.6, see below). Future: a dropdown to highlight *other*
  resources too (Rich asked to start with MRA Shop only).

## Shipped 2026-06-16 (evening) — Projects editor

- **In-dashboard Project Tasks editor is LIVE** (rev 3.5): PROJECTS tab → **✎ Edit Project Tasks**
  (or click a project in *Project Progress*) → popup with that project's tasks **grouped by phase**,
  collapsible (▸/▾, Collapse/Expand all), milestone rows shaded gold. Add / edit / ✓ complete /
  ↩ reopen / 🗑 delete + Predecessor links; code-gated by the same `ensureAuth` as the shop board.
- **Workbook `Project Tasks` sheet** now has **Task ID (col M)** + **Predecessor (col N)**, colored
  project divider lines, milestone gold shading, and Excel phase **grouping (+/− outline)**.
- **`Export-Data.ps1`** emits each project's full `tasks[]` (id, task, phase, type, who, start/finish,
  status, milestone, comments, predecessor). FIXED a crash where `$pId` collided with PowerShell's
  read-only `$PID` — renamed to `$pTaskId`. (Rich's local pipeline: `Update-Auto.ps1` → `Export-Data.ps1`
  → AzCopy push, run by right-click; workbook lives one level UP from the `dashboard` folder.)
- **`MRA-Sync.ts`** = the merged Office Script (shop-floor actions + 5 project-task actions:
  add/edit/delete/close/reopen ProjectTask). Matches rows by Project + Task ID, falls back to task text.

