#!/usr/bin/env python3
"""
build_from_lists.py   (STEP 3 - read path: build data.js from the SharePoint Lists)

Reads lists.json (produced by the "MRA Lists to JSON" Power Automate flow, which
dumps the 4 Lists + Holidays straight from SharePoint) and writes the dashboard's
data.js - WITHOUT going near the Excel workbook.

The Lists were created via "From Excel", so their columns carry SharePoint's raw
auto-names (field_1, field_2, ...). The FIELD MAPS below were derived by matching
List rows back to the live data.js (same workbook source). Empty cells are omitted
per-row by SharePoint, so every read is tolerant of a missing field.

Fleet (Fleetio/Samsara), the logistics "Coming Back to MRA" calendars, mraStatus
and physicalBays were never in Excel either - they are PASSED THROUGH unchanged
from an existing data.js (default ./data.js), so a diff focuses only on the
List-sourced sections (jobs / projects / teamTasks / users / holidays).

RUN (validation - writes a CANDIDATE, does NOT touch the live data.js):
    python3 build_from_lists.py --lists lists.json --base data.js --out data.fromlists.js

CUTOVER (in the Action, once verified): --out data.js  then push as today.
"""
import argparse, json, re, sys
from datetime import datetime, timezone

PHYSICAL_BAYS_DEFAULT = [
    'Bay 2 Front','Bay 2 Back / Loading Dock','Bay 3 Front','Bay 3 Back',
    'Bay 4 Front','Bay 4 Back','Bay 5 Front','Bay 5 Back',
    'Parking Lot','On Hold/Off-Site']

# ---- field maps (List field_N -> meaning), derived empirically ---------------
# jobs:   Title=Project
J_BAY,J_CLIENT,J_JOBNUM   = 'field_1','field_2','field_3'
J_START,J_SHIP,J_STATUS   = 'field_4','field_5','field_6'
J_PM,J_NOTES,J_CATEGORY   = 'field_7','field_8','field_9'
# shopTasks: Title=Task
S_PROJECT,S_ASSIGNED      = 'field_1','field_4'
S_STATUS,S_OPENED,S_CLOSED= 'field_5','field_6','field_7'
S_COMMENTS                = 'field_9'
# projectTasks: Title=Task
P_PROJECT,P_TASKID,P_PHASE,P_TYPE = 'field_1','field_2','field_3','field_4'
P_ASSIGNED,P_START,P_FINISH,P_DUR = 'field_5','field_6','field_7','field_8'
P_STATUS,P_PM,P_MILE,P_COMMENTS   = 'field_9','field_10','field_11','field_12'
P_PRED,P_SUB                      = 'field_13','field_14'
# users: Title=Name
U_CODE,U_ROLE,U_ACTIVE    = 'field_1','field_2','field_3'
# holidays: Title=Name
H_DATE,H_COUNTRY          = 'field_1','field_2'


def ff(row, *keys):
    """First non-empty field value as a trimmed string ('' if none present)."""
    for k in keys:
        if k in row and row[k] is not None:
            v = str(row[k]).strip()
            if v != '':
                return v
    return ''

def is_yes(v):
    return str(v).strip().lower() in ('yes','y','true','1')

def as_num(v):
    try:
        return float(str(v).strip())
    except (TypeError, ValueError):
        return None

def num_str(v):
    d = as_num(v)
    if d is None:
        return ''
    return str(int(d)) if d == int(d) else str(d)

def code_norm(v):
    """Excel stored codes as numbers, so they arrive like '1974.0' - strip the .0."""
    s = str(v).strip()
    if re.fullmatch(r'\d+\.0', s):
        s = s[:-2]
    return s

def pin_hash(s):
    """Mirror the dashboard's pinHash: h=(h*31+charCode)>>>0 per char."""
    h = 0
    for ch in str(s):
        h = (h * 31 + ord(ch)) & 0xFFFFFFFF
    return h

def norm_gen(s):
    """Mirror Export-Data NormGen: drop non-word/space, trim, lowercase."""
    return re.sub(r'[^\w ]', '', str(s)).strip().lower()

