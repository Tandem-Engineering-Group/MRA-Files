/* =============================================================================
 *  MRA Sync — PROJECT TASKS write-back  (Office Script add-on)
 * =============================================================================
 *  The dashboard's "✎ Edit Project Tasks" editor sends these actions through the
 *  SAME Power Automate flow / Run-script step you already use for the floor board:
 *
 *      addProjectTask · editProjectTask · deleteProjectTask
 *      closeProjectTask · reopenProjectTask
 *
 *  Because the flow runs ONE Office Script, paste this into your existing
 *  "MRA Sync" script (don't make a second script). Two steps:
 *
 *  STEP 1 — dispatch.  In main(), right AFTER you have the parsed `payload`
 *  object and AFTER your existing PIN / auth check, add:
 *
 *      if (["addProjectTask","editProjectTask","deleteProjectTask",
 *           "closeProjectTask","reopenProjectTask"].indexOf(payload.action) >= 0) {
 *        return mraHandleProjectTask(workbook, payload);
 *      }
 *
 *  STEP 2 — paste the whole `mraHandleProjectTask` function (below) at the very
 *  bottom of the script. Helper names are prefixed `mra…` so they won't collide
 *  with anything already in your script.
 *
 *  Project Tasks columns (0-based):
 *    A0 Project · B1 Phase · C2 Type · D3 Task · E4 Start · F5 Finish · G6 Duration
 *    H7 Assigned · I8 Status · J9 PM · K10 Milestone · L11 Comments · M12 Task ID · N13 Predecessor
 *
 *  Matching for edit/complete/reopen/delete = Project (A) + Task ID (M), with a
 *  fallback to Project (A) + Task text (D) for any legacy row whose ID is blank.
 *  (After one export every row has an ID, so the ID path is the normal one.)
 * ============================================================================= */

function mraProjSerialFromISO(iso: string): number | null {
  if (!iso) return null;
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
  if (!m) return null;
  // Excel serial = days since 1899-12-30 (date-only, no timezone drift)
  return Math.round((Date.UTC(+m[1], +m[2] - 1, +m[3]) - Date.UTC(1899, 11, 30)) / 86400000);
}

function mraProjTodaySerialEastern(): number {
  const est = new Date(new Date().toLocaleString("en-US", { timeZone: "America/New_York" }));
  return Math.round((Date.UTC(est.getFullYear(), est.getMonth(), est.getDate()) - Date.UTC(1899, 11, 30)) / 86400000);
}

function mraHandleProjectTask(workbook: ExcelScript.Workbook, payload: { [k: string]: string }): string {
  const ws = workbook.getWorksheet("Project Tasks");
  if (!ws) { return "Project Tasks sheet not found"; }

  // column indexes (A..N)
  const PROJECT = 0, PHASE = 1, TYPE = 2, TASK = 3, START = 4, FINISH = 5, DUR = 6,
        ASSIGNED = 7, STATUS = 8, PM = 9, MILESTONE = 10, COMMENTS = 11, ID = 12, PRED = 13;

  const used = ws.getUsedRange();
  const vals = used.getValues();          // row 0 = header
  const baseRow = used.getRowIndex();     // absolute row index of the header (normally 0)

  const action = payload.action;
  const proj = (payload.project || "").trim();
  const wantId = (payload.id != null ? ("" + payload.id) : "").trim();
  const wantTask = (payload.taskOld || payload.task || "").trim();

  const cellStr = (r: number, c: number): string => ("" + (vals[r][c] == null ? "" : vals[r][c])).trim();
  const setVal = (rowAbs: number, c: number, v: string | number): void => { ws.getCell(rowAbs, c).setValue(v); };
  const setDate = (rowAbs: number, c: number, iso: string): void => {
    const s = mraProjSerialFromISO(iso);
    const cell = ws.getCell(rowAbs, c);
    if (s == null) { cell.setValue(""); }
    else { cell.setValue(s); cell.setNumberFormat([["m/d/yyyy"]]); }
  };

  // ----- ADD -----
  if (action === "addProjectTask") {
    let maxId = 0;
    for (let r = 1; r < vals.length; r++) {
      const n = parseInt(cellStr(r, ID), 10);
      if (!isNaN(n) && n > maxId) { maxId = n; }
    }
    const newId = maxId + 1;
    const rowAbs = baseRow + vals.length;     // first empty row under the used range
    setVal(rowAbs, PROJECT, proj);
    setVal(rowAbs, PHASE, payload.phase || "");
    setVal(rowAbs, TYPE, payload.type || "");
    setVal(rowAbs, TASK, payload.task || "");
    setDate(rowAbs, START, payload.start || "");
    setDate(rowAbs, FINISH, payload.finish || "");
    setVal(rowAbs, DUR, payload.dur || "");
    setVal(rowAbs, ASSIGNED, payload.assigned || "");
    setVal(rowAbs, STATUS, payload.status || "Not Started");
    setVal(rowAbs, PM, payload.pm || "");
    setVal(rowAbs, MILESTONE, payload.milestone || "No");
    setVal(rowAbs, COMMENTS, payload.comments || "");
    setVal(rowAbs, ID, newId);
    setVal(rowAbs, PRED, payload.pred || "");
    return "added project task id=" + newId;
  }

  // ----- locate the row for edit / complete / reopen / delete -----
  let r = -1;
  if (wantId) {
    for (let i = 1; i < vals.length; i++) {
      if (cellStr(i, PROJECT) === proj && cellStr(i, ID) === wantId) { r = i; break; }
    }
  }
  if (r < 0 && wantTask) {
    for (let i = 1; i < vals.length; i++) {
      if (cellStr(i, PROJECT) === proj && cellStr(i, TASK) === wantTask) { r = i; break; }
    }
  }
  if (r < 0) { return "row not found: " + proj + " / " + (wantId || wantTask); }
  const rowAbs = baseRow + r;

  if (action === "deleteProjectTask") {
    ws.getCell(rowAbs, 0).getEntireRow().delete(ExcelScript.DeleteShiftDirection.up);
    return "deleted";
  }

  if (action === "closeProjectTask") {
    setVal(rowAbs, STATUS, "Completed");
    if (cellStr(r, FINISH) === "") { const s = mraProjTodaySerialEastern(); const c = ws.getCell(rowAbs, FINISH); c.setValue(s); c.setNumberFormat([["m/d/yyyy"]]); }
    return "completed";
  }

  if (action === "reopenProjectTask") {
    setVal(rowAbs, STATUS, payload.status || "In Progress");
    return "reopened";
  }

  if (action === "editProjectTask") {
    setVal(rowAbs, TASK, payload.task || "");
    setVal(rowAbs, PHASE, payload.phase || "");
    setVal(rowAbs, TYPE, payload.type || "");
    setVal(rowAbs, ASSIGNED, payload.assigned || "");
    setVal(rowAbs, STATUS, payload.status || "");
    setVal(rowAbs, MILESTONE, payload.milestone || "No");
    setVal(rowAbs, COMMENTS, payload.comments || "");
    setVal(rowAbs, PRED, payload.pred || "");
    setDate(rowAbs, START, payload.start || "");
    setDate(rowAbs, FINISH, payload.finish || "");
    return "edited";
  }

  return "unknown project action: " + action;
}
