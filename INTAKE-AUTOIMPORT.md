# Intake Drop Folder — auto-import setup

Lets team members add their project tasks themselves: they fill the intake
template **offline**, drop it in a shared folder, and the schedule picks it up
automatically. Nobody but the dashboard PC ever writes to the master workbook.

## How it flows
1. Team member downloads the template (the **⬇ Download Intake Template** button
   on the dashboard's Projects tab, or you email them the file).
2. They fill it in offline: the info block at top (Project / Job # / PM), then
   the task table (dropdowns + a Phase 1–5 skeleton are already there).
3. They save it and drop it in the **`Intake Inbox`** folder.
4. Your dashboard PC's 15-min job runs **`Import-Intake.ps1`** first: it opens
   the master in Excel, appends the rows to **Project Tasks**, archives the
   file, then the normal `Export-Data.ps1` + AzCopy push runs — so the rows
   show up on the dashboard that same cycle.

## One-time setup (on the dashboard PC)
The scripts live in your dashboard folder (next to `Export-Data.ps1` /
`Update-Auto.ps1` / `azcopy.exe`). Make sure these two files are there:

- `Import-Intake.ps1`  (new)
- `Update-Auto.ps1`    (now calls the import first — replace your copy)

That's it for files. The first scheduled run **creates the folders itself**:

```
...\01.1 RL Claude Bot\Intake Inbox\          <- team drops files here
...\01.1 RL Claude Bot\Intake Inbox\Archive\  <- processed files (timestamped)
...\01.1 RL Claude Bot\Intake Inbox\Rejected\ <- files with no "Enter Here" sheet
```

(The `Intake Inbox` folder sits next to the master workbook, so it's inside the
SharePoint-synced area — team members reach it via SharePoint/Teams.)

**Share the inbox with the team:** in SharePoint, open the `Intake Inbox`
folder → **Share / Copy link** → send it to whoever fills templates. They just
drop their finished file in there. Done.

## Requirements / things to know
- **Excel + logged-in session.** The import uses Excel itself (so charts, the
  Gantt and tables are preserved). It only runs when files are waiting, and it
  needs your dashboard PC to be **logged in** at the time. If it's logged off,
  files simply wait in the inbox and import on the next run while you're logged
  in. (The export + Azure push don't need Excel and keep working regardless.)
- **Master open?** If the master workbook is open (by you or via SharePoint),
  the import skips that cycle and retries next time — it never fights for the
  file. Nothing is lost.
- **Safe by design.** A file that isn't a real intake (no `Enter Here` sheet)
  is moved to `Rejected\`. A file that errors is left in the inbox for a look.
- **Template layout (current "branded" template).** `Import-Intake.ps1` reads
  the `Enter Here` sheet and fills Project Tasks (Project, Phase, Type, Task,
  Start, Finish, Duration, Assigned To, Status, PM, Milestone, Comments):
  - **Project** and **Project Manager** come from the one-time info block at the
    top (labels `Project / Client:`, `MRA Job #:`, `Project Manager:`). Project
    is **free text** — brand-new jobs are fine. If a Job # is given it's appended
    as `Name (J####)`.
  - **Per task row** (table whose header row is `Phase | Type | Task | Start |
    Finish | Duration | Assigned To | Status | Milestone | Comments`): a row is
    imported only if **Task** is filled, so the blank Phase 1–5 skeleton rows are
    ignored until you add tasks to them.
  - The reader finds the info-block labels and the task header **by name**, so
    minor row shifts are fine. The old flat layout (header `Project` in A1, data
    A–L from row 2) still imports too — archived files keep working.
  - Change a label or a column header in `build_template.py` → update the
    matching reader in `Import-Intake.ps1` (they're commented to stay in sync).
- **First run after a template change:** drop one filled file and check
  `import-log.txt` / the dashboard to confirm the rows land where expected.

## Troubleshooting
- Check **`import-log.txt`** in the dashboard folder — it logs each run:
  files found, rows imported, skips, and any errors.
- "Master is open/locked … will retry" in the log just means the workbook was
  open; close it and it imports next cycle.
- Nothing happening? Confirm the `Intake Inbox` folder is fully synced down to
  the PC (OneDrive green check) and that the file is a `.xlsx` (not still
  uploading / `.tmp`).
