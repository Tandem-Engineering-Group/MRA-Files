# Lists Write-Side / Cutover Design (Step 3 — kill the .xlsx)

Engineering reference for moving the dashboard OFF the workbook and onto the 4 SharePoint
Lists for BOTH read and write. Read side is built + verified (Export-Data.ps1 `Build-FromLists`,
gated by `MRA_LISTS_JSON`; the "MRA Lists to JSON" flow emits raw list rows to `lists.json`).
This doc specs the WRITE side + the cutover.

## Data-safety guarantee (no edit is ever missed)
- Until cutover, ALL edits go to the **workbook** (unchanged). The lists are a frozen snapshot
  and do NOT track live edits — that's fine, they aren't live.
- Cutover step 1 = a **fresh full reload** of the workbook into the lists (the loader below), which
  captures every edit made up to that moment. No gap.
- After cutover, edits go to the lists (write flow), workbook retired.
- => Users keep editing normally the whole time; never hand-maintain the lists.

## Architecture (minimize Power Automate pain)
The dashboard already funnels EVERY edit through one function, `shopWrite(payload)` (~line 3201),
which POSTs `{action, pin, user, ...}` no-cors to `CLOSE_FLOW_URL` (flow "MRA Sync V2", runs the
Office Script `MRA-Sync.ts` against the workbook).

Plan: keep all ~24 call sites UNCHANGED. Add a translation layer INSIDE `shopWrite` (JS, fully
testable, no PA): switch on `payload.action` -> emit one or more normalized **ops**, and POST
`{ops:[...], pin, user}` to a NEW flow URL. Gate with `const USE_LISTS_WRITE=false;` so it's dormant
until the new flow is live (existing behavior 100% unchanged while false). At cutover: flip the flag
+ point reads at the lists, together.

