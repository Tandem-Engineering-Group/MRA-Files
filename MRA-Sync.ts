function main(workbook: ExcelScript.Workbook, payload: string) {
    let p: {
        action?: string;
        project?: string; task?: string; taskOld?: string; closedDate?: string;
        jobNum?: string; bay?: string; assigned?: string; milestone?: string; comments?: string;
        client?: string; pm?: string;
        row?: number; status?: string; start?: string; completion?: string; notes?: string;
        id?: string | number; phase?: string; type?: string; finish?: string; pred?: string;
        pin?: string; user?: string;
        // bulk upload of a whole project (action "importProject")
        replace?: boolean;
        tasks?: {
            task?: string; phase?: string; type?: string; start?: string; finish?: string;
            duration?: string; assigned?: string; status?: string; milestone?: string;
            comments?: string; predecessor?: string;
        }[];
    } = {};
    try { p = JSON.parse(payload); } catch (e) { console.log("Bad payload"); return; }

    // ---- who is this? resolve the code against the Users sheet (plaintext compare) ----
    const code = String(p.pin || "").trim();
    const who = ((): string | null => {
        const ws = workbook.getWorksheet("Users");
        if (ws) {
            const used = ws.getUsedRange();
            if (used) {
                const v = used.getValues(); let hasData = false;
                for (let i = 1; i < v.length; i++) {
                    const name = String(v[i][0] || "").trim(), c = String(v[i][1] || "").trim(), act = String(v[i][2] || "").trim();
                    if (!name || !c) continue;
                    hasData = true;
                    if (/^(no|n|inactive|0|false)$/i.test(act)) continue;
                    if (c === code) return name;
                }
                if (hasData) return null;   // Users list exists -> only listed, active codes allowed
            }
        }
        return code === "1974" ? "Shop" : null;   // legacy fallback until Users sheet has people
    })();
    if (who === null) { console.log("Unauthorized code — ignored."); return; }

    const serialOf = (iso: string): number | "" => {
        const m = (iso || "").split("-");
        if (m.length !== 3) return "";
        return Math.floor((Date.UTC(+m[0], +m[1] - 1, +m[2]) - Date.UTC(1899, 11, 30)) / 86400000);
    };
    const easternParts = () => new Intl.DateTimeFormat('en-US', {
        timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: true
    }).formatToParts(new Date());
    const todaySerial = (): number => {
        const pa = easternParts(); const g = (k: string) => { const x = pa.find(z => z.type === k); return x ? +x.value : 0; };
        return Math.floor((Date.UTC(g('year'), g('month') - 1, g('day')) - Date.UTC(1899, 11, 30)) / 86400000);
    };
    const logIt = (action: string, project: string, detail: string) => {
        try {
            const t = workbook.getTable("ActivityLog"); if (!t) return;
            const pa = easternParts(); const g = (k: string) => { const x = pa.find(z => z.type === k); return x ? x.value : ''; };
            const when = g('month') + '/' + g('day') + '/' + g('year') + ' ' + g('hour') + ':' + g('minute') + ' ' + g('dayPeriod');
            t.addRow(-1, [when, who, action, project || "", detail || ""]);
        } catch (e) { }
    };
    const table = workbook.getTable("ShopTasks");
    const findRow = (vals: (string | number | boolean)[][], project: string, task: string): number => {
        const pr = (project || "").trim().toLowerCase(), tk = (task || "").trim().toLowerCase();
        for (let i = 0; i < vals.length; i++)
            if (String(vals[i][0]).trim().toLowerCase() === pr && String(vals[i][3]).trim().toLowerCase() === tk) return i;
        return -1;
    };

    if (p.action === "addTask") {
        if (!table || !p.project || !p.task) { console.log("Missing"); return; }
        table.addRow(-1, [p.project, p.jobNum || "", p.bay || "", p.task, p.assigned || "", todaySerial(), "", "Open", p.milestone || "", p.comments || ""]);
        table.getRangeBetweenHeaderAndTotal().getLastRow().getCell(0, 5).setNumberFormatLocal([["m/d/yyyy"]]);
        logIt("Add task", p.project, p.task); return;
    }
    if (p.action === "addJob") {
        const jobs = workbook.getTable("Jobs");
        if (!jobs || !p.project) { console.log("Missing"); return; }
        jobs.addRow(-1, [p.bay || "", p.project, p.client || "", p.jobNum || "", serialOf(p.start || ""), serialOf(p.completion || ""), p.status || "TBD", p.notes || "", "", "", p.pm || ""]);
        const last = jobs.getRangeBetweenHeaderAndTotal().getLastRow();
        if (p.start) last.getCell(0, 4).setNumberFormatLocal([["m/d/yyyy"]]);
        if (p.completion) last.getCell(0, 5).setNumberFormatLocal([["m/d/yyyy"]]);
        logIt("Add job", p.project, (p.bay || "") + (p.jobNum ? " · " + p.jobNum : "")); return;
    }
    if (p.action === "editTask") {
        if (!table || !p.project || !p.taskOld) { console.log("Missing"); return; }
        const body = table.getRangeBetweenHeaderAndTotal(); const vals = body.getValues();
        const i = findRow(vals, p.project, p.taskOld);
        if (i < 0) { console.log("No match"); return; }
        if (p.task !== undefined) body.getCell(i, 3).setValue(p.task);
        if (p.assigned !== undefined) body.getCell(i, 4).setValue(p.assigned);
        if (p.milestone !== undefined) body.getCell(i, 8).setValue(p.milestone);
        if (p.comments !== undefined) body.getCell(i, 9).setValue(p.comments);
        if (p.status) {
            body.getCell(i, 7).setValue(p.status);
            const gc = body.getCell(i, 6); const done = /done|complete/i.test(p.status);
            if (done && String(vals[i][6]).trim() === "") { gc.setValue(todaySerial()); gc.setNumberFormatLocal([["m/d/yyyy"]]); }
            if (!done) gc.clear(ExcelScript.ClearApplyTo.Contents);
        }
        logIt("Edit task", p.project, p.task || p.taskOld); return;
    }
    if (p.action === "deleteTask") {
        if (!table || !p.project || !p.task) { console.log("Missing"); return; }
        const body = table.getRangeBetweenHeaderAndTotal(); const i = findRow(body.getValues(), p.project, p.task);
        if (i < 0) { console.log("No match"); return; }
        body.getRow(i).getEntireRow().delete(ExcelScript.DeleteShiftDirection.Up);
        logIt("Delete task", p.project, p.task); return;
    }
    if (p.action === "reopenTask") {
        if (!table || !p.project || !p.task) { console.log("Missing"); return; }
        const body = table.getRangeBetweenHeaderAndTotal(); const i = findRow(body.getValues(), p.project, p.task);
        if (i < 0) { console.log("No match"); return; }
        body.getCell(i, 7).setValue("Open"); body.getCell(i, 6).clear(ExcelScript.ClearApplyTo.Contents);
        logIt("Reopen task", p.project, p.task); return;
    }
    if (p.action === "editJob") {
        const r = Number(p.row); if (!r || r < 4) { console.log("Bad row"); return; }
        const ws = workbook.getWorksheet("Input");
        if (p.project !== undefined && String(ws.getRange("B" + r).getValue()).trim().toLowerCase() !== (p.project || "").trim().toLowerCase()) { console.log("Stale row"); return; }
        if (p.bay) ws.getRange("A" + r).setValue(p.bay);
        if (p.status) ws.getRange("G" + r).setValue(p.status);
        if (p.notes !== undefined) ws.getRange("H" + r).setValue(p.notes);
        const setDate = (col: string, iso: string) => { const cell = ws.getRange(col + r), s = serialOf(iso || ""); if (s === "") cell.clear(ExcelScript.ClearApplyTo.Contents); else { cell.setValue(s); cell.setNumberFormatLocal([["m/d/yyyy"]]); } };
        if (p.start !== undefined) setDate("E", p.start);
        if (p.completion !== undefined) setDate("F", p.completion);
        logIt("Edit job", p.project || "", "row " + r); return;
    }
    if (p.action === "deleteJob") {
        const r = Number(p.row); if (!r || r < 4) { console.log("Bad row"); return; }
        const ws = workbook.getWorksheet("Input");
        if (p.project !== undefined && String(ws.getRange("B" + r).getValue()).trim().toLowerCase() !== (p.project || "").trim().toLowerCase()) { console.log("Stale row"); return; }
        ws.getRange("A" + r).getEntireRow().delete(ExcelScript.DeleteShiftDirection.Up);
        logIt("Delete job", p.project || "", "row " + r); return;
    }

    // ===== PROJECT TASKS (the long-term "Project Tasks" sheet: cols A..N) =====
    if (p.action === "addProjectTask" || p.action === "editProjectTask" || p.action === "deleteProjectTask"
        || p.action === "closeProjectTask" || p.action === "reopenProjectTask") {
        const pws = workbook.getWorksheet("Project Tasks");
        if (!pws) { console.log("No Project Tasks sheet"); return; }
        const used = pws.getUsedRange(); const vals = used.getValues();
        const base = used.getRowIndex(), cnt = used.getRowCount();
        const PROJECT = 0, PHASE = 1, TYPE = 2, TASK = 3, START = 4, FINISH = 5,
            ASSIGNED = 7, STATUS = 8, MILE = 10, COMMENTS = 11, ID = 12, PRED = 13;
        const pr = String(p.project || "").trim().toLowerCase();
        const mileVal = (m: string | undefined) => (m === "Yes" ? "Yes" : "No");
        const setPDate = (rowAbs: number, col: number, iso: string) => {
            const cell = pws.getCell(rowAbs, col), s = serialOf(iso || "");
            if (s === "") cell.clear(ExcelScript.ClearApplyTo.Contents);
            else { cell.setValue(s); cell.setNumberFormatLocal([["m/d/yyyy"]]); }
        };

        if (p.action === "addProjectTask") {
            if (!p.project || !p.task) { console.log("Missing"); return; }
            let maxId = 0;
            for (let i = 1; i < vals.length; i++) { const n = parseInt(String(vals[i][ID]).trim(), 10); if (!isNaN(n) && n > maxId) maxId = n; }
            const newId = maxId + 1, r = base + cnt;
            pws.getCell(r, PROJECT).setValue(p.project);
            pws.getCell(r, PHASE).setValue(p.phase || "");
            pws.getCell(r, TYPE).setValue(p.type || "");
            pws.getCell(r, TASK).setValue(p.task);
            setPDate(r, START, p.start || "");
            setPDate(r, FINISH, p.finish || "");
            pws.getCell(r, ASSIGNED).setValue(p.assigned || "");
            pws.getCell(r, STATUS).setValue(p.status || "Not Started");
            pws.getCell(r, MILE).setValue(mileVal(p.milestone));
            pws.getCell(r, COMMENTS).setValue(p.comments || "");
            pws.getCell(r, ID).setValue(newId);
            pws.getCell(r, PRED).setValue(p.pred || "");
            logIt("Add project task", p.project, String(p.task) + " (#" + newId + ")"); return;
        }

        // locate the row for edit / complete / reopen / delete — by Task ID, else by task text
        const wantId = String(p.id != null ? p.id : "").trim();
        const wantTask = String(p.taskOld || p.task || "").trim().toLowerCase();
        let idx = -1;
        if (wantId) for (let i = 1; i < vals.length; i++) if (String(vals[i][PROJECT]).trim().toLowerCase() === pr && String(vals[i][ID]).trim() === wantId) { idx = i; break; }
        if (idx < 0 && wantTask) for (let i = 1; i < vals.length; i++) if (String(vals[i][PROJECT]).trim().toLowerCase() === pr && String(vals[i][TASK]).trim().toLowerCase() === wantTask) { idx = i; break; }
        if (idx < 0) { console.log("No matching project task"); return; }
        const rowAbs = base + idx;

        if (p.action === "deleteProjectTask") {
            pws.getCell(rowAbs, 0).getEntireRow().delete(ExcelScript.DeleteShiftDirection.Up);
            logIt("Delete project task", p.project || "", String(p.task || wantId)); return;
        }
        if (p.action === "closeProjectTask") {
            pws.getCell(rowAbs, STATUS).setValue("Completed");
            if (String(vals[idx][FINISH]).trim() === "") { const c = pws.getCell(rowAbs, FINISH); c.setValue(todaySerial()); c.setNumberFormatLocal([["m/d/yyyy"]]); }
            logIt("Complete project task", p.project || "", String(p.task || wantId)); return;
        }
        if (p.action === "reopenProjectTask") {
            pws.getCell(rowAbs, STATUS).setValue(p.status || "In Progress");
            logIt("Reopen project task", p.project || "", String(p.task || wantId)); return;
        }
        if (p.action === "editProjectTask") {
            if (p.task !== undefined) pws.getCell(rowAbs, TASK).setValue(p.task);
            if (p.phase !== undefined) pws.getCell(rowAbs, PHASE).setValue(p.phase);
            if (p.type !== undefined) pws.getCell(rowAbs, TYPE).setValue(p.type);
            if (p.assigned !== undefined) pws.getCell(rowAbs, ASSIGNED).setValue(p.assigned);
            if (p.status !== undefined && p.status !== "") pws.getCell(rowAbs, STATUS).setValue(p.status);
            if (p.milestone !== undefined) pws.getCell(rowAbs, MILE).setValue(mileVal(p.milestone));
            if (p.comments !== undefined) pws.getCell(rowAbs, COMMENTS).setValue(p.comments);
            if (p.pred !== undefined) pws.getCell(rowAbs, PRED).setValue(p.pred);
            if (p.start !== undefined) setPDate(rowAbs, START, p.start);
            if (p.finish !== undefined) setPDate(rowAbs, FINISH, p.finish);
            logIt("Edit project task", p.project || "", String(p.task || wantId)); return;
        }
        return;
    }

    // ===== BULK IMPORT a whole project from the dashboard Upload tab =====
    // Appends the uploaded tasks. If replace=true (project name matched an existing
    // one), the old rows are CLEARED IN PLACE (contents only) rather than deleted, so
    // the Project Gantt's absolute-row mirror formulas are never shifted/broken.
    if (p.action === "importProject") {
        const pws = workbook.getWorksheet("Project Tasks");
        if (!pws || !p.project || !p.tasks || !p.tasks.length) { console.log("Missing import data"); return; }
        const used = pws.getUsedRange(); const vals = used.getValues();
        const base = used.getRowIndex(), cnt = used.getRowCount();
        const PROJECT = 0, PHASE = 1, TYPE = 2, TASK = 3, START = 4, FINISH = 5, DURATION = 6,
            ASSIGNED = 7, STATUS = 8, PM = 9, MILE = 10, COMMENTS = 11, ID = 12, PRED = 13;
        const pr = String(p.project).trim().toLowerCase();
        let maxId = 0;
        for (let i = 1; i < vals.length; i++) { const n = parseInt(String(vals[i][ID]).trim(), 10); if (!isNaN(n) && n > maxId) maxId = n; }

        let cleared = 0;
        if (p.replace) {
            for (let i = 1; i < vals.length; i++) {
                if (String(vals[i][PROJECT]).trim().toLowerCase() === pr) {
                    pws.getRangeByIndexes(base + i, 0, 1, 14).clear(ExcelScript.ClearApplyTo.Contents);
                    cleared++;
                }
            }
        }

        const startRow = base + cnt;   // append safely below everything
        const block: (string | number)[][] = [];
        for (const t of p.tasks) {
            maxId++;
            const row: (string | number)[] = new Array(14).fill("");
            row[PROJECT] = p.project; row[PHASE] = t.phase || ""; row[TYPE] = t.type || ""; row[TASK] = t.task || "";
            row[START] = serialOf(t.start || ""); row[FINISH] = serialOf(t.finish || "");
            row[DURATION] = t.duration || ""; row[ASSIGNED] = t.assigned || ""; row[STATUS] = t.status || "Not Started";
            row[PM] = p.pm || ""; row[MILE] = (t.milestone === "Yes" ? "Yes" : "No"); row[COMMENTS] = t.comments || "";
            row[ID] = maxId; row[PRED] = t.predecessor || "";
            block.push(row);
        }
        pws.getRangeByIndexes(startRow, 0, block.length, 14).setValues(block);
        // date format on the new Start/Finish cells
        const fmt: string[][] = []; for (let i = 0; i < block.length; i++) fmt.push(["m/d/yyyy"]);
        pws.getRangeByIndexes(startRow, START, block.length, 1).setNumberFormatLocal(fmt);
        pws.getRangeByIndexes(startRow, FINISH, block.length, 1).setNumberFormatLocal(fmt);
        logIt("Import project", p.project, (p.replace ? ("replaced " + cleared + " row(s) → ") : "added ") + block.length + " task(s)");
        return;
    }

    // CLOSE (default)
    if (table && p.project && p.task) {
        const body = table.getRangeBetweenHeaderAndTotal(); const vals = body.getValues();
        const i = findRow(vals, p.project, p.task);
        if (i >= 0 && String(vals[i][7]).toLowerCase() !== "done") {
            body.getCell(i, 7).setValue("Done");
            const cl = body.getCell(i, 6); cl.setValue(todaySerial()); cl.setNumberFormatLocal([["m/d/yyyy"]]);
            logIt("Close task", p.project, p.task); return;
        }
        console.log("No matching open task"); return;
    }
    console.log("Nothing to do.");
}
