# Projects write-back — spec (next session, after the team's project cleanup)

Goal: bring the same dashboard write-back to the **PROJECTS** tab that the FLOOR
board now has — add / edit / delete / close / reopen **project tasks**, plus
instant on-screen updates — reusing the exact same plumbing.

Reuses (no new setup): the existing close flow URL (`SHOP_WRITE_URL` =
`CLOSE_FLOW_URL`), the one `Close Shop Task` Office Script, the **1974** PIN gate
(client + server), and the optimistic/instant-update + poll-gating mechanism.

## Source of truth
**Project Tasks** sheet. Columns:
`A Project · B Phase · C Type · D Task · E Start · F Finish · G Duration ·
 H Assigned · I Status · J PM · K Milestone · L Comments`
(`Add-TaskRow` in `Export-Data.ps1` already reads these.) Done = Status `Completed`.

## 1. Export change (Export-Data.ps1)
Today each project exports only `milestones[]`. Add a full task list so the
dashboard can show/edit every task:

- In `Add-TaskRow`, also push each row into a per-project `tasks` array:
  `{ t=Task(D), phase=B, type=C, who=Assigned(H), startISO=E, finISO=F,
     st=Status(I), ml=Milestone(K), cm=Comments(L), done=($I -eq 'Completed') }`
- Emit `tasks = @($o.tasks)` on each project object (alongside `milestones`).
- Keep `milestones[]` as-is (gantt/gates rely on it).

Matching key for edits = **project name + task text** (same approach as Shop
Tasks; Project Tasks rows have no stable id). Watch for duplicate identical task
text within a project — edits/deletes hit the first match.

## 2. Office Script — new branches (Close Shop Task)
Point at `workbook.getWorksheet("Project Tasks")` (find the table name first; if
it's a ListObject use it, else write by row within the used range). Mirror the
Shop Tasks branches, matched by project(A)+task(D):

- `addProjectTask` → append row: Project, Phase, Type, Task, Start(serial),
  Finish(serial), Duration(optional), Assigned, Status(default `Not Started`),
  PM, Milestone, Comments. Date cells → `m/d/yyyy`, Eastern via `todaySerial`/`serialOf`.
- `editProjectTask` → match project+taskOld; set Task(D), Assigned(H), Start(E),
  Finish(F), Status(I), Milestone(K), Comments(L). If Status→Completed and no
  finish, optionally stamp finish = today (decide with Rich).
- `deleteProjectTask` → match project+task; `getEntireRow().delete(Up)`.
- `closeProjectTask` → set Status `Completed` (+ finish date if blank).
- `reopenProjectTask` → set Status back to `In Progress`/`Not Started`.
- (optional) `addProject` — a project is just its first task row, so `addProjectTask`
  with a new Project name effectively starts one. Probably no separate branch needed.

Keep the `1974` pin check and the same `serialOf`/`todaySerial` helpers.

## 3. Dashboard UI (PROJECTS view)
- Reuse `🔒 Edit mode` (same toggle reveals project-task tools too) and the
  `editTaskModal` pattern (add Phase/Type/Start/Finish fields for projects).
- Surface tools where tasks render: the expanded **milestone/gate rows** and/or
  a per-project **task list** (new). Likely add a small expandable task list per
  project so every task (not just milestones) is editable.
- `➕ Add project task` button (project picker + new-project option), and an
  `➕ Add project` entry point.
- Dropdowns: Assigned (reuse `ASSIGNEE_OPTIONS` + PM/people list), Status
  (Not Started / In Progress / Completed / On Hold), Phase (free text or the
  project's existing phases), Milestone (Yes/No).
- Optimistic updates: reuse `oApply()` / `markPending()` + the `generatedAt`
  poll-gate so project edits show instantly and don't bounce. Add an
  `oRecomputeProject(p)` to refresh taskCount/doneCount/pct/milestones locally.

## 4. Open questions for Rich (resolve at cleanup)
- Final phase names / task structure after the team cleanup (build against that).
- Do we edit **all tasks** or just **milestones/hard-dates** from the dash?
- Status vocabulary to standardize (Not Started / In Progress / Completed / On Hold?).
- Should closing the last task of a phase auto-advance anything? (probably no.)

## Effort
Script branches: small (copy Shop Tasks pattern). Export expansion: moderate.
Projects UI: the larger piece (denser screen). All transport/auth/instant-update
already exists, so it's mostly UI + export, not new infrastructure.