### Op format
```
{ verb: "create"|"update"|"delete",
  list: "Jobs"|"ShopTasks"|"ProjectTasks"|"Users"|"Holidays",
  id:   <SharePoint item id>,        // for update/delete by item (preferred, see IDs below)
  match:{ Col: val, ... },           // for cascades / when no id (find items by field)
  set:  { Col: val, ... } }          // friendly column names (list display names)
```
Friendly column names = the import-file headers = list display names (PA's Create/Update item
shows these; internally they're Title + field_N, but PA hides that). Keeps the dashboard decoupled
from field_N.

### List schemas (friendly columns; first col is the list's Title internally)
- **Jobs**: Project*, Bay, Client, JobNum, Start, Finish, Status, PM, Notes  (*=Title)
- **ShopTasks**: Task*, Project, JobNum, Bay, Assigned, Status, Opened, Closed, Milestone, Comments
- **ProjectTasks**: Task*, Project, TaskID, Phase, Type, Assigned, Start, Finish, Duration, Status,
  PM, Milestone, Predecessor, Sub, SubRes, Order, EstDays, EstHours, Budget, Parent, Comments
- **Users**: Name*, Code, Role, Active
- **Holidays**: Name*, Date, Country

### ID strategy (so update/delete are direct, not fragile text matches)
Export `Build-FromLists` must stamp the **SharePoint item id** onto every entity it emits:
- job.row   = item id  (jobs)
- task._iid = item id  (shop tasks; keep existing matching as fallback)
- projTask: matched by **TaskID** (stable data field already in the list) — item id optional
The dashboard then sends `id` for update/delete -> flow does **Update item / Delete item by id**
(no filter loop). Cascades (rename) use `match` (Get items by field -> loop). TODO: add the id
stamping in Build-FromLists when wiring cutover.

## Action -> ops map (from MRA-Sync.ts behavior)
| action | ops |
|---|---|
| (legacy close, no action) | update ShopTasks id set{Status:"Done", Closed:today} |
| addTask | create ShopTasks set{Task,Project,JobNum,Bay,Assigned,Opened:today,Status:"Open",Milestone,Comments} |
| editTask | update ShopTasks id set{Task,Assigned,Status,Milestone,Comments, Closed:(today if Done else "")} |
| deleteTask | delete ShopTasks id |
| reopenTask | update ShopTasks id set{Status:"Open", Closed:""} |
| addJob | create Jobs set{Project,Client,JobNum,Bay,Start,Finish:completion,Status,Notes,PM} |
| editJob | update Jobs id set{Bay,Status,Start,Finish,Notes,Client,PM[,Project:newProject][,JobNum:newJobNum]}; if newProject: + update ShopTasks/ProjectTasks match{Project:old} set{Project:new}; if newJobNum: + update ShopTasks match{JobNum:old} set{JobNum:new} |
| deleteJob | delete Jobs id |
| renameProject | update ProjectTasks/Jobs/ShopTasks match{Project:old} set{Project:new} |
| setProjectPM | update ProjectTasks/Jobs match{Project} set{PM} |
| renameAssignee | update ProjectTasks match{Assigned:old} set{Assigned:new}; update ShopTasks match{Assigned:old} set{Assigned:new} |
| deleteProject | delete ProjectTasks/Jobs/ShopTasks match{Project} (Lists allow real delete — no Gantt mirror issue) |
| setUser | upsert Users match{Name} set{Code,Active:"Yes"} |
| deleteUser | delete Users match{Name} |
| renameUser | update Users match{Name:old} set{Name:new} |
| setHoliday | upsert Holidays match{Name,Date} set{Country} |
| deleteHoliday | delete Holidays match{Name[,Date]} |
| addProjectTask | create ProjectTasks set{...; TaskID = max+1 (flow assigns) } |
| editProjectTask | update ProjectTasks match{Project,TaskID} set{present fields} (Gantt drag = same) |
| deleteProjectTask | delete ProjectTasks match{Project,TaskID} (real delete OK) |
| closeProjectTask | update ProjectTasks match{Project,TaskID} set{Status:"Completed", Finish:today if blank} |
| reopenProjectTask | update ProjectTasks match{Project,TaskID} set{Status:"In Progress"} |
| importProject | if replace: delete ProjectTasks match{Project}; then create each task (flow assigns TaskIDs) |
| setEOTM | NOT here — separate "MRA EOTM" flow -> $web blob (unchanged) |

Note: the Lists kill the clear-vs-delete workaround (deleteProject/deleteProjectTask/import-replace
can REAL delete; the Project Gantt absolute-row mirror was a workbook-only constraint).

## Write flow (new — what Rich builds; spec only)
HTTP-trigger flow ("Anyone"), receives `{ops, pin, user}`. Steps:
1. Parse JSON. 2. **Validate pin** against MRA Users (reject if not a known code). 3. Apply-to-each op
-> Switch(verb): create / update / delete. Use either PA native Create/Update/Delete item (friendly
columns, ~per-list branches) OR "Send an HTTP request to SharePoint" generic (fewer branches,
internal names). Decide at build time; native = simpler for Rich, more branches.
Security: pin gate + restrict to the 4 known lists (public endpoint, same threat model as today).

## Bulk loader (replaces "From Excel", which truncates big lists ~240 rows)
For the cutover full reload + the JFSD-style gaps: load via the write flow itself (POST create-ops in
batches) or a one-off "Apply to each row -> Create item" flow reading the workbook-derived JSON.
NOT "From Excel". This is also how the fresh cutover reload happens.

## Cutover sequence (one coordinated move)
1. Build write flow; test in PARALLEL (preview dashboard -> new flow -> lists) — live untouched.
2. Verify writes land + read still matches live for a bit.
3. Flip: fresh full reload (loader) -> set `USE_LISTS_WRITE=true` + point reads at lists
   (MRA_LISTS_JSON via the Lists->JSON flow to the pipeline blob + export.yml) -> deploy.
4. Retire the workbook shuttle/Office-Script path.

## PROGRESS LOG
- 2026-06-23: **Write pipeline PROVEN.** Built flow **"MRA Lists Write 2"** (workflow id
  `12d3826052ea4f5584ec2921fc83172c`, trigger "Anyone"). A POSTed `create` op landed a real
  row in MRA Shop Tasks. Lesson learned the hard way: the new PA designer **auto-wraps any
  Dynamic-content/array reference in a "For each"** — so build with **fx expressions only**,
  leave the trigger schema EMPTY, and parse inline with `json(triggerBody())`. The HTTP
  "Headers"/"Body" fields are hidden under **Advanced parameters -> Show all**.
- **Working create branch** (the whole flow right now = trigger -> this one action, no Switch/loop):
  Send an HTTP request to SharePoint, Method POST,
  Uri `concat('_api/web/lists/getByTitle(''', json(triggerBody())?['op']?['list'], ''')/items')`,
  Headers Accept + Content-Type = `application/json;odata=nometadata`,
  Body `json(triggerBody())?['op']?['body']`.
- **NEXT: add Switch(verb) + update/delete WITHOUT a nested loop** (the For-each was the pain).
  Match is unique for the common ops, so use `first(...)`:
  - update: GET `.../items?$filter=<op.filter>&$select=Id&$top=1` -> MERGE to
    `.../items(@{first(body('HTTP_Get')?['value'])?['Id']})` with headers `IF-MATCH:*`,
    `X-HTTP-Method:MERGE`, body `json(triggerBody())?['op']?['body']`.
  - delete: same GET -> POST `.../items(<first Id>)` with `IF-MATCH:*`, `X-HTTP-Method:DELETE`.
  - create: the POST above.
  - Wrap the three in a Switch on `json(triggerBody())?['op']?['verb']`.
  - Cascades (renameProject/setProjectPM/renameAssignee/deleteProject = many rows) need a real
    loop over all matches -> defer to v2; rare.
- Then: set `LISTS_WRITE_URL` + `USE_LISTS_WRITE=true` in MRA_Dashboard.html, fresh full reload
  of the lists, deploy, retire workbook.
- 2026-06-23 PM: **create + update + delete ALL PROVEN** end-to-end via curl against
  "MRA Lists Write 2". Switch routes on verb; update/delete use FindToUpdate/FindToDelete
  (GET `$filter ...&$select=Id&$top=1`) then MERGE/DELETE to `items(first(...).Id)` with
  headers `IF-MATCH:*` + `X-HTTP-Method: MERGE|DELETE`. `LISTS_WRITE_URL` now wired in the
  dashboard (DORMANT — `USE_LISTS_WRITE` still false).
- REMAINING before cutover:
  1. ✅ **`upsert` — DONE in code 2026-06-24 (no PA verb).** The dashboard `_listOpsRaw` splits
     setUser/setHoliday into **update** (if the name/date already exists in `MRA_DATA`) **else
     create** — so the flow only ever sees create/update/delete.
  2. ✅ **Cascades — DONE in code 2026-06-24 (no PA loop).** Instead of one match-many op, the
     dashboard now **fans each cascade out into one op PER ROW, matched by SharePoint item Id**,
     by enumerating the affected rows straight from the in-memory board. Covers renameProject /
     setProjectPM / renameAssignee / deleteProject / editJob(newProject|newJobNum) / importProject.
     Linchpin: **`Build-FromLists` now stamps `_id` (SharePoint item Id) on every entity** (jobs
     already had `row`; added to shop tasks via the shop obj + Build-TasksFromRows, and to project
     tasks via Add-TaskRowObj). `_listOps` emits `Id eq <n>` (numeric, UNQUOTED — like the pin)
     for these; the existing FindToUpdate/FindToDelete branches handle each single-Id op with no
     loop. Verified by extracting the real functions and running cascade scenarios through them
     (renameProject → 6 per-row ops by Id, deleteProject → 6 deletes, renameAssignee → only the
     matching rows, setUser EXISTING→update / NEW→create). **DORMANT** until cutover
     (`USE_LISTS_WRITE` still false; reads still from the workbook, so `_id` is only present once
     reads come from Lists).
  3. ✅ **SECURITY: pin-gate the flow — DONE & VERIFIED 2026-06-24.** Added two actions at the
     TOP of "MRA Lists Write 2" (before the Switch): **CheckPIN** = "Send an HTTP request to
     SharePoint" GET
     `concat('_api/web/lists/getByTitle(''MRA Users'')/items?$select=Id&$top=1&$filter=field_1 eq ''', json(triggerBody())?['pin'], '''')`
     (Accept/Content-Type `application/json;odata=nometadata`), then a **Condition**
     `length(body('CheckPIN')?['value']) is equal to 0` → True branch **Terminate (Failed,
     "Rejected: unknown code")**; False empty → falls through to the Switch. Curl-verified:
     bad code `0000` → run **Failed** (rejected), real code `1974` → run **Succeeded**.
     ⚠️ LESSON: `json(triggerBody())` needs the body to arrive as a **string** — the dashboard
     posts `Content-Type: text/plain;charset=UTF-8` (no-cors), so it works. A request sent with
     `application/json` makes PA pre-parse the body to an Object and `json()` errors → the run
     **fails closed** (no write), which is safe. Code column being **text** was fine; no
     numeric-filter change needed.
  4. **Parallel test** with a preview dashboard (USE_LISTS_WRITE=true on a test copy) -> real
     edits land in lists; live stays on workbook.
     - 2026-06-24: read path is CODE-READY — `Export-FromLists.ps1` (Graph reader) now stamps
       `_id` on jobs/shop tasks/project tasks, and `deploy.yml` has a **`listscand`** dispatch
       mode that builds a candidate data.js from the Lists, checks `_id`, and diffs vs live (no
       publish). **BLOCKER:** the run failed because the repo secrets **SP_TENANT_ID /
       SP_CLIENT_ID / SP_CLIENT_SECRET are EMPTY** — the Graph "MRA Dashboard Lists Reader" app
       (Part A = IT) was never finished / its creds never added. The guard exits cleanly with
       that message. Two ways to unblock: (A) IT creates the Entra app (Graph Sites.Selected on
       MRASiteProject) → partner adds the 3 values as repo secrets → re-run `listscand` (then
       it's fully automatic forever); or (B) the "MRA Lists to JSON" Power Automate flow (Rich's
       login, no IT) writes lists.json to the pipeline blob and the export reads it via
       `MRA_LISTS_JSON` + `Build-FromLists` (already `_id`-stamped). Recommended: A (one-time IT,
       hands-off after; same team needed for Step 4 SSO).
  5. **Cutover:** fresh full reload of lists from workbook (bulk loader, not From-Excel) +
     flip `USE_LISTS_WRITE=true` + point reads at lists + deploy + retire workbook.

## 2026-06-24 — WRITE PATH PROVEN END-TO-END (no Excel, no IT/Graph)
Read path went the **Power Automate** route (option B), not Graph: the **"MRA Lists to JSON"** flow
(Rich's login) writes `lists.json` to the **`pipeline`** blob; **`build_from_lists.py`** (new) decodes it
to `data.js`. Verified + standing up a side-by-side preview, then a write-enabled preview, drove the
write test through the **real UI**. All confirmed in the Lists via the row **Modified** timestamps.

**PROVEN (persisted to the Lists):** shop **add** + **close**, project **add** + **close**.
Preview harness = `deploy.yml` mode **`listspreview`** → publishes `preview-lists2.html` (live dashboard
pointed at `data.lists.js`, `USE_LISTS_WRITE=true`, build # stamped in the banner) + `data.lists.js`;
`listspreview-cleanup` removes them. Live board untouched the whole time.

**HARD-WON LESSONS (these shaped the fixes):**
- **The write flow's `FindToUpdate` can ONLY match by TEXT fields.** A `$filter=Id eq <n>` (internal
  item id) returns EMPTY → the MERGE then targets `.../items` (collection) → **`SP.ListItemEntityCollection
  does not support HTTP method`** BadRequest. Text filters (`field_1 eq '..' and Title eq '..'`) work.
  ⇒ **All matching must be text.** Switched project-task close/edit/delete/reopen to match by
  **{Project, Title}** (the proven shop-close path). The `_id`/`_ptMatch`/`idOps` "match by item Id"
  design (and jobs' `{Id:jId}`) is therefore DEAD for writes — see remaining work.
- **Number columns reject non-numeric writes (`Edm.Double`).** "From Excel" made several columns
  numeric. Do NOT write them: **ShopTasks `field_8`** (dropped the bogus Milestone map), **ProjectTasks
  `field_2` (TaskID)** + **`field_13` (Predecessor)** (TaskID is match-only, Predecessor dropped from the
  write map — needs a Text column to persist).
- **New project tasks get NO TaskID** — `importProject`/`addProjectTask` create a row but the flow does
  not assign `field_2`, so it lands empty (saw task 570). Fine for text-matched edits; revisit if TaskID
  is needed for predecessors/display.
- **Optimistic UI + cache confusion:** the board shows edits optimistically (localStorage) so a task can
  look "Completed" without having saved; and stale cached `preview-lists.html` repeatedly served old code.
  Fixes: publish to a **fresh filename** (`preview-lists2.html`) + **stamp the build # in the banner** so
  we can verify the loaded code. (Also: editing the LIVE board writes to the workbook, not the Lists.)

**DONE 2026-06-24 (commit 987824f):** ✅ All ops converted to TEXT matching. `editJob`/`deleteJob`
match the job by `{Project}` (Title); `renameProject`/`deleteProject`/`setProjectPM`/`renameAssignee`/
`editJob`(newProject|newJobNum)/`importProject`-replace fan out one text op per row via `taskOps`/`jobOps`
(`{Project, Task[, oldValue]}`). Dup-title-safe except `setProjectPM` (rare; documented). Simulated all six.
NO id-based matching remains in `_listOpsRaw`.

----------------------------------------------------------------------------------------------------
## ⭐ CUTOVER — START HERE (next session, planned 2026-06-25)
**State as of 2026-06-24:** read path AND write path are both BUILT + PROVEN end-to-end against the
SharePoint Lists, with **zero Excel**. Verified live via the write-enabled preview. Everything below is
committed on branch `claude/zealous-fermi-6n5pil`. Nothing about the LIVE board has changed yet — it still
reads/writes the workbook (`USE_LISTS_WRITE=false`). Cutover is the ONLY thing left.

**What exists now (no need to rebuild):**
- **Read:** `build_from_lists.py` turns `lists.json` → `data.js` (field_N map verified; stamps `_id`).
- **Read source:** the **"MRA Lists to JSON"** Power Automate flow writes `lists.json` to BOTH SharePoint
  (`/MRA Claude Code/01.1 RL Claude Bot/lists.json`) AND the private **`pipeline`** blob.
- **Write:** dashboard `_listOpsRaw`+`_listOps` (DORMANT behind `const USE_LISTS_WRITE=false`, line ~3218 of
  `MRA_Dashboard.html`) → posts ops to **`LISTS_WRITE_URL`** = the **"MRA Lists Write 2"** flow. All ops
  text-matched. PIN-gated. Proven: shop add/close, project add/close (persisted, timestamp-verified).
- **Preview harness:** `deploy.yml` mode **`listspreview`** publishes `preview-lists2.html` (live dashboard
  pointed at `data.lists.js`, `USE_LISTS_WRITE=true`, build # in banner) — the parallel test rig.
  `listspreview-cleanup` removes it. Also mode `listscand` builds a candidate `data.js` from the blob + diffs.

**CUTOVER CHECKLIST:**
1. **[Rich]** Put **"MRA Lists to JSON"** on a **Recurrence** trigger (every 15 min, like the workbook
   shuttle) — it's currently an Instant flow run by hand. This keeps `pipeline/lists.json` fresh on its own.
2. **[Claude+Rich]** **Fresh full reload of the Lists from the current workbook** at flip time, so the Lists
   capture every edit up to the cutover moment. Load via the **write flow in batches** (NOT "From Excel" —
   it truncates ~240 rows). One-time.
3. **[Claude]** **Wire the LIVE read off the Lists:** make the scheduled `data.js` build run
   `build_from_lists.py` against `pipeline/lists.json` (mirror the `listspreview` step but publish the real
   `data.js` to `$web`), instead of `export.yml`'s workbook→`Export-Data.ps1` path. Keep fleet/Samsara as-is
   (inherited from the live data.js base).
4. **[Claude]** **Flip the live board:** set `const USE_LISTS_WRITE = true;` in `MRA_Dashboard.html` (line
   ~3218), deploy `mode=live`. Now the live board reads AND writes the Lists.
5. **[Claude+Rich]** **Retire the workbook:** stop the "MRA workbook shuttle" flow + the Office-Script save
   path (and the workbook→`export.yml`). Keep one last workbook backup.

**Optional later hardening (not blocking):** get "MRA Lists Write 2" to support **item-id matching**
(`getItemById`) so we can drop text matching and kill the `setProjectPM`/dup-title edge; assign **TaskID** on
new project-task creates (flow currently leaves `field_2` empty); make `field_13`/`field_2` **Text** columns
if we ever want to write Predecessor/TaskID.
