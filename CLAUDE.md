# CLAUDE.md — MRA Shop Floor Dashboard

Guidance for Claude when working in this repository.

## How Rich likes instructions (standing preference — follow every time)

- **Write the instructions IN THE CHAT, numbered step-by-step.** Do NOT put the steps
  in a committed file/doc and point him at it — he wants to read them right here. Spell
  out explicit numbered clicks/steps, not a high-level summary. He'll say so bluntly if
  it slips into summary mode or gets parked in a file.
- **Send files only when a step needs a downloadable file** (a template, script,
  spreadsheet, photo) — deliver it via the file-send tool so he can grab it directly.
  Files are for downloads, the chat is for the steps. (Don't tell him to "open the repo
  doc.")
- He's comfortable building Power Automate flows and clicking through SharePoint/M365
  with precise guidance, but he is **not** a developer — avoid raw PowerShell/CLI for
  him where a guided GUI or a flow will do, and anticipate the prompts he'll hit.

### Access / who-has-what (don't ask Rich to fetch these — he can't)
- **Azure** (the `mrashopdash` storage account, the `AZURE_STORAGE_KEY` / access keys,
  AzCopy + deploy creds) is owned by **Rich's PARTNER**, not Rich. Rich does **not**
  have the Azure Portal or the storage key. Anything needing the Azure storage key →
  the partner provides it (it's the same key the deploy already uses). Don't tell Rich
  to "grab key1 from the Azure Portal."
- **M365 admin** (Entra **app registrations**, SharePoint admin consent) → **IT**.
- So for a step needing a credential: route storage/Azure → partner, Entra/M365 admin →
  IT, and give Rich the exact ask to forward.

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

## 🎯 Eliminate-Excel roadmap (Rich's north star — "never go to the excel file for anything")

Rich's explicit goal: retire the workbook entirely. Track progress here; don't lose it.

- **✅ STEP 1 DONE (2026-06-20): board runs off-PC.** The export no longer needs Rich's PC.
  Pipeline: a Power Automate **"MRA workbook shuttle"** flow (every 15 min, his login) copies the
  workbook to a private Azure blob container **`pipeline`** AND POSTs a `repository_dispatch`
  (`event_type:"run-export"`) to GitHub; the **`.github/workflows/export.yml`** Action (on the
  DEFAULT branch `claude/exciting-keller-wm7u2p`) downloads the workbook, runs `Export-Data.ps1`
  (honors `MRA_WORKBOOK` env override), and pushes `data.js`. Tokens are GitHub repo secrets
  (`FLEETIO_API_KEY`, `FLEETIO_ACCOUNT_TOKEN`, `SAMSARA_TOKEN`, `AZURE_STORAGE_KEY`). The trigger
  is a fine-grained PAT (`Contents: write`, resource owner = the org) the shuttle sends via an HTTP
  step — the org had to allow fine-grained PATs first. **GitHub's `schedule` is a flaky backup
  (~hourly); the repository_dispatch from the shuttle is the reliable 15-min trigger.** See
  `CLOUD-EXPORT-SETUP.md`. ⚠️ The PAT expires (~1 yr) — remind Rich to rotate it.
- **🔜 STEP 2 — close the last edits that still force Excel:** (1) ✅ **move/copy a task to a
  different project/job DONE** (rev 4.83 project tasks, 4.84 shop tasks); (2) add subtasks in the
  editor *(still open)*; (3) ✅ **🗑 Delete a whole project in one click DONE** — `deleteProjectBtn()`
  → `deleteProject` action → script cascade-CLEARS (not delete-shift) the project's Project Tasks +
  matching floor job (Input) + Shop Tasks, protecting the Project Gantt's absolute-row mirror.
  *(2026-06-22: also fixed per-task `deleteProjectTask` to CLEAR instead of delete-shift, same mirror
  rule.)* (4) ✅ **move/reorder shop tasks between trailers DONE** (rev 4.84 move/copy); (5) manage
  login Users/codes from the dashboard *(setUser/deleteUser/renameUser actions exist + UI; verify
  live)*; (6) ✅ **logistics "arriving" calendars DONE** — `renderReturns` "Coming Back to MRA" panel
  wired onto FLOOR (rev 4.82, no longer orphaned).
  ✅ **Upload a whole new project via the "Upload Filled" tab = ALREADY WORKING** (confirmed
  2026-06-20: parses the filled template client-side → `importProject` action → lands on the board
  next cycle; same-name = replace, new name = add).
  ⚠️ **DELETE/EDIT ALL DEPEND ON THE LIVE OFFICE SCRIPT BEING CURRENT.** Every dashboard action
  (delete project/task/job/user/holiday, move/copy, importProject) is handled in `MRA-Sync.ts` AND
  the dashboard sends it — BUT it only works if the Office Script the Power Automate save-flow runs
  is the latest `MRA-Sync.ts`. If Rich pasted an older script, the newer buttons (deleteProject,
  importProject, move/copy) fire from the UI but silently no-op → he'd still go to Excel. Re-paste
  `MRA-Sync.ts` + Save when in doubt. (setEOTM is the one action NOT in this script — it has its own
  EOTM blob flow, by design.)
- **🏁 STEP 3 — kill the .xlsx:** move the data off the workbook entirely → **SharePoint Lists**
  (Jobs / ShopTasks / ProjectTasks / Users), so there's no Excel file to open. Platform handles
  concurrency (the write-collision class disappears).
  - **✅✅ CUTOVER DONE — LIVE ON LISTS 2026-06-25 (zero Excel).** The live board now READS + WRITES the
    SharePoint Lists. What shipped:
    - **Read:** `export.yml` (on the DEFAULT branch) still runs `Export-Data.ps1` so **Fleetio/Samsara stay
      fresh**, then a new step downloads `pipeline/lists.json` (kept fresh by the **"MRA Lists to JSON"** flow,
      now on a **15-min Recurrence**) and runs `build_from_lists.py --base data.js` to OVERRIDE the board
      sections (jobs/projects/tasks/users/holidays) + republish `data.js`. **Fail-safe**: if lists.json is
      missing/build errors, it leaves the workbook-built data.js live. Live data.js now carries `"source":"lists"`.
    - **Write:** `const USE_LISTS_WRITE = true` in `MRA_Dashboard.html`. Edits go to **"MRA Lists Write 2"**.
      **By item-id** matching now: dashboard `_findId()` resolves each row's SharePoint `_id` (stamped by
      `build_from_lists`) and `_listOps` emits `mergeById`/`deleteById` (new Switch cases in the flow) — so edits
      to tasks named with `& / # / – / emoji` save correctly (OData text filters broke on those). Filter path
      kept as fallback when no `_id`.
    - **Reload:** the Lists were fully reconciled to the workbook (255 ops + 59 by-id) and **verified 0 residual**
      before the flip (tooling: `gen_reload.py` / by-id generator in the scratchpad; diff = re-run vs live data.js).
    - **Rollback** (workbook untouched, ~3 min): set `USE_LISTS_WRITE=false` + redeploy `mode=live`; revert
      `export.yml` on the default branch (remove the override step) + re-run export. The **workbook shuttle +
      Office-Script still run** (shuttle feeds the fleet base; Office-Script writes a now-ignored workbook) — kept
      as rollback, **not yet retired**.
    - **TODO follow-ups (not blocking):** (1) **refresh lag is now ~15–30 min** (two unsynced 15-min cycles:
      Lists→JSON, then export) — tighten by having the Lists→JSON flow `repository_dispatch` the export, or merge
      the cycles; (2) retire the workbook shuttle + Office-Script once stable; (3) new project-task creates land
      with no TaskID (flow leaves `field_2` blank — text-matched edits still work); (4) Predecessor/Duration are
      Number columns and not written.
    - Gotchas + the full design are in `LISTS-WRITE-DESIGN.md`.
## 🔜 NEXT SESSION RUNBOOK — locked in 2026-06-25 (Rich wants all of this "tomorrow")

**A. Cutover follow-ups (post-flip cleanup — board is LIVE on Lists, see Step 3):**
1. **Verify the test edits persisted** — Rich added shop tasks on **Ferguson BizBox - Graphic Updates**
   ("test edit for Ricardo miller" etc.) as a live write test. Run "MRA Lists to JSON" → rebuild
   (`listspreview`) → confirm they came out of the Lists. (Pending at end of 2026-06-24 session.)
2. **Tighten refresh lag (~15–30 min → ~15):** today it rides TWO unsynced 15-min cycles (the
   "MRA Lists to JSON" Recurrence, then `export.yml`). Fix: add an **HTTP `repository_dispatch`
   (`event_type:"run-export"`) step to the END of the "MRA Lists to JSON" flow** (same fine-grained PAT
   the workbook shuttle uses) so writing `lists.json` immediately triggers the export rebuild → one cycle.
3. **Retire the workbook path (only once stable):** ⚠️ DEPENDENCY — `export.yml` still runs
   `Export-Data.ps1` for **fresh Fleetio/Samsara**, which needs the **workbook** (the shuttle copies it to
   the `pipeline` blob). So BEFORE retiring the shuttle, refactor the fleet pull to NOT need the workbook
   (Export-Data has a fleet-only path, or split it out). THEN pause the **"MRA workbook shuttle"** flow +
   stop the **Office Script** save path. Keep one final workbook backup. (The dashboard already writes to
   the Lists, so the Office Script is unused now — safe to retire after fleet is decoupled.)

**B. 🔐 STEP 4 — Secure login + role-based access (Rich: "add secure login + decide what each login sees").**
**DECISION 2026-06-25 (Rich): SKIP the code-based soft roles (old "Layer 1") — it'd be thrown away when
real SSO lands. Go STRAIGHT to real M365 sign-in ("real MRA logins") with roles + private data.**

- **THE PLAN — Azure Static Web Apps (SWA) with Entra ID (M365) login + roles.** Cleanest "real login":
  built-in Microsoft sign-in restricted to the MRA org, roles, and **data served behind auth (not public)**.
  This is a **HOSTING MIGRATION** off the public `$web` blob → SWA. Steps for tomorrow:
  1. **[Partner — Azure]** Create the **Static Web App** (mrashopdash subscription). Wire it to the GitHub
     repo (SWA auto-adds its own deploy workflow) OR keep our `deploy.yml` and point SWA at the output. Serve
     `MRA_Dashboard.html` (+ assets) and **`data.js` from BEHIND auth** (so it's no longer publicly fetchable).
  2. **[IT / often automatic]** Auth = SWA's **built-in Entra ID provider**; **restrict sign-in to the MRA
     tenant** (only @tandemeng.com / org accounts). IT may need to OK the app/consent; SWA's default Entra
     provider often needs no separate app reg — confirm tenant restriction.
  3. **[Claude] Roles from the MRA Users list (so Rich manages roles in SharePoint, not Azure):** add a small
     **roles API** (Azure Function in the SWA) that looks the signed-in user up in **MRA Users** and returns
     their **Role** (Admin / Editor / Viewer) via SWA's `rolesSource`. Then SWA gates by role natively.
  4. **[Claude] Dashboard:** read the signed-in identity + roles from **`/.auth/me`**; gate **tabs + edit
     buttons + ☰ admin items** by role (Viewer read-only · Editor edits · Admin = all + manage logins/EOTM/
     holidays/design-admin). The PIN/code-login + `_findId` write path stays; identity now comes from SSO.
  5. **[Claude] Pipeline:** repoint the data publish from public `$web` → the SWA's auth-protected location
     (the export hybrid build stays the same; only the publish target changes).
- **OPEN QUESTIONS to settle first thing tomorrow:**
  - **Shop TV / Wall mode — DECIDED (Rich 2026-06-25): NO login for the shop floor.** The **default,
    anonymous view = the FLOOR/shop-floor screen only**, read-only. **Login gates everything else** (other
    tabs, all editing, ☰ admin). Implication: the FLOOR data stays **publicly readable** (anonymous SWA route)
    — so it's NOT "fully private"; the sensitive tabs (Projects/Fleet/admin/editing) sit behind M365 sign-in.
    Build via SWA route rules (`staticwebapp.config.json`): `/` + floor = anonymous; the rest = authenticated.
  - **Role → tab matrix** (who sees what): e.g. shop crew → FLOOR (+FLEETIO?) only; managers → all; Rich = Admin.
  - Confirm the **MRA Users** list has everyone who needs access + their **Role**.
- **OWNERS to line up (Rich, give them a heads-up tonight/AM):** **partner** = create the Azure Static Web App
  + hosting; **IT** = Entra/tenant sign-in restriction (+consent if prompted). Claude builds the roles API +
  dashboard auth gating. (Per the access rules up top: Azure → partner, Entra/M365 admin → IT.)
- (Fallback if SWA is blocked: **Teams/SharePoint embed** auto-authenticates the org but leaves `$web` data
  public; or **MSAL.js** sign-in gate on the static page — both are softer. SWA is the real answer Rich wants.)
- **🔑 ENTRA APP REG (provided by Rich 2026-06-25) — NOT secrets, safe to keep here:**
  **Tenant ID** `1dc2dfee-5d93-4f0c-aa97-2344b72fe6b0` (= gomra.com tenant) · **Client ID** `fad6a2aa-2dab-4c46-ad3a-29e7040036ae`.
  The **client SECRET is NOT provided and must never be pasted in chat / committed** — it goes straight into the
  SWA config (`AAD_CLIENT_SECRET`) in Azure.
- **⚠ DECISION 2026-06-25: going OPTION 2 (real SWA, truly private).** Rich understood that an MSAL.js UI gate
  hides the *view* but not the *data* (the `$web` host serves data.js to anyone with the URL), so he wants the
  real lock-on-the-door (SWA checks the gomra.com login before serving data). His **partner** (Azure access — same
  login as the storage key) will create the SWA + wire the custom Entra provider.
- **🔓 "Partner can't get the client secret" — RESOLVED (it's normal, not a blocker):** Azure shows a client
  secret's VALUE only ONCE at creation, then hides it forever (unrecoverable by design). FIX = create a **NEW**
  secret: app reg → Certificates & secrets → New client secret → copy the Value → paste into the **Static Web App**
  application settings as `AAD_CLIENT_SECRET`. Never retrieved/shared; stays in Azure.
- **NEXT STEP owed to the partner (forwardable):** (1) create the **Azure Static Web App** (Standard plan, needed
  for custom auth) in the `mrashopdash` subscription, connected to the GitHub repo; (2) add custom **Microsoft Entra**
  login restricted to tenant `1dc2dfee…`, Client ID `fad6a2aa…` + a fresh `AAD_CLIENT_SECRET`; (3) send Claude the
  **SWA URL**. THEN Claude: `staticwebapp.config.json` (floor=anonymous, rest=authenticated), roles from MRA Users,
  `/.auth/me` gating, repoint the data publish behind auth, and give the partner the exact **callback URL** to add to
  the app reg. (Optional stopgap offered to Rich: ship the MSAL.js soft gate now for logins-today, swap to SWA when ready.)

- **(c) ✉ EMAIL ON NEW TASK — Rich wants this (2026-06-25).** Power Automate trigger **"When an item is
  created" on MRA Project Tasks + MRA Shop Tasks** (also fire on assignee-set) → look up the assignee's email
  (from the **MRA Users `Email`** column — same column the SSO uses) → **send an Outlook email**, subject
  **"MRA Command Center — you have a new task"**, body = a short blurb (task title · project · due date · any
  note) + optionally that person's current open list. Prereq: emails on the Users list (shared with SSO) +
  the **assignee name → email** match. NOTE: attaching the exact printed one-pager as a **PDF** is a stretch
  (needs an HTML→PDF step — OneDrive convert or a paid connector); **v1 = a clean formatted HTML email body**
  (looks like the one-pager, no attachment), add the PDF later if wanted. Also covers the design team
  (Steve K / Sarah Williams / Mark Mustonen / Brandon Choy) + everyone else.
  - **MRA logins are @gomra.com (Rich provided 2026-06-25)** — for the email-on-new-task flow + SSO role match.
    Rich (Admin) = `rmiller@gomra.com`; Brandon Choy = `bchoy@gomra.com` · Mark Mustonen = `markm@gomra.com` ·
    Sarah Williams = `swilliams@gomra.com` · Steve K (Kowalski) = `skowalski@gomra.com`. Put these (+ everyone
    else) in the **MRA Users `Email`** column with their **Role**.
  - **DOMAIN — RESOLVED enough to plan:** everyone who uses the board (incl. Rich's `rmiller@gomra.com`) has a
    **@gomra.com** account, so **SSO targets the gomra.com M365 tenant** — clean single-tenant sign-in. Rich's
    `@tandemeng.com` is the Tandem parent, **not needed** for the board. (Still worth a one-line confirm to IT
    that gomra.com is its own tenant when they make the Entra app registration.)
- **(d later) Teams/Outlook/Planner hooks** — assigned **Planner** task (Teams Tasks/phone) + channel posts;
  embed dash as a Teams tab. Reliable now we're OFF the Office-Script path.


### ⚠️ Dashboard release checklist (do EVERY time `MRA_Dashboard.html` changes — Rich shouldn't have to remind us)

1. **Build the feature.**
2. **Update the `? help`** — add/adjust the matching section in `GENERAL_HELP` (and `FLEETIO_HELP` for fleet stuff) so the in-app guide always matches what shipped.
3. **Bump the rev / CHANGELOG** — add a new entry at the TOP of the `CHANGELOG` array (rev + date + plain-English items). The footer badge + "What's new" modal read from it.
4. **Deploy** — commit, push, then trigger the `deploy.yml` workflow with `mode=live` (HTML only; leaves `data.js` alone) and verify the new code is live.

Treat help + rev as PART OF the feature, not an afterthought.

## Pending / requested (not yet built — remind Rich)

- **⏳ GANTT FULL-SCREEN DETAIL VIEW — make it MATCH the inline Projects Gantt (Rich 2026-06-25, "you missed it,
  do everything the same on every view"). The inline `#projGantt` toolbar got the clean treatment; the full-screen
  overlay `#ganttFS` (`renderGanttFS`, the view you get clicking a project bar / ⛶ Expand) did NOT.** Three pieces,
  all "make `#ganttFS` look like the inline one":
  1. **LOD slider** on the full-screen view — a slider (Rich wants it **vertical**, or right-to-left is fine) that
     progressively collapses detail: **all tasks → phases (+milestones) → milestones only → fully shrunk**, and
     back open the other way. (The inline gantt already has the 3-step `ganttLodSlider` 📊 proj/phase/tasks — extend
     to a 4-step tasks/phases/milestones/shrunk for the detail view, or reuse + add a 4th level.)
  2. **‹ › scroll arrows** (`.gfs-nav`, line ~741: currently `top:50%` = floating mid-screen) → move them **UP TOP,
     outside the toolbar**, like the inline `.gnav-l/.gnav-r` (`top:5px`). Consistency.
  3. **Simplify the toolbar into the ⚙ View dropdown** (`.tbmenu` native <details>, same as the inline Projects
     Gantt) — consolidate the flat row (Hide completed / By date / List order / Collapse all / zoom + pan sliders /
     Today / All / US / Canada holiday picker / assignee) into the same **⚙ View** popover + keep 🖨 Print / ⤢ / ✕.
  - ⚠️ VISUAL change on a daily-use view + Rich is hot on consistency — **build by REUSING the inline components
    (tbmenu, slider, .gnav positioning) so it matches by construction, then EYEBALL on the gantt preview
    (`ganttpreview` → preview-gantt.html) before going live.** Do NOT blind-ship.
- **🎨 UI batch requested 2026-06-24 (working through in waves; deploy incrementally).** Status: ✅ **FLEETIO (4) +
  Fleetio layout move + Service-under-Issues + Floor FL1/FL2/FL3 + Collapse-all fix + 📖 Product Catalogue ALL shipped
  LIVE (rev 7.1→7.5)**. ✅ **Projects-Gantt task-level rebuild (P1–P3) — SHIPPED rev 8.0** (phases expand/collapse +
  rollup bars on the inline gantt + both detail views). ⏳ Remaining = the full-screen-detail-view consistency above.
  - **Projects tab / Gantt — ⏳ THE LAST PIECE (deliberately not blind-shipped — it's a visual Gantt-engine change on a
    daily-use view; build it where the result can be eyeballed). Scoping done:**
    1. Project **tasks shown in the Gantt**, **expand/collapse** per project; clicking a project defaults to
       **open (tasks-expanded) mode**. *(the long-parked "task-level Gantt bars")*
    2. A **level-of-detail slider** on the Project Gantt: progressively **shrinks rows** — full tasks → … → milestones only.
    3. When you **filter by assignee**, still see **all that person's tasks**, expand/collapsible.
    - **HOW (scoped 2026-06-24):** the Gantt engine `renderGantt` (~line 5388) ALREADY renders task **sub-rows**
      (`cls:'g-subrow'`, used by the full-screen detail view `renderGanttFS` ~8029, task→row map ~8090-8115). Main
      Projects Gantt builds one row per project (~line 5958 `rows=dated.map(...)`). PLAN: (a) small engine tweak — render
      an optional unescaped `r.caret` before `esc(r.label)` in the gutter (line ~5454, label is currently escaped so a
      caret can't be injected via label); (b) a `GANTT_EXPANDED` Set + gutter caret to expand a project → push its tasks
      as `g-subrow` rows (reuse the FS task→row mapping); (c) P3: when `PROJ_WHO` (assignee filter) is set, auto-expand and
      show only that person's tasks; (d) P2: a LOD select/slider (All tasks / Milestones only / Projects only) controlling
      what sub-rows render. NOTE current project-row onclick = `openProjectEditor` — Rich wants click to **expand tasks**;
      keep the editor reachable via the name / ✎ button.
  - **Fleetio tab — ✅ ALL DONE (rev 7.1):**
    4. ✅ **⚠ Open Issues panel → true full-screen** (`toggleIssuesFS`, `.fs-on`; ⤡ Contract / Esc). *(F1)*
    5. ✅ **Fleetio issue # everywhere** — done in `fioTitle` (`.fionum` span), so it propagates to every panel. *(F2)*
    6. ✅ **Hover a row → highlights yellow** (CSS `:hover` on the fleet panel rows). *(F3)*
    7. ✅ **By Trailer: full unit name inline after the J#** (was tucked underneath). *(F4)*
  - **Floor tab:**
    8. ✅ **Per-tile ⊟/⊞ tasks button** — collapse/expand EVERY job's tasks in a tile at once (`toggleTileJobs`);
       per-job ▾ caret already existed. *(FL1, rev 7.2)*
    9. ✅ **Parking Lot + Next Up default COLLAPSED** (`DEFCOLL_ROWS` + `opts.defaultCollapsed`; open via `expandedJobs`). *(FL2, rev 7.2)*
    10. ✅ **Bay 3 + Bay 4 MIDDLE tiles** between Front/Back — auto-hide when empty + **Ⓜ Middle bays** filter to force-show.
        (`MIDDLE_BAYS`, columns grouped by bay number, middle jobs re-tagged `category=bay`, added to `BAY_OPTIONS`.) *(FL3, rev 7.4)*
  - **Fleetio layout (Rich 2026-06-24):** ✅ moved **⚠ Open Issues** up to the top (full-width) where **Needs Attention**
    was, and **removed Needs Attention** (covered by Open Issues). **SVC overdue stays in the dedicated 🔧 Service —
    Due & Overdue panel** (recommended NOT mixing service records into the issues list; revisit if Rich wants a combined view).

- **🗂 MRA Product Catalogue in the ☰ Menu — ✅ DONE (rev 7.5).** Hosted at **`/catalogue/index.html`** on `$web`
  (its `logo.png` + 3 JSONs live in the subfolder so they don't clash with the dashboard's root assets). No HTML edits
  needed — it already `fetch()`es its JSONs by relative path, so hosting fixed the "load the file" wonkiness. ☰ Menu link
  added (`href="catalogue/index.html"` — Azure Static Web doesn't serve subfolder index docs, so link the file explicitly).
  Files committed under `catalogue/`; `deploy.yml` uploads them on every deploy. ⚠️ NOTE: it's on the PUBLIC site (same as
  the dashboard) — incl. `mra-product-history.json`. Fine if the catalogue is OK public; lock down with Step 4 SSO if not.

- **Standardize Assigned-To names in the workbook (Rich asked 2026-06-18: "go back and fix
  them all the same", and "stop forgetting open items").** The `Project Tasks` `Assigned To`
  column has variants for the same resource. The dashboard's **Crew / Resource Schedule**
  alias-merges these at runtime (`CREW_ALIAS` in `MRA_Dashboard.html`), but the real fix is to
  clean the workbook so each crew/person is ONE name (then the alias map can shrink). Canonical
  groupings Rich has confirmed (clean these in the workbook):
  - **Wrap Team** ← MasterWraps, Master Wraps, Wraps
  - **Electricians** ← Electrician
  - **Maintenance** ← Doug, Doug Cooley  *(added 2026-06-18)*
  - **MRA Design** ← Steve K  *(added 2026-06-18)*
  - plus shared compounds like *Ted O'Malley / Electrician* (split on " / " at runtime).
  Tie into the Assignee-mismatch flagger + Assigned-To dropdown cleanup below.

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

## Shipped 2026-06-22

- **🏆 Employee of the Month editor = LIVE** (rev 4.90). `☰ Menu → 🏆 Employee of the Month`
  (admin/Rich only) edits the name + photo + on/off straight from the board — retires
  `Push-Photo.bat`. Back end = a Power Automate HTTP flow **"MRA EOTM"** (workflow id
  `6710721766a14785bbda0d27567e5219`): trigger **"Who can trigger the flow? = Anyone"** (so the
  dashboard's no-cors `fetch` can post anonymously), gated by **`pin == 1974`** in a Condition,
  then **two Azure Blob "Create blob (V2)"** actions writing `eotm.txt` (name or "off") + `eotm.png`
  (`base64ToBinary(photoB64)`) into the **`$web`** container. URL is in `EOTM_WRITE_URL` in
  `MRA_Dashboard.html`. ⚠️ LESSON: the NEW Power Automate (`*.environment.api.powerplatform.com`)
  HTTP trigger defaults to **"Any user in my tenant"** (OAuth-only, no `sig=` in URL → our anon post
  fails); must switch to **"Anyone"** + **Save** to get the SAS-signed URL (`…&sig=…`). Also fought a
  connection-binding gremlin: a deleted Azure Blob connection (`8ac11228…`) kept getting re-bound to
  new actions → "problem using … connection"; fix = **Change connection** on each blob action to a
  live "mrashopdash key" connection (do NOT mass-delete connections — one runs the 15-min workbook
  shuttle). Also wired the orphaned logistics **"↩️ Coming Back to MRA"** panel onto FLOOR (rev 4.82),
  **move/copy a project task** to another project (4.83) and **move/copy a shop task** between
  trailers (4.84), **Fleetio descriptions** on the board everywhere (4.85-4.87), **General-task bay
  tag** (4.88).

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

- **FLEET tab rebuild from Fleetio + Samsara (IN PROGRESS 2026-06-17 PM).** Replacing the hand-typed
  `FLEET=[…]` array (164 rows baked into `MRA_Dashboard.html`: f, t=type, y, m=make, j=Job/Tour,
  dot/ins/reg/ift flags) with a LIVE roster sourced from Fleetio + Samsara.
  - **Samsara = live GPS location.** Token in `samsara.txt` next to `Export-Data.ps1` (one paginated
    read-only `/fleet/vehicles/stats?types=gps`; ~89 tracked units, Samsara vehicle `name` = the bare
    fleet #, so matching is clean — **71 of 82 located units match the hand list**, up from 7). `$fLoc`
    (keyed by fleet# via `NormFleet`) now also carries `yard` (Samsara geofence name, e.g. "MRA Madison
    Heights" / "Warren Penske Yard") + `atISO` (GPS fix time → can flag stale, e.g. unit 1214 last
    reported 2025-05). NOTE Samsara has NO tour/job field; Fleetio likewise nightly-mirrors GPS so
    Samsara is the upstream truth — Export pulls location from Samsara, not Fleetio.
  - **Fleetio = roster + compliance.** Export STEP 1 (done, this commit) now EMITS
    `MRA_DATA.fleetio.fleet[]` = `{f, nm, t, y, mk(make+model), tour(=group_name), stat(status),
    mi/mu(primary meter+unit), oi/ow/os(open issues/WOs/service counts), plate, rs, vin,
    comp:[{ty,due,s}]}`. `comp` = the vehicle's renewal reminders, each labeled via the
    `vehicle_renewal_types` id→name lookup (the earlier probe showed reminders carry only
    `vehicle_renewal_type_id`, not a name — hence the lookup). Fleetio confirmed: 149 vehicles, 202
    renewal reminders / 89 vehicles, each with a real `next_due_at` + `vehicle_renewal_reminder_status`.
  - **Tour rule (Rich chose 2026-06-17): Fleetio Group FIRST, hand-typed Excel list as FALLBACK.** The
    dashboard keeps its existing `FLEET=[…]` as the fallback/seed and merges the Fleetio roster over it
    by fleet# (so nothing is ever lost; trucks grouped in Fleetio go fully automatic). Fleetio "Group"
    looks tour-shaped already (saw `"Siemen's DBX 2 J1110-3005"` vs hand `"Seno Medical / 1454"`).
  - **STEP 2 DONE — shipped rev 3.23 (deployed `mode=live` from the feature branch).** FLEET tab now
    renders from `MRA_DATA.fleetio.fleet[]` merged over the built-in `FLEET` array (Fleetio-first,
    office list fallback so nothing is lost): new **Status / Miles / Open** columns + real **compliance
    DATES** (Inspection→DOT, Registration, Insurance; **IFTA stays from the office list — Fleetio has
    no IFTA renewal type**), tour = Fleetio Group first. Location cell prefers the Samsara **yard**
    name, else City, ST. Renewal type names confirmed live: **Inspection 84 / Insurance 67 /
    Registration 49 / Emission 2**. Merge vs live data = 149 Fleetio + 68 office-only = **217 rows**.
    `renderFleet()` now also runs on every live refresh (was first-paint only) and falls back to the
    old office-list render if `fleetio.fleet` is absent.
  - **PENDING:** Rich must re-run the export with the NEW Samsara token in `samsara.txt` — the
    failed-token 15:01 run left `fleetio.locations` empty, so locations show "—" until he re-runs
    (roster/compliance already populate from that run). Then verify locations repopulate live.
  - **SECURITY:** Samsara token was pasted into chat (twice) then rotated by Rich; the live token lives
    only in `samsara.txt` on his machine. Never commit tokens.

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

