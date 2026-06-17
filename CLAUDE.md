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

### ⚠️ Dashboard release checklist (do EVERY time `MRA_Dashboard.html` changes — Rich shouldn't have to remind us)

1. **Build the feature.**
2. **Update the `? help`** — add/adjust the matching section in `GENERAL_HELP` (and `FLEETIO_HELP` for fleet stuff) so the in-app guide always matches what shipped.
3. **Bump the rev / CHANGELOG** — add a new entry at the TOP of the `CHANGELOG` array (rev + date + plain-English items). The footer badge + "What's new" modal read from it.
4. **Deploy** — commit, push, then trigger the `deploy.yml` workflow with `mode=live` (HTML only; leaves `data.js` alone) and verify the new code is live.

Treat help + rev as PART OF the feature, not an afterthought.

## Pending / requested (not yet built — remind Rich)

- **Projects-tab "next tier" — PARKED 2026-06-17 (Rich: "hold for now but log on to-do").**
  After the rev 3.19 at-risk/status work, these were the agreed next candidates:
  1. **Resource highlighter dropdown** — extend the `🟧 MRA Shop load` toggle into a dropdown
     to highlight *any* assignee's date spans across all projects (today it's MRA Shop only).
     Reuse `mraShopSegs(p)` generalized to a chosen `who`.
  2. **PM / project filter (or search)** on the Projects tab — a PM dropdown or search box that
     filters the Gantt + the PM Load / Milestones / Progress / Team lists to one PM or project.
  3. **Assignee-mismatch flagger** — treat a canonical assignee list as truth and flag typos /
     unknown names (ties into the "Assigned-To dropdowns" cleanup below). Surface as a small
     "⚠ unrecognized assignees: …" note on the Team Capacity panel.
  - Also from the same brainstorm, lower priority: per-project read-only detail card,
    data-gap nudges (no dates / TBD PM / single-task stubs), and task-level Gantt bars +
    predecessor/critical-path links (the latter overlaps the parked "Task-level Gantt bars").
- **DATA FIX Rich owns:** `Siemens DI Pedestal` shows 27% complete but its **start date is in the
  future**, so the dashboard reads it as "upcoming". Correct the start in the workbook.

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

## Shipped 2026-06-17 (morning)

- **MRA Shop load highlight = white outline, picker removed** (rev 3.12). Rich tried the color
  picker, chose **white outline**, said remove the picker ("just adds more"). `MRA_HL_STYLE` is now
  a const `'white'`; the `.hlcolor` select + `setMraHlStyle` + unused `.hl-*` CSS are gone.
- **Added tasks persist on the device through a reload** (rev 3.13). New localStorage pending-adds
  cache (`PENDING_KEY='mra_pending_adds_v1'`, 12h TTL): `pendAdd` on each add path (submitProjTask add,
  submitAddTask, addFleetioTask), `mergePending(incoming)` re-applies in `refresh()`. Self-prunes once
  the row appears in data.js (matched by normalized task text) or after TTL. Fixes Rich's iPad complaint
  (Safari reloads backgrounded tabs → optimistic add was lost). **Adds only** — closes/edits/deletes
  still reconcile on the next refresh (could extend later).
- **Intake template rebuilt to MIRROR the master `Project Tasks` sheet** (rev 3.14). `build_template.py`
  now emits task header **A=Project · B=Phase · C=Type · D=Task · E=Start · F=Finish · G=Duration ·
  H=Assigned To · I=Status · J=PM · K=Milestone · L=Comments** (1:1 with master A–L; M/N are system).
  **Project (A)** and **PM (J)** auto-fill down via formula `=IF($B$6...)`/`=IF($B$7...)` from the info
  block. Status list matches the dashboard (`Not Started/In Progress/Completed/On Hold`); Assigned list =
  canonical orgs+people on the hidden `Lists` sheet (editable; column also takes free text). `Import-Intake.ps1`
  gained a **MIRROR** layout reader (header A="Project" & D="Task" → 1:1 map; falls back to info-block
  Project/PM when the autofill formula isn't cached; guards `=*` formula text). LEGACY + old BRANDED still
  read. Download link cache-buster bumped to `?v=20260617`. **Two load paths now work:** drop in Intake
  Inbox (auto-import) OR Paste→Values into Excel.
- **Assigned-To dropdown on the dashboard editor = ALREADY LIVE**: `ptAssigned` is a `<datalist>`
  (`ptAssignList`) populated from `projAssignees()` (distinct `who` across all project tasks) — free text +
  autocomplete (type "ELEC" → Electricians if present in data). Auto-learns from the workbook.

### Still open from the morning queue
- **Siemens DI + Medtronic imports** — NOT yet written (see below; the `/tmp/build_import.py` draft builds
  both into the workbook in one pass to send to Rich; rerun against his LATEST uploaded master).
- **Upload tab — CONFIRMED design (Rich 2026-06-17):** in-browser upload on the Projects tab. Flow:
  download the MIRROR template → fill new project data → **upload via the new Upload tab** → dashboard
  parses the xlsx client-side → POSTs rows to the Power Automate flow → shows on the next 15-min cycle.
  **Replace-by-project MERGE:** if the uploaded Project name matches an existing project EXACTLY, replace
  that project's rows with the upload (else append a new project). IMPLEMENTATION NOTE: the Project Gantt
  (sheet6) mirrors Project Tasks by ABSOLUTE row, so the Office Script must do replace SAFELY = append new
  rows + **clear-contents** of the old project's rows (do NOT delete rows / shift them) to avoid breaking
  the mirror. New flow/script action: `importProject` {project, pm, tasks[], replace, pin, user}.
- **MRA Shop lane preview** — Rich earlier asked for a preview of a dedicated aggregate "MRA Shop" lane row
  before loading live (separate from the white-outline highlight, which is done).

## In progress / queued (2026-06-17)

- **Siemens DI + Medtronic imports = DONE / LIVE** (verified 2026-06-17 against live `data.js`,
  generated 8:22 AM): **Siemens DI Pedestal = 15 tasks** (renamed from "Seimans", old 2 rows replaced),
  **Medtronic = 160 tasks** (old ~101 wiped + replaced with the new schedule + milestones). Rich saved
  the file I sent. The earlier "NOT yet written" note below was STALE and caused confusion — kept here
  only for the import decisions/spec. Remaining polish Rich owns offline: Medtronic assignee colors +
  assignee standardization (see Assigned-To dropdowns).
- **Siemens DI Pedestal import** (spec, DONE — from Rich's PDF "SIEMENS DI Preliminary Hard Date Schedule
  v1.06.10.2026"). Parsed to **15 tasks** across 5 phases (Project Planning / Creative Design /
  Production / Post Production / Launch). Decisions confirmed: fix spelling **Seimans → Siemens
  DI Pedestal** and **replace** its 2 existing rows (currently rows 318–319, Task IDs 317–318);
  PM=Megan Fraser; party → Assigned To (MRA / Siemens DI / Heitek / Combined); dates 2026 → Finish
  (two ranges get Start+Finish); Completed→`Completed`, Upcoming/Future→`Not Started`; milestones
  ◆ = "Pedestal Completion" (Jul 31) + "Upcoming Event · Boston, MA" (Aug 5).
- **Medtronic import** (spec, DONE — from "Medtronic_Production_Schedule_v4.06.05.2026.xlsx", sheet `2026`).
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

