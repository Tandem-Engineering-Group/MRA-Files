# Phase B — Unified Structured Tasks + Close-from-Dashboard (build spec)

Goal: one common task model across **shop** and **projects**, with real
**Opened / Closed dates + Status** per task — so the dashboard can do true
per-task history/reporting, and (Phase 2) let you **close a task from the
dashboard** behind a PIN. Designed to be **additive and backward-compatible**:
the live board never goes dark during the switch.

---

## 1. Today (why we're changing it)

- **Shop tasks** live as free text in the Input tab's **Notes cell (col H)** —
  one blob per job, `x ` prefix = done, dates hand-typed. No structure, no real
  dates the system can sort/filter on.
- **Project tasks** already *are* structured rows (Project Tasks tab:
  Project · Phase · Type · Task · Start · Finish · Duration · Assigned · Status ·
  PM · Milestone · Comments). So projects are half-way there.
- The workbook's **Board / Gantt / Sal Tasks** tabs are formula-driven off the
  **Input** tab. ⚠️ Ripping tasks out of Input's Notes cell would break those
  formulas — so we do **not** gut Input.

## 2. The design (recommended): add a "Shop Tasks" sheet, don't break Input

Keep **Input** as the job/bay-level sheet it is today (Bay, Project, Client,
Job#, Start, Comp, Status, PM). Add a new **`Shop Tasks`** sheet that mirrors
**Project Tasks**, one row per task:

| Col | Field | Notes |
|----|-------|-------|
| A | Job # | links the task to the Input job (e.g. J1428) |
| B | Bay | optional, for grouping |
| C | Task | the task text |
| D | Assigned | person (Sal, etc.) — real field, not buried in text |
| E | Opened | date opened |
| F | Closed | date closed (blank = open) |
| G | Status | Open / In Progress / Done |
| H | Milestone | Yes/No |
| I | Comments | |

Result: **shop tasks and project tasks share the same shape.** The Notes cell
can stay during transition (we read both), then retire once everyone's on rows.

## 3. What changes, by piece (all backward-compatible)

- **`Export-Data.ps1`** — read tasks from `Shop Tasks` (rows) when present;
  fall back to parsing the Notes cell when not. Emits the same `openTasks` /
  `doneTasks` the dashboard already uses, **plus** per-task `assigned`,
  `opened`, `closed`, `status`. (Same dual-read trick we used for the intake
  importer — old files keep working.)
- **Dashboard** — render Sal cards / bay task lists / History from the
  structured fields when available; keep parsing free-text when not. Visible
  change is tiny: optional "closed 6/14" on done tasks, and exact per-task date
  filtering in History.
- **Intake template** — already structured; just confirm columns line up so
  projects + shop + the future *Upload Project* button all use one format.

## 4. Phase 2 — close a task from the dashboard (PIN-gated)

Board is static/one-way today, so closing needs a small write-back path. Plan:

1. Each task gets a small **✓ close** control (Sal cards + bay task lists).
2. Click → **PIN prompt** (shared code; gates who can close).
3. Dashboard POSTs `{job, task, closedBy, date}` to a **Power Automate flow**
   (or appends to a **SharePoint list**) — you authorize this once.
4. The dashboard PC's 15-min job reads pending closes, sets the task's
   **Closed date + Status=Done** on the `Shop Tasks` sheet, republishes.
5. Task shows closed on the board next cycle (~≤15 min).

Notes: pairs cleanly with §2 (just flips two cells). PIN is a shared gate, not
per-person identity — fine for "only I close things." Instant (vs ~15 min)
would need an Azure Function with write creds; start with the flow.

## 5. Migration of existing tasks

For each current job, move the Notes-cell lines into `Shop Tasks` rows:
`x ` lines → Status=Done (Closed = any date in the text, else today);
numbered lines → Status=Open. I can script a one-time converter you run on the
PC, or do it during the workbook edit when you hand it over.

## 6. Execution order (safe cutover — board stays live throughout)

1. **(me, now)** This spec. ✅
2. **(me, solo)** Ship the **backward-compatible dashboard + Export-Data** that
   read *either* format. Deploy — nothing changes yet because the data's still
   old-format. Zero risk.
3. **(you)** Drop the workbook here → **(me)** add `Shop Tasks`, migrate
   existing tasks, send it back → **(you)** put it back + copy the new
   `Export-Data.ps1` onto the PC.
4. First export now publishes structured tasks; dashboard shows real dates.
5. **(you)** Stand up the Power Automate flow (I'll give exact steps) →
   **(me)** wire the PIN **✓ close** button → deploy. Phase 2 live.

## 7. Decisions to lock with the PMs

- Final column set / names (so shop + projects + Upload-Project all match).
- Status vocabulary (Open / In Progress / Done — anything else?).
- The shared **PIN** for closing (and whether projects can be closed too).
- Whether to retire the Notes cell immediately or run both for a while.
