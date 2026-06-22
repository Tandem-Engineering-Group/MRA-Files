# STEP 3 — Kill the .xlsx → SharePoint Lists

Goal (Rich's north star): **never open the Excel file for anything.** Move the
source of truth off `MRA_Shop_Board_v6_9_7.xlsx` into **SharePoint Lists**, so:

- edits are **concurrent-safe** (the platform handles write collisions — the whole
  "two people save at once" class of bug disappears),
- the cloud export **no longer needs the workbook** (or Rich's PC), and
- the flaky **Office Script** write step goes away (this also kills the
  "Who"-column-blank gremlin, since we stop round-tripping through Excel).

The dashboard (`MRA_Dashboard.html`) does **not** change in this step — it keeps
reading `data.js`. We only swap what *produces* `data.js` and what *writes* edits.

---

## CURRENT STATUS (2026-06-22) — everything ready, waiting on IT

- ✅ **Lists created + data loaded** (Rich, via SharePoint "From Excel" import + a
  Power Automate "load table" flow): **MRA Users (4), MRA Jobs (54), MRA Shop Tasks
  (165), MRA Project Tasks (557)**. (Lists were made by GUI import, so column internal
  names may be the display names — the reader maps them tolerantly.)
- ✅ **Read path staged + CI-green:** `Export-FromLists.ps1` (Graph app-only auth) builds
  a candidate `data.js` from the Lists; `Compare-DataJs.ps1` diffs it vs the live
  Excel-built `data.js` (jobs/projects/users/holidays only). Fleet + logistics are
  passed through from the existing `data.js`.
- ⏳ **Blocked on IT:** the **Entra app registration** (`SHAREPOINT-READ-SETUP.md` — the
  forwardable email was given to Rich). IT returns Tenant/Client ID + secret → Rich adds
  GitHub secrets `SP_TENANT_ID` / `SP_CLIENT_ID` / `SP_CLIENT_SECRET`.
- ⚠️ **Backfill needed before the diff matches:** the GUI import didn't carry three Jobs
  fields the board uses — **PM, StartISO (start date), Notes** — and the Shop Tasks
  **Opened/Closed** dates. These columns are now in `Provision-MRA-Lists.ps1` +
  `Migrate-Data-To-Lists.ps1`. Backfill options once creds land: (a) re-run the migration
  for Jobs/Shop Tasks (`Migrate-Data-To-Lists.ps1 -Fresh`), or (b) a one-time column
  import from the current `data.js` (which still has them). Until backfilled, expect the
  compare to flag PM/startISO/notes diffs on jobs — that's expected, not a code bug.

### When IT delivers (the flip, ~30 min)
1. Rich adds the 3 GitHub secrets.
2. Claude runs `Export-FromLists.ps1 -OutFile data.fromlists.js` then
   `Compare-DataJs.ps1 data.js data.fromlists.js`.
3. Backfill PM/Start/Notes (+ Opened/Closed) until the compare says **MATCH**.
4. Wire the read into `export.yml` (Lists source), keep Excel path as rollback.
5. Then the **write path** (Power Automate Switch → List items) per the mapping below.

---

## Architecture (chosen)

```
        BEFORE                                  AFTER (Step 3)
  ┌──────────────┐                        ┌──────────────────────┐
  │  Excel .xlsx │  ← writes (Office       │  SharePoint Lists     │ ← writes (Power
  │  (workbook)  │     Script, flaky)      │  Jobs/ShopTasks/...   │    Automate → List
  └──────┬───────┘                        └──────────┬───────────┘    item, reliable)
         │ Export-Data.ps1 reads xlsx                │ Export-FromLists.ps1 reads Lists
         ▼                                            ▼
      data.js  ──→ dashboard (unchanged)          data.js  ──→ dashboard (unchanged)
```

- **Read path:** new `Export-FromLists.ps1` reads the Lists (PnP/Graph) and emits the
  **exact same `data.js` shape** the dashboard already expects. `fleetio` (Fleetio +
  Samsara) and `mraStatus` (logistics calendars) stay sourced as they are today —
  they were never in Excel.
- **Write path:** the dashboard already POSTs JSON actions to a Power Automate HTTP
  trigger. We replace the "Run Office Script" action inside that flow with a
  **Switch on `action` → SharePoint Create / Update / Delete item** on the right List.
- **Dates are stored as text `YYYY-MM-DD`** (not List date columns) on purpose — the
  dashboard already speaks ISO strings, and it sidesteps every timezone/serial-date
  headache the Excel COM path had.

---

## The Lists (exact schemas)

Internal names have no spaces. `Title` is reused as the most natural key per list.
Date-ish fields are **Text** holding `YYYY-MM-DD`.

### `MRA Users`
| Field (display) | Internal | Type | Notes |
|---|---|---|---|
| Name | Title | Text | the person (was Users!A) |
| Code | Code | Text | login code (was Users!B) |
| Active | Active | Yes/No | default Yes (was Users!C) |
| Role | Role | Choice | Admin / Editor / Viewer (enables Step 4) |

### `MRA Jobs`  (one item per floor job / trailer)
| Field | Internal | Type | Notes |
|---|---|---|---|
| Project | Title | Text | program / job name (group key) |
| Bay | Bay | Text | trailer / bay |
| Client | Client | Text | |
| JobNum | JobNum | Text | |
| JobStatus | JobStatus | Choice | Active/Scheduled/On Hold/Shipped/Leave/TBD |
| Category | Category | Text | e.g. `general` / `floor` |
| ShipISO | ShipISO | Text | YYYY-MM-DD (optional) |
| StartISO | StartISO | Text | YYYY-MM-DD (added 2026-06-22 — board uses it) |
| PM | PM | Text | project manager (added 2026-06-22) |
| Notes | Notes | Note | job notes / Notes-cell fallback (added 2026-06-22) |
| SortOrder | SortOrder | Number | board order |
| PhysicalBay | PhysicalBay | Yes/No | is this a real bay |

### `MRA Shop Tasks`  (one item per floor task)
| Field | Internal | Type | Notes |
|---|---|---|---|
| Task | Title | Text | task text |
| Project | Project | Text | matches `MRA Jobs`.Title |
| Assigned | Assigned | Text | who |
| Status | Status | Choice | Open / In Progress / Done / N/A |
| Milestone | Milestone | Yes/No | |
| Comments | Comments | Note | |
| Opened | Opened | Text | YYYY-MM-DD (added 2026-06-22) |
| Closed | Closed | Text | YYYY-MM-DD; drives the "(closed m/d/yy)" tag (added 2026-06-22) |
| SortOrder | SortOrder | Number | |

### `MRA Project Tasks`  (one item per project task)
| Field | Internal | Type | Notes |
|---|---|---|---|
| Task | Title | Text | task text |
| Project | Project | Text | |
| TaskID | TaskID | Number | the per-project Task ID (col M) |
| Phase | Phase | Text | |
| Type | Type | Text | |
| Assigned | Assigned | Text | "Group / Person" allowed |
| StartISO | StartISO | Text | YYYY-MM-DD |
| FinishISO | FinishISO | Text | YYYY-MM-DD |
| Duration | Duration | Text | |
| Status | Status | Text | Not Started / In Progress / Completed / On Hold (+ % handled in text like today) |
| PM | PM | Text | |
| Milestone | Milestone | Yes/No | |
| Comments | Comments | Note | |
| Predecessor | Predecessor | Text | predecessor Task ID |
| Sub | Sub | Yes/No | is a subtask |
| ParentID | ParentID | Number | parent Task ID (blank = top-level) |
| SubRes | SubRes | Text | |
| EstDays | EstDays | Number | |
| EstHours | EstHours | Number | |
| Budget | Budget | Number | |
| SortOrder | SortOrder | Number | |

### `MRA Holidays`  (optional — could stay computed in the dashboard)
| Field | Internal | Type | Notes |
|---|---|---|---|
| Name | Title | Text | |
| DateISO | DateISO | Text | YYYY-MM-DD |
| Country | Country | Choice | US / CA / BOTH |

---

## Cutover plan (testable chunks — nothing is irreversible)

1. **Provision** — run `Provision-MRA-Lists.ps1` (creates the Lists + columns,
   idempotent). *[script ready in this repo]*
2. **Migrate** — run `Migrate-Data-To-Lists.ps1` once: reads the current `data.js` and
   fills the Lists. Spot-check a project + a trailer against the board. *[DONE via GUI
   import; re-run for the new Jobs PM/Start/Notes + Shop Tasks Opened/Closed backfill]*
3. **Read swap** — point the export at the Lists: `Export-FromLists.ps1` emits the same
   `data.js`; `Compare-DataJs.ps1 data.js data.fromlists.js` diffs them until they
   match, then wire it into `export.yml`. *[staged + CI-green; needs the app reg]*
4. **Write swap** — in the existing Power Automate flow, replace **Run Office Script**
   with a **Switch (action)** → SharePoint item ops (see mapping below). Test each
   action from the dashboard.
5. **Verify & retire** — run both paths for a few days; once the Lists path is trusted,
   stop the workbook shuttle and archive the .xlsx. Excel is now optional.

**Rollback at any point:** the workbook + `Export-Data.ps1` still work; just point the
export back at the .xlsx.

---

## Write-path mapping (Power Automate flow)

The dashboard already sends these `action`s. Replace the Office Script step with a
`Switch` on `triggerBody()?['action']`:

| action | List | operation |
|---|---|---|
| `addTask` | MRA Shop Tasks | Create item (Project, Title=task, Assigned, Status=Open, Milestone, Comments) |
| `editTask` | MRA Shop Tasks | Get items (Project eq … and Title eq taskOld) → Update item |
| `closeTask` / `reopenTask` | MRA Shop Tasks | Update item (Status) |
| `deleteTask` | MRA Shop Tasks | Get items → Delete item |
| `addProjectTask` | MRA Project Tasks | Create item (next TaskID = max+1 for that Project) |
| `editProjectTask` | MRA Project Tasks | Get items (Project, TaskID) → Update item |
| `deleteProjectTask` | MRA Project Tasks | Get items → Delete item |
| `closeProjectTask`/`reopenProjectTask` | MRA Project Tasks | Update item (Status) |
| `deleteProject` | MRA Jobs + MRA Project Tasks | Delete the job + all its tasks |
| `importProject` | MRA Project Tasks | replace-by-project: delete old rows, create new |
| `setHoliday`/`deleteHoliday` | MRA Holidays | Create/Update / Delete |
| (logins) addUser/editUser | MRA Users | Create / Update |

Every payload already carries `user` → write it straight into a `ChangedBy`/`Who`
audit column (or rely on the List's built-in Modified By). **The "Who" blank bug is
gone** because there's no Office Script in the path anymore.

---

## Who does what

- **Claude (me):** all the scripts (`Provision`, `Migrate`, `Export-FromLists`,
  `Compare-DataJs`), the exact flow step list, the `export.yml` change, and verification
  diffs.
- **Rich (M365 — I can't do these from the web session):**
  1. Run `Provision-MRA-Lists.ps1` once (you're a site owner).
  2. Run `Migrate-Workbook-To-Lists.ps1` once.
  3. For the cloud read, create a small **Entra app registration** (Sites.Selected /
     Sites.Read on the MRA Site Project site) so `export.yml` can read the Lists
     headlessly — OR keep the read running from your PC/shuttle for now.
  4. Edit the Power Automate flow per the mapping above.

We'll do them in order and verify each before the next. Excel stays the live source
until step 5, so the board never goes dark.
