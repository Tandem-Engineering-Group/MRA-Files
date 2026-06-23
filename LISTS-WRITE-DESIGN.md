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