def iso_to_mdyy(iso):
    if re.fullmatch(r'\d{4}-\d{2}-\d{2}', iso or ''):
        y, m, d = iso.split('-')
        return f"{int(m)}/{int(d)}/{y[2:]}"
    return ''

def iso_or_none(v):
    return v if re.fullmatch(r'\d{4}-\d{2}-\d{2}', v or '') else None


def build_tasks_from_rows(rows):
    """Mirror Build-TasksFromRows in Export-Data.ps1 (same on-screen shape)."""
    open_, done = [], []
    tasks = []
    done_count = sal_open = n = 0
    for r in rows:
        who = r['who']
        label = f"{who} - {r['task']}" if who else r['task']
        if r['done']:
            done_count += 1
            cdisp = ''
            if r['cl']:
                p = str(r['cl']).split('-')
                if len(p) == 3:
                    cdisp = f"  (closed {int(p[1])}/{int(p[2])}/{p[0][2:]})"
            done.append(label + cdisp)
        else:
            n += 1
            open_.append(f"{n}. {label}")
            if re.search(r'(?i)\bsal\b', label):
                sal_open += 1
        tasks.append({'t': r['task'], 'who': who, 'op': r['op'], 'cl': r['cl'],
                      'st': r['st'], 'done': r['done'], 'ml': r['ml'], 'cm': r['cm'],
                      '_id': r['_id']})
    return {'open': open_, 'openCount': len(open_), 'doneCount': done_count,
            'salOpen': sal_open, 'done': done, 'tasks': tasks}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--lists', default='lists.json')
    ap.add_argument('--base',  default='data.js')
    ap.add_argument('--out',   default='data.fromlists.js')
    args = ap.parse_args()

    with open(args.lists, encoding='utf-8') as fh:
        L = json.load(fh)
    jobs_in    = L.get('jobs', []) or []
    shop_in    = L.get('shopTasks', []) or []
    proj_in    = L.get('projectTasks', []) or []
    users_in   = L.get('users', []) or []
    hol_in     = L.get('holidays', []) or []

    # --- Shop Tasks grouped by project (normalized) --------------------------
    shop_by_proj = {}
    for it in shop_in:
        task = ff(it, 'Title')
        if not task:
            continue
        st = ff(it, S_STATUS)
        op = ff(it, S_OPENED)
        cl = ff(it, S_CLOSED)
        rec = {'task': task, '_id': it.get('ID') or it.get('id'),
               'who': ff(it, S_ASSIGNED), 'st': st, 'ml': '',
               'cm': ff(it, S_COMMENTS),
               'op': op or None, 'cl': cl or None}
        rec['done'] = bool(re.search(r'(?i)done|complete', rec['st']) or rec['cl'])
        key = norm_gen(ff(it, S_PROJECT))
        shop_by_proj.setdefault(key, []).append(rec)

    # --- Jobs ----------------------------------------------------------------
    jobs, gen_job, used = [], None, set()
    for it in jobs_in:
        proj = ff(it, 'Title')
        if not proj:
            continue
        bay      = ff(it, J_BAY)
        client   = ff(it, J_CLIENT)
        job      = ff(it, J_JOBNUM)
        status   = ff(it, J_STATUS)
        pm       = ff(it, J_PM)
        notes    = ff(it, J_NOTES)
        start_iso= ff(it, J_START)
        comp_iso = ff(it, J_SHIP)
        nkey = norm_gen(proj)
        st_rows = shop_by_proj.get(nkey)
        if st_rows:
            used.add(nkey)
        t = build_tasks_from_rows(st_rows) if st_rows else \
            {'open': [], 'openCount': 0, 'doneCount': 0, 'salOpen': 0, 'done': [], 'tasks': []}

        is_general = (nkey == 'general')
        if is_general:
            category = 'general'
        elif status == 'Leave' or bay == 'APL/Holidays':
            category = 'leave'
        elif bay not in PHYSICAL_BAYS_DEFAULT:
            category = 'pipeline'
        else:
            category = 'bay'

        rec = {
            'row': 'general' if is_general else (int(it.get('ID')) if str(it.get('ID','')).isdigit() else it.get('ID')),
            '_id': it.get('ID') or it.get('id'),
            'bay': bay, 'project': proj, 'client': client, 'jobNum': job,
            'status': status, 'pm': pm,
            'startISO': start_iso or None, 'completionISO': comp_iso or None,
            'startText': iso_to_mdyy(start_iso), 'completionText': iso_to_mdyy(comp_iso),
            'category': category, 'notesRaw': notes,
            'openTasks': t['open'], 'openCount': t['openCount'], 'doneCount': t['doneCount'],
            'salOpen': t['salOpen'], 'doneTasks': t['done'], 'tasks': t['tasks'],
        }
        if is_general:
            gen_job = rec
        else:
            jobs.append(rec)

    if gen_job is None and 'general' in shop_by_proj:
        gt = build_tasks_from_rows(shop_by_proj['general'])
        gen_job = {'row': 'general', 'bay': 'General', 'project': '\U0001F6E0 General',
                   'client': '', 'jobNum': '', 'status': '', 'pm': '',
                   'startISO': None, 'completionISO': None, 'startText': '', 'completionText': '',
                   'category': 'general', 'notesRaw': '',
                   'openTasks': gt['open'], 'openCount': gt['openCount'], 'doneCount': gt['doneCount'],
                   'salOpen': gt['salOpen'], 'doneTasks': gt['done'], 'tasks': gt['tasks']}

    jobs.sort(key=lambda j: j['row'] if isinstance(j['row'], int) else 999999)
    jobs_out = list(jobs)
    if gen_job:
        jobs_out.append(gen_job)

    # --- Project Tasks -> projects + teamTasks -------------------------------
    pmap = {}
    team_tasks = []
    for it in proj_in:
        name = ff(it, P_PROJECT)
        if not name:
            continue
        p_task   = ff(it, 'Title')
        p_phase  = ff(it, P_PHASE)
        p_type   = ff(it, P_TYPE)
        p_status = ff(it, P_STATUS) or 'Not Started'   # mirror Export-Data: blank → Not Started
        p_pm     = ff(it, P_PM)
        p_assign = ff(it, P_ASSIGNED)
        p_cm     = ff(it, P_COMMENTS)
        p_dur    = ff(it, P_DUR)
        p_taskid = num_str(ff(it, P_TASKID))
        p_pred   = ff(it, P_PRED)
        s_iso    = iso_or_none(ff(it, P_START))
        f_iso    = iso_or_none(ff(it, P_FINISH))
        p_mile   = 'Yes' if is_yes(ff(it, P_MILE)) else 'No'   # mirror Export-Data: non-milestone → No
        p_sub    = is_yes(ff(it, P_SUB))

        o = pmap.get(name)
        if o is None:
            o = {'name': name, 'pm': '', 'minStart': None, 'maxFinish': None,
                 'taskCount': 0, 'doneCount': 0, 'pctSum': 0,
                 'milestones': [], 'tasks': []}
            pmap[name] = o
        o['taskCount'] += 1
        if p_status == 'Completed':
            o['doneCount'] += 1
        tp = 0
        if p_status == 'Completed':
            tp = 100
        else:
            m = re.search(r'(\d{1,3})\s*%', p_status)
            if m:
                tp = max(0, min(100, int(m.group(1))))
        o['pctSum'] += tp
        if p_pm and not o['pm']:
            o['pm'] = p_pm
        if s_iso and (o['minStart'] is None or s_iso < o['minStart']):
            o['minStart'] = s_iso
        if f_iso and (o['maxFinish'] is None or f_iso > o['maxFinish']):
            o['maxFinish'] = f_iso
        if p_mile == 'Yes':
            md = f_iso or s_iso
            if md:
                o['milestones'].append({'name': p_task, 'dateISO': md, 'owner': p_assign,
                                        'status': p_status, 'phase': p_phase,
                                        'done': p_status == 'Completed'})
        if p_assign and p_status != 'Completed':
            o['tasks']  # noqa
            team_tasks.append({'assignee': p_assign, 'project': name, 'task': p_task,
                               'dueISO': f_iso or s_iso, 'status': p_status})
        o['tasks'].append({'id': p_taskid, '_id': it.get('ID') or it.get('id'), 't': p_task,
                           'phase': p_phase, 'type': p_type, 'who': p_assign,
                           'startISO': s_iso, 'finISO': f_iso, 'dur': p_dur, 'st': p_status,
                           'ml': p_mile, 'cm': p_cm, 'pred': p_pred, 'sub': p_sub,
                           'done': p_status == 'Completed'})

    projects = []
    for o in pmap.values():
        pct = round(o['pctSum'] / o['taskCount']) if o['taskCount'] else 0
        projects.append({'name': o['name'], 'pm': o['pm'],
                         'startISO': o['minStart'], 'finishISO': o['maxFinish'],
                         'taskCount': o['taskCount'], 'doneCount': o['doneCount'], 'pct': pct,
                         'milestones': o['milestones'], 'tasks': o['tasks']})

    # --- Users (hash the plaintext code; skip inactive/blank) ----------------
    users = []
    for it in users_in:
        name = ff(it, 'Title')
        code = code_norm(ff(it, U_CODE))
        if not name or not code:
            continue
        if (U_ACTIVE in it) and not is_yes(it[U_ACTIVE]):
            continue
        users.append({'name': name, 'h': pin_hash(code)})

    # --- Holidays ------------------------------------------------------------
    holidays = []
    for it in hol_in:
        name = ff(it, 'Title')
        d    = ff(it, H_DATE)
        ctry = ff(it, H_COUNTRY).upper()
        if not name or not re.fullmatch(r'\d{4}-\d{2}-\d{2}', d):
            continue
        if ctry not in ('US', 'CA', 'BOTH'):
            ctry = 'US'
        holidays.append({'name': name, 'dateISO': d, 'country': ctry})

    # --- inherit fleet + logistics + physicalBays from the existing data.js ---
    fleetio, mra_status, phys = None, [], PHYSICAL_BAYS_DEFAULT
    try:
        raw = open(args.base, encoding='utf-8').read()
        base = json.loads(raw[raw.index('{'):raw.rindex('}') + 1])
        fleetio    = base.get('fleetio')
        mra_status = base.get('mraStatus', []) or []
        phys       = base.get('physicalBays') or PHYSICAL_BAYS_DEFAULT
    except Exception as e:
        print(f"  (couldn't inherit fleet/logistics from {args.base}: {e})", file=sys.stderr)

    now = datetime.now()
    payload = {
        'generatedAt':   datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        'generatedText': now.strftime('%a %b %-d, %Y  %-I:%M %p'),
        'todayISO':      now.strftime('%Y-%m-%d'),
        'physicalBays':  phys,
        'jobs':          jobs_out,
        'projects':      projects,
        'teamTasks':     team_tasks,
        'fleetio':       fleetio,
        'mraStatus':     mra_status,
        'users':         users,
        'holidays':      holidays,
        'source':        'lists',
    }
    js = json.dumps(payload, ensure_ascii=False, separators=(',', ':'))
    out = "// Auto-generated by build_from_lists.py - do not edit by hand\nwindow.MRA_DATA = " + js + ";\n"
    with open(args.out, 'w', encoding='utf-8') as fh:
        fh.write(out)

    orphans = [k for k in shop_by_proj if k not in used and k != 'general']
    print(f"Wrote {args.out} from Lists:")
    print(f"  jobs={len(jobs_out)}  projects={len(projects)}  teamTasks={len(team_tasks)}"
          f"  users={len(users)}  holidays={len(holidays)}")
    if orphans:
        print(f"  NOTE: shop tasks for {len(orphans)} project(s) matched no job: {', '.join(orphans)}")


if __name__ == '__main__':
    main()
