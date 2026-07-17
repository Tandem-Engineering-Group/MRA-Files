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
- **👥 TWO DIFFERENT PEOPLE (Rich clarified 2026-06-25) — don't conflate:**
  - **MRA IT guy** = gomra.com **Entra/M365** admin. Created the app reg (gave Tenant+Client IDs). Owns the
    **app registration** (in the gomra.com tenant).
  - **Partner (Tandem)** = has the **Azure key / `mrashopdash` subscription** access. Builds the SWA + hosting.
- **🔓 "Partner can't get the client secret" — EXPLAINED:** the secret lives on the **app registration in gomra.com**
  = the **IT guy's** tenant, NOT the partner's Azure — that's literally why the partner can't see it. Azure also hides
  a secret's value after creation (one-time view). So the **IT guy** must create a NEW client secret (app reg →
  Certificates & secrets → New client secret → copy Value) and hand the value to the **partner** to paste into the
  **SWA** app settings as `AAD_CLIENT_SECRET`. (Alt: IT adds partner as an owner of the app reg — more hassle.)
- **NEXT STEPS — split by owner:**
  - **IT guy (gomra.com):** (1) create the client secret → hand value to partner; (2) LATER add the SWA **callback URL**
    to the app reg's redirect URIs (Claude provides exact URL once SWA exists); (3) confirm app reg = single-tenant.
  - **Partner (Tandem/Azure):** (1) create the **Azure Static Web App** (Standard plan — needed for custom auth) in the
    `mrashopdash` subscription, connected to the GitHub repo; (2) configure custom **Entra** login (Tenant `1dc2dfee…`,
    Client `fad6a2aa…` + IT's secret as `AAD_CLIENT_SECRET`); (3) send Claude the **SWA URL**.
  - **THEN Claude:** `staticwebapp.config.json` (floor=anonymous, rest=authenticated), roles from MRA Users list,
    `/.auth/me` gating, repoint the data publish behind auth, give IT the exact callback URL.
  - (Optional stopgap offered to Rich: ship the MSAL.js soft gate now for logins-today, swap to SWA when ready.)

- **(c) ✉ EMAIL ON NEW TASK — ✅ BUILT + LIVE for PROJECT TASKS (2026-06-26).** Flow **"MRA Email"** (owner Rich,
  Office 365 Outlook conn `rmiller@gomra.com`): trigger **"When an item is created" on MRA Project Tasks** →
  **Get items** on **MRA Users** with Filter `Title eq '<Assigned>'` → **Send an email (V2)** To =
  `first(body('Get_items')?['value'])?['Email']`, subject "MRA Command Center — you have a new task", body =
  Task/Project/Due(FinishISO)/Notes + dashboard link. **GOTCHAS LEARNED (don't repeat):** (1) the MRA Users name
  column's INTERNAL name is **`Title`** (just *labeled* "Name" via `Set-TitleLabel` — see `Provision-MRA-Lists.ps1`),
  so the filter is `Title eq …`, NOT `Name eq …`; (2) **straight quotes only** in the Filter Query — smart/curly
  quotes throw "expression … is not valid / Creating query failed" (BadRequest 400); (3) the assignee on the task
  must EXACTLY match a **Name** in MRA Users (`Sarah Williams` ok; ⚠️ board lane **"Steve K" ≠ "Steve Kowalski"** —
  align them). MRA Users now has Email filled for all 8 (Rich/Luc Giglio/Al Karloff/Megan Fraser/Steve Kowalski/
  Brandon Choy/Mark Mustonen/Sarah Williams). **STILL OPEN:** (a) **dashboard board-adds don't reliably create the
  list row** — a task added via the dash Projects editor did NOT appear in MRA Project Tasks even after a 15-min
  cycle (direct "+ Add new item" in the list DID fire the flow), so verify the dash `addProjectTask` create op is
  landing in the **"MRA Lists Write 2"** flow (board saves are no-cors fire-and-forget — check that flow's run
  history) or board-added tasks won't email; (b) **MRA Shop Tasks** = clone the flow (Save As → trigger list =
  MRA Shop Tasks) for bay tasks; (c) **re-assigning an EXISTING task won't fire** ("item created" only — would need
  created-or-modified + an assignee-changed guard, or fire from the dashboard on assign); (d) **design-board "added
  here" general cards DON'T email** (they go to design.json via the **"MRA Design Board"** flow `DESIGN_WRITE_URL`,
  not a list) → to wire: small dash change in `dtbAddGen` to POST `{who,title,due}` to a new **HTTP-triggered** email
  flow (clone of "MRA Email": HTTP trigger → same Get items + Send email), then embed its URL + deploy.
  --- ORIGINAL SPEC: --- Power Automate trigger **"When an item is
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

## ✅ REQUESTED 2026-06-25 — Design-task VERIFICATION / sign-off workflow (BUILD NOW on existing code logins)
Rich wants a two-step complete for **project-fed** design tasks (NOT the ad-hoc/general ones added on the board):
- **Design board stays OPEN (no login)** — unchanged. On a **project-fed** task the button = **"✓ Mark ready"** → sets the
  project task to a new **"Pending Verification"** status (the flag), stamped with who (the task's assignee, e.g. Sarah).
  On an **ad-hoc/general** task the button still **self-closes** (design.json), no sign-off.
- **Projects tab annunciation:** a **"🟡 Awaiting verification (N)"** panel (visible to all) — project · task · marked-by ·
  PM · since — with **✓ Verify** (→ Completed) and **↩ Send back** (→ In Progress).
- **Gated to the task's assigned PM OR admin (Rich)** using the EXISTING code logins (findUser→CURRENT_USER; PM name
  matched fuzzily to the project's PM; Rich=admin sees all). Everyone can SEE the flag so the PM knows to log in.
- **DECISION (Rich): do it NOW with the number logins, transfer to gomra.com SSO later** (IT guy is struggling with the
  client secret + off next week → SSO is a few weeks out). Build the `canVerify(task)` check so it's a one-line swap to
  SSO roles later. Approach = a real **"Pending Verification" status on the task** (single source of truth; shows on
  Projects tab + Gantt + reports; never counted done until verified). Ship to a **preview** first for Rich to run the
  Sarah→Al loop, then live.



### ⚠️ Dashboard release checklist (do EVERY time `MRA_Dashboard.html` changes — Rich shouldn't have to remind us)

1. **Build the feature.**
2. **Update the `? help`** — add/adjust the matching section in `GENERAL_HELP` (and `FLEETIO_HELP` for fleet stuff) so the in-app guide always matches what shipped.
3. **Bump the rev / CHANGELOG** — add a new entry at the TOP of the `CHANGELOG` array (rev + date + plain-English items). The footer badge + "What's new" modal read from it.
4. **Deploy** — commit, push, then trigger the `deploy.yml` workflow with `mode=live` (HTML only; leaves `data.js` alone) and verify the new code is live.

Treat help + rev as PART OF the feature, not an afterthought.

## ✅ DONE 2026-07-15 PM: GPS VIN-join backfill (was "NEXT SESSION")
**SHIPPED + VERIFIED live:** Export-Data.ps1 (default branch, commit 8c6356a) now builds a
`$vinToFleet` map from the Fleetio roster and, in the Samsara loop, publishes each GPS fix under
the Fleetio fleet # too when the VIN matches a different name (reads `$v.externalIds.'samsara.vin'`;
freshest-fix rule kept; `vin-joined N` counter in stdout + samsara-debug.txt). Verified:
`locations["4489"]` = Madison Heights (joined from Samsara "IW164"), J1559 On Cloud card shows
GPS instead of "📡 no GPS". Card shows ⚠ (city, not the MRA-yard geofence) — honest per Samsara.
--- original note: ---
## GPS backfill from Fleetio telematics (Rich 2026-07-15)
J1559 On Cloud Infowheel (unit 4489 Dodge Ram) shows "📡 no GPS" although Fleetio telematics HAS a
3-min-old location — because `fleetio.locations` is built from SAMSARA ONLY in Export-Data.ps1 (default
branch `claude/exciting-keller-wm7u2p`); units tracked in Fleetio-but-not-Samsara (vans/trucks) all read
no-GPS. ROOT CAUSE FOUND (Rich's Samsara shots 7/15): SAME VAN, TWO NAMES — Samsara "IW164" vs Fleetio
"4489 DODGE RAM 3500...", identical VIN 3C7WRVMG2RE124489. Export links Samsara↔Fleetio by unit
number in the NAME → never connects. FIX: **VIN join** in Export-Data.ps1's Samsara matcher (both
payloads carry VIN) — key $fLoc under the Fleetio fleet # too. Fixes all dual-identity InfoWheels
vans (IW163-167 class match by name already; 4489-style don't). Dash-side `_ynLoc` is CORRECT —
no JS change needed. Test: J1559 On Cloud card shows 📍 after next export.
Also in flight: SWA created?(await Rich URL+token) · Infowheels 3D builder awaiting Brandon/Mark OBJ
exports (instructions given 7/15; Rev1 = shell+floors+cabinets at /builder/).

## Shipped 2026-07-17 — 🙋 MY WORK rebuilt to report quality + pro daily email (rev 27.4 → 27.5)

- **rev 27.4 deployed + live-verified** (Al Karloff email `al.karloff@`→`akarloff@gomra.com` in ROLE_BY_EMAIL).
- **rev 27.5 — MY WORK page + daily email rebuilt (Rich: "weak / half-ass ... make it professional like the
  reports we sent Al & Megan").** The bare panels are gone. Both the **MY WORK tab** and the **?mywork=Name**
  daily-email page are now full one-pagers matching `buildPMReportHtml`:
  - **Shared `REPORT_CSS`** const extracted (PM report + My Work email use the SAME stylesheet → identical look;
    added `.pv`/`.pend`/`.fol`/`.hnote` classes). PM report now reads `const css=REPORT_CSS` (regression-tested).
  - **`myWorkFor(name)` rebuilt** to gather: od/due/later (own shop+project tasks), **pendingMine** (tasks I marked
    ready, awaiting PM), **awaitingMe** (Pending-Verification tasks where I'm the PM/admin — `projIsPendingVerify`),
    **doneRecent** (closed last 7d), **myProjects** (PM'd OR followed, health-sorted), **milestones** (30d), **follow**.
  - **Tab (`renderMyWork`, dark):** stat strip (open·overdue·due·to-verify·marked-ready·projects) + ✅ Awaiting
    your sign-off (inline **✓ Verify / ↩ Back** via existing `verifyTask`/`sendBackTask`/`gotoVerifyTask`) + Overdue
    + Due-this-week + 🟡 Marked-ready + 📊 My Projects (health color/target/past-due/%) + ◆ Milestones + ✅ Completed
    7d + Everything else + **⚙ Customize (Follow any project)**.
  - **Email (`buildMyWorkHtml`, light):** identical sections, printbar + MRA-orange title + stat tiles + badges +
    photo thumbnails; footer links back to the live dashboard. It's the SAME page the daily flow links.
  - **⚙ Follow** = per-person `localStorage` (`mra_mwfollow_<namekey>`) — pin any project (health/milestones/past-due
    show even if not assigned). Helpers: `mwGetFollow/mwSetFollow/mwToggleFollow/mwPickFollow`.
  - Help guide: new **②ᵐ 🙋 MY WORK** section. Validated: node --check PASS + **headless render** (tab + email + Sal
    non-PM + PM-report regression + verify-button path + follow flow) — zero pageerrors; screenshots eyeballed.
  - ⏭ **Daily-email Power Automate flow still to build with Rich** (Recurrence → per-person Send-email of the
    `?mywork=<Name>` link, CC rmiller@gomra.com; routing table below). Trigger with "let's build the email flow".

## Shipped 2026-07-16 EVENING — 🔐 SSO LOGIN LIVE (rev 26.0 → 26.3) + live updates + Fleetio GPS fallback

- **🔐 Microsoft 365 sign-in LIVE on the board.** MSAL.js browser (public client, PKCE — NO secret; tenant
  blocks client secrets + required admin consent, Tim granted org-wide consent). Floor = anonymous (shop TVs
  unchanged); everything else behind @gomra.com sign-in. `SSO` module gated to HOSTS=['mrashopdash.z13...'],
  **FAIL-OPEN** (off-host / MSAL fail / 6s timeout → no gating, board behaves as pre-login → shop TV can never
  wall). Config: TENANT 1dc2dfee-5d93-4f0c-aa97-2344b72fe6b0, CLIENT fad6a2aa-2dab-4c46-ad3a-29e7040036ae
  (app reg "MRA Dashboard Lists Reader"). Redirect URIs (SPA) Tim registered: .../MRA_Dashboard.html + .../ .
- **Roles (Rich's access xlsx):** admin=Rich/Al Karloff/Luciana Giglio · editor(full)=Megan Fraser/Brandon Choy ·
  design(editor, restricted menu)=Sarah Williams/Mark Mustonen · exec(view-all read-only)=Tony Amato/John Renaud/
  Gino Bitonti · everyone-else=staff (Floor/Fleetio/Assets, no Projects). Steve Kowalski REMOVED (fired — tell Tim
  to disable his gomra acct). `ROLE_CAPS` tab+menu matrix; 5 special menu items tagged `data-perm`
  (builder/sales/ghost/logins/holidays/eotm). **26.3: role matches EMAIL *and* display NAME** (order-insensitive)
  — a wrong-guess email dropped Al to staff (lost Projects); name fallback fixes it. Pill tooltip shows resolved
  email+role for self-diagnosis.
- **26.1 ONE LOGIN:** signed-in edit-role (admin/editor/design) edits with NO number code (ensureAuth bridges →
  CLOSE_PIN='1974' [flow-accepted, verified], CURRENT_USER=SSO name). View-only roles blocked w/ message. Code
  modal kept as shared-floor fallback (leads with Microsoft button). 26.2 FIX: MSAL CDN url 2.38.3 was 404 →
  2.38.1 + jsdelivr fallback (the 404 fail-opened = "login not showing" on all devices).
- **⏱ LIVE UPDATES (was 15-min):** the "MRA Lists to JSON" flow ALREADY had the repository_dispatch HTTP step
  (URI .../dispatches, body run-export, PAT). Rich changed its **Recurrence 15 min → 2 min** + re-saved (had to
  delete a stale `Overwrite=true` param on the SharePoint Create file step — modern connector overwrites by
  default). VERIFIED: exports now fire ~2 min apart, data.js updates same-cycle → **edits propagate in ~2-3 min**.
- **📡 Fleetio GPS fallback shipped earlier (rev 25.7 + Export-Data.ps1 33c08de):** dead-tracker units use
  Fleetio's newer last-known location; ">60d = tracker DEAD · per Fleetio" chip. Unit 83 now Madison Heights.
- **🚚 InfoWheels 3D Builder** at /builder.html + ☰ Menu (rev 25.6, smooth van hull, true colors) — awaiting
  Brandon/Mark real OBJ exports.
- Deploys: 25.5→26.3 all `mode=live`, verified by polling rev. Branch claude/zealous-fermi-6n5pil.

### 🔜 TOMORROW (2026-07-17) — locked in
1. **📁 Migrate Claude files off Tandem → MRA (gomra.com) SharePoint** (Rich + Tim only). ⚠ NOT just a copy: the
   Lists→JSON flow, workbook shuttle, and the SharePoint **Lists** (Jobs/ShopTasks/ProjectTasks/Users) all point at
   `snptechnical.sharepoint.com/sites/MRASiteProject/.../MRA Claude Code/01.1 RL Claude Bot` and run under
   **RMiller@tandemeng.com** connections. Moving to gomra.com = repoint every flow's Site Address + re-auth
   connections as a gomra.com login, and likely recreate the Lists in the new site. Tim to create the gomra.com
   SharePoint site (Rich+Tim owners) first. Scope carefully — it's a pipeline migration.
2. **🔑 Rotate the GitHub PAT** — it appeared in a screenshot (github_pat_11CFZU…). Regenerate the fine-grained
   PAT (Contents:write, org resource owner) → update it in BOTH flows (workbook shuttle + MRA Lists to JSON HTTP
   steps). Walk Rich through it.
3. **Verify Al Karloff's login** lands as Admin (name-fallback should fix the email-guess). Have anyone with wrong
   access hover the pill → read email+role → fix the map.
4. If Power Automate nags about run limits from the 2-min recurrence, dial to 3-5 min.

## Shipped 2026-07-16 PM (rev 25.5 → 25.8 · GPS fallback · catalogue rules re-audit · 3D builder)

- **25.5 crew ?sheet= links + prints carry 📋 schedule tasks** (buildCrewSheetHtml merge, same rules as columns).
- **25.6 InfoWheels 3D Builder**: ☰ Menu link + root alias `/builder.html` (Azure 404s subfolder URLs
  without index.html). Builder = self-contained three.js r147 (UMD+OrbitControls+RoomEnvironment embedded),
  smooth ExtrudeGeometry ProMaster-class van hull (first boxy version = "dog ass" per Rich), wrap/accent
  colors (LinearToneMapping keeps swatch-true color), floor/wall finishes, 4 cabinet slots/side
  (empty/low/high/bench), 📸 screenshot, 🔗 config links (state in URL hash). deploy.yml uploads builder/.
  Real IW2.0 Inventor OBJ exports from Brandon/Mark drop in later; UI stays.
- **📡 GPS Fleetio fallback (Rich: "match Fleetio, note gps dead")**: Export-Data.ps1 (default branch,
  commit after 33c08de) — after Samsara, units with stale(>14d)/missing fix get a per-vehicle GET
  /api/v1/vehicles/{id} (the index does NOT embed current_location_entry; detail does; dead-tracker
  candidates first, cap 60, 250ms gaps) and use the newer Fleetio last-known location with src:'fleetio'.
  22 units gained locations (unit 83 → Madison Heights 4/24 ✓, never-tracked client trailers too).
  Dash 25.7: `_gpsStaleTxt` — >60d = "tracker DEAD", "· per Fleetio" source note, all 4 chip sites.
- **25.8 covered schedule lines hide**: `_ptCov` (open shop tasks' [pt:] tags + exact-normalized text on
  the main job) filters all 3 📋 collectors — a schedule line being worked as a shop task shows ONCE
  (Rich's Trumpf "2 tasks for the same" complaint; his ⚒-created tasks carried tags and self-resolved).
- **🗂 CATALOGUE: Quintin's Product Lookup Rules V2.1 locked in** at `catalogue/PRODUCT_RULES.md` — THE
  standard for every import. Subagent re-audit of the IMPORT-001..185 batch (commit e7d6533f, deployed):
  185 → 156 proper products (5 deduped into existing, 11 within-batch, 13 fee/service lines removed +
  17 history rows), all real DDCCSSFFF-III ids (existing CC/SS code map reused; new cats: Hydraulics,
  Vehicle Accessories, Shop Equipment, Wire & Cable, Networking, Computers & Tablets, Furniture),
  315 history rows relinked, canonical names per the category rule table. review_status:
  365 ready / 38 manual_review (8020 bare SKUs, VHB 4950 possible dupe, Starlink possible dupe, CNC perf
  sheet kept as custom product, etc. — Quintin should sweep these in the Table tab). Validator all-pass;
  37 pre-existing `-Sxx` sub-item rows grandfathered (IDs permanent). Zero IMPORT- ids remain live.

## Shipped 2026-07-16 AM part 2 (rev 25.1 → 25.4) — MRA Shop bucket · J#-linking · merges · perf

- **25.1 "MRA Shop / Sal" (Rich: keep MRA Shop load):** `dtbReassignTo` preserves the MRA Shop bucket
  alongside the person; finder's isShop = shop-ONLY (bucket+person = picked up); ⚒ prefill strips bucket.
  **DATA REPAIR:** the 19 plain-replaced assignments from 7/15 were rewritten to "MRA Shop / X" by capturing
  the dashboard's own mergeById ops headlessly (stub fetch, drain _wq, stamp pin/user) and curling them to
  LISTS_WRITE_URL — all 19 verified landed in data.js. (Repair list built by diffing the 7/13 data snapshot.)
- **25.2 📋 schedule tasks ON bay cards, J#-FIRST linking (Rich):** `_projJobsFor`/`_projMainJob` (project with
  a J# links ONLY by J#; name containment fallback; real bay beats lot/hold; closest-name tiebreak) + 📋 pill
  & expandable schedule list on the main card, ⚒ per line.
- **25.3 ⚡ PERF (iPad black screen):** per-card matching froze iPads → `_pjRebuild()` builds window._PJBYROW
  once per renderAll; cards do O(1) lookups. NOTE: renderAll baseline is ~600ms at 6× CPU throttle — the page
  is heavy; a real speed pass is a candidate next task.
- **25.4 MERGED into crew columns (Rich's screenshots):** schedule lines ride the project's TRAILER card in the
  crew columns (out entries carry row; host lookup via _projMainJob; standalone 📋 card only when no board job,
  e.g. JFSD). Header: "42 open · 16 trailers · 18 📋" (📋 = task count).
- **Project Job #s STAMPED IN THE LISTS** (build_from_lists P_PROJJOB='JobNum' col on ProjectTasks; first task's
  value → project.jobNum): Oakland J1420 · Trumpf J1554 · Medtronic J1553 · SMC J1542 — verified in data.js.
  Cisco (J1558) + JFSD (J1526) were already set. To link a future project: put its J# in the JobNum column of
  any of its schedule rows (or ask Claude to stamp it).
- **⚒/verify loop end-to-end test pattern:** stub CLOSE_PIN/CURRENT_USER/ensureAuth/shopWrite in headless page,
  run ptbOpen→ptbSubmit→closeTaskByName×N, auto-accept dialogs → parent hits "Pending Verification".

## Shipped 2026-07-16 AM (rev 24.6 → 25.0) — stale GPS · repeat-close fix · WO 24h filter · 📋 tasks on crew columns · ⚒ break-into-shop-tasks

- **24.6 stale GPS:** unit 83 FM Global's tracker last pinged 09/2022 from Dauphin Cty PA — board showed it as
  current ("⚠ GPS: Dauphin County, PA"). `_gpsStale(loc)` (>14d) → muted "📡 GPS stale · last …" chip everywhere
  (bay pills, meeting `_mtgGps` {stale:true}, lot cards, What's-Next state/mismatch, deficiency GPS list, at-MRA
  filter keys). Stale fixes never make location claims. (Tell Doug: unit 83 + 1214 trackers dead.)
- **24.7 recurring tasks:** Rich closed Jeff's weekly eyewash 3× — closing a 🔁 spawns an identically-named
  next-cycle copy instantly, looked like a failed close. `isSnzRep(t)` (open+repeat+due>today+3d) hides the copy
  from cards/crew queues/sheets/WO prints + `oRecompute` excludes it (recompute pass at renderAll, idempotent);
  close (optimistic + `_findId` ShopTasks) targets earliest-due OPEN copy; spawnRepeat never stacks (any open
  same-name copy blocks). Data was clean — no dup rows landed from the 3 closes.
- **24.8 WO 24h filter (Stephanie):** print picker "🧾 Which:" radio + `?wo=doug` page "Show: 🗂 All / 🕐 Updated
  last 24h" buttons (`opts.since`; job prints only if a task was added (op) or closed (cl) since yesterday for
  that crew; green NEW tag on fresh lines; `&new=1` deep-links filtered).
- **24.9 📋 project tasks on crew columns:** Rich's ~20 finder assigns "disappeared" — writes all landed (32 crewed
  project tasks in window), but crew columns only showed SHOP tasks. Now `build(re)` appends one 📋 card per
  project (same window: startISO||finISO ≤ today+14, not done/complete, no milestones, who matches crew re);
  header "N open · M trailers · K 📋". Card/lines click → openProjectEditor(name).
- **25.0 ⚒ break-into-shop-tasks + PM sign-off:** ⚒ button on 📋 lines (crew columns + ⚠ finder) → `ptbOpen`
  modal (job picker best-match preselect, one task per line, assign+due) → each line = real addTask on that job
  with `[pt:<proj>|<handle>]` in comments (`_ptTag`), parent schedule line → In Progress. `ptOfferReady(cm)` on
  close: when the LAST tagged sibling closes → `dtbMarkReady` (existing design-board machinery) → 🟡 Pending
  Verification → Projects-tab verify queue (canVerify: PM/Rich). Verified headless end-to-end (Trumpf Flooring →
  3 tasks → closes → "goes to Al Karloff to verify").

## Shipped 2026-07-15 PM (second wave, rev 24.3 → 24.5) — floor cleanup · 🆕 badge · leave calendar/upload

- **#1195 "Broken Vent" investigation (Rich: "not showing"):** it WAS everywhere (data.js since 7/13
  23:30, Fleetio tab row 69/76, meeting card, dash card behind "🔧 1 Fleetio ▸") — a DISCOVERABILITY
  problem: default sort = overdue→priority→OLDEST, so new issues sank to the bottom. Fix = 24.3 badge/float.
- **24.3:** (1) ⚠ Open Issues: issues opened ≤7d get **🆕 new** badge (`_fioIsNew`/`_fioAge`) + float
  right under the overdue block in the default sort; (2) **FLOOR slimmed (Rich):** `#crewSchedPanel`,
  `#floorGanttPanel`, `#fl-flagged`, `#fl-returns` hidden via CSS `display:none!important` (NOT deleted —
  one line brings any back; renders still run into hidden divs, zero null-refs). 🔔 due-back banner stays;
  Coming-Back lives on FLEETIO tab + Meeting view. **"Open Work by Assignee" panel STAYS** (Rich's
  screenshot was sent in error — he said "wrong screenshot"); (3) **Staff on Leave: 📅 month-calendar
  view** (`renderLeaveBox`/`_lvCalHtml`, chips = who's out, ‹ › nav, tap-to-edit, `#fl-leave` spans
  full grid width) + **📤 Upload** (`lvUploadBtn`/`_lvImport`, SheetJS via `ensureXLSX`).
- **24.4:** leave box **defaults to calendar** (LEAVE_VIEW='cal'; ☰ List flips back, remembered).
- **24.5:** Upload **decodes the HR payroll leave report** (Rich's vaca.xlsx: single-column lines, one
  row per 8-hour day): `_lvPayroll` regex-parses lines, Approved-only, "Roe, Kayla M."→"Kayla Roe",
  **merges day-rows into ranges** (weekend gaps bridged), plus shared dupe pass (`_lvLast` last-name +
  date-overlap vs existing board leave). Verified vs his real file: 24 day-rows → 8 entries, Giglio's
  two separate weeks stay separate. Generic Name·Start·Return sheets still work.
- Deploys: all `mode=live`, verified by polling `rev:"24.x"`. Leave writes ride the normal `addJob`
  (bay APL/Holidays · status Leave) path → ~15–30 min to sync back like any board edit.

## Shipped 2026-07-15 — verification day (rev 23.1 → 23.7)

- 23.1/23.2 ⚠ finder 📋 rows: muted context line (↳ parent · phase · comments — Al's Teams ask) + flex-wrap layout fix.
- 23.3 Work Orders: 🏭 Jobs selector in the print picker (default ALL; tick to print one job's WOs).
- 23.4 **Next Up/On Hold reconciles by eye**: ONE rule — tile = NEXT UP + ON HOLD KPIs (both bay-based);
  tile header shows split (bayCard `opts.headExtra`); ⏭/⏸ lane pill per held job; status-On-Hold-elsewhere
  jobs get amber "⏸ on hold (status)" pill on their own card (Pod 1086 case) and DON'T count in the tab.
- 23.5 Pipeline panel default-collapsed (joined setupFloorCollapse list). 23.6 OFF-SITE/PARTS KPI tab.
- 23.7 **🩺 Deficiency List** (`buildDeficiencyHtml`; ☰ Actions + `?fix=1&pm=`): all correctable problems
  by PM→project + Floor&Ops, green FIX hint per line — built for a scheduled AM email (Rich builds the
  3-step Recurrence→Send-email flow; steps given in chat 7/15).
- Fleetio-MRA-on-held-tile answered: feature already on all cards; 5 of 6 held units simply have no
  Back-to-MRA dates in Fleetio (only SMC J1542 does) — data-side fix.
- Audit findings 7/15: 89 open project tasks past-due (Medtronic 43/Cisco 14/Oakland 10/Trumpf 8),
  35 undated; shop side clean (75 open/11 od/2 unassigned); ghosts left: ADLM 2026 (9!), Trumpf Trailer
  Build, SWC MMOT Hawaii, Make Sal Happy; 2 TBD PMs (Siemens 53ft #1/#2); S&P pipeline empty (0 prospects).
- GOTCHA: `isParkingBay`/`isHeldBay` are renderFloor-LOCAL (globals are `bayIsParts`/`bayIsHeld`) — standalone
  builders need their own lot regex.

## Shipped 2026-07-14 — outage + day-2 polish (rev 21.6 → 22.7)

- **⚡ AZURE OUTAGE (Microsoft's side, resolved):** all writes to the `mrashopdash` storage account failed
  ~00:12→14:16 UTC 7/14 with `ErrorCode:ResourceNotFound` — BOTH GitHub Actions AND Power Automate flows
  (independent creds) → account-level, partner called Microsoft. READS kept working (board stayed up; edits
  saved to Lists, synced after recovery). LESSONS: (1) the generic `grep rev:"[0-9.]*" | head -1` on the live
  HTML matches a DOC-COMMENT `rev:"3.1"` at ~line 3424 FIRST — always grep the SPECIFIC rev string (a false
  "site reverted to June" alarm came from this); (2) failed-deploy triage: check `data.js` Last-Modified +
  whether PA flows also fail before blaming code; (3) with the GitHub MCP down, deploys can ride a TEMP push
  trigger on deploy.yml (`branches:[main,<dev>]` — file at the PUSHED ref is used; paths filter needs a
  dashboard-file change) — added + reverted same day.
- **Shipped:** 21.6 🧹 ghost-task screen + gantt icon legend + ⏱ new-project watchdog · 21.7 punch ⚠ Issue
  button · 21.9 issue-button hover walkthrough + banner · 22.0 **MRA-Shop project tasks in the ⚠ unassigned
  finder** (start ≤14d or overdue; 👤 assign writes back via dtbReassignTo/editProjectTask) · 22.2 rows show
  ▶ start → finish (finish-only read as >2wks, Rich confused) · 22.3 **WO/punch ASSET # = real fleet unit(s)**
  (from the job's Fleetio issues; title → sub line; maintenance ask) · 22.4/22.6 Logistics Calendar quick link ·
  22.5 **meeting hover-dock** (reuses `fioIssueDetailHtml` in `#mtgIssDetail`, `.fionum` delegate, Esc closes
  card first) · 22.7 **meeting Parking-Lot cards match Coming-back** (Fleetio MRA range, `_ynLoc` GPS chip,
  status/dates/client, ✎ open; sub-jobs skip fleet bits).
- **Operational finds for Rich:** SWC IL J1422 board=Parking Lot but GPS=Springfield Charter Township (fix bay
  or move unit); 42 genuinely past-due Medtronic tasks (26 MRA Design) — statuses need cleanup, all views now
  surface them honestly (21.5 alignment).
- Cleanup: dropped the wrong-base stash + local healthpreview backup branch (commit lives as default-branch tip).

## Shipped 2026-07-13 — Production Meeting · Sales & Planning · sub-jobs · punch list / recaps (rev 19.0 → 21.0)

*(Full rev detail = the CHANGELOG array. Session highlights + gotchas:)*

- **🏭 Production Status Meeting (19.0–20.3)** — Projects header + ☰ Menu. 3 stages: PM report-out (owner band:
  tiles + stacked bar + **PM Project Load** chart; **Program Gantt** grouped by PM w/ sort picker + highlighted PM
  header rows + **JFSD-family rollup rows**), Discuss & Align (**manual** discuss-list — auto-copying yellow/red made
  stage 2 = stage 1, Rich was confused; now only what you tap `discuss ▸`), Team & Actions (real `[MTG]` tasks on
  🛠 General). Past-due lists expandable (+ show N more). **Print = WYSIWYG snapshot** of the live view (dashboard
  CSS under body.light) + full SVG gantt, with an options bar (portrait/landscape/letter/legal/A4) and **Fit-to-1-page
  auto-scale** (transform on #sheet) — Rich asked 3× for 1-pager, don't regress this. Sibling builds (`JFSD - *`)
  group under one family unit in ALL meeting counts.
- **📈 Sales & Planning (20.4–20.6)** — ☰ Menu + Projects header. Committed projects = solid bars; **prospects** =
  purple hatched bars (name/vehicle/scope/est dates/probability %) stored as **`[SALES]`-tagged tasks on 🛠 General**
  (comments carry `[sales]{json}`) → sync via Lists, **hidden from floor** (tile filter + unassigned finder skip
  `isSalesT`). ◀ ▶ nudge a week; **✔ Signed → promote** creates the real project via `addProjectTask` (kickoff task)
  and removes the bar. Exec band (Committed/Prospects/**Expected new builds**=Σpr/**Next PM free**) + PM LOAD strip +
  executive one-page print (`spPrint`, SVG hatch pattern). From Al's 7/10 sync (transcript) + al_planning_for_sales.xlsx.
- **🧩 Sub-jobs (20.7–20.8)** — several jobs share a J# (J1524 trailer + pedestal builds). `[subjob]` tag in job
  **Notes** (checkbox on ➕ Add job / ✎ edit manages it; tag stripped from the textarea, ship-history preserved).
  `jobIsSub()` gates: Fleetio MRA date line, 🔧 issue pill, What's-Next GPS/returns. Card shows 🧩 pill (full
  instructions on hover). ➕ Add job with an existing J# asks: sub-job vs add-tasks-to-existing.
- **🧾 Punch list + 📧 recaps (21.0)** — `buildJobPunch` (✎ edit job → 🧾 Punch list; `?punch=J####`): ONE doc per
  job, ALL crews grouped (PRINT_CREWS + named + UNASSIGNED), WO-style shell, digital-first. `buildFloorRecapHtml`
  (☰ Actions → 📧 Floor recap; `?recap=1&days=N`): closed-in-window w/ who+photos + still-open per job.
  `buildPMReportHtml` (**Megan's ask**; ☰ Actions → 📧 PM report…; `?recap=1&pm=Megan&days=7`): her projects' health
  overview (projHealth/_pmtBehindBits), done last 7d (**last-24h highlighted**), coming due ≤14d (overdue flagged),
  ◆ milestones ≤30d, stat tiles. **Email flows PARKED** — Rich builds them after Megan reviews (3-step clone of
  Doug's 7:15 flow: Recurrence → Send email w/ the link).
- **Fixes:** ⏸ parked bars grey in Project Progress (Al, 19.1); recurring shop tasks 🔁 daily/weekly/monthly via
  `[repeat:…]` tag in Comments + spawnRepeat on close (19.0, Jeff's eyewash PM); design-board subtasks show
  **↳ part of <parent>** + phase chips (19.0); unassigned finder skips **orphan/ghost jobs** (`row 'orphan:*'` /
  category 'pipeline' — e.g. QuidelOrtho Decommission leftovers, 20.9); catalogue got a sortable/filterable **Table
  tab** (Al's ask; edits still cache-only — write-back undecided).
- **⚠ PARKED / TO-DO (hold these):** (1) **at-MRA/away Gantt shading + "no shop work" filter — built but WRONG per
  Rich** (Al wants end-of-project offsite, really just a filter); code dormant, toggle hidden (`.atMraBtn`
  display:none, `ATMRA_SHADE`/`projAwaySegs` remain) — re-scope with Al before touching; (2) scheduled email flows
  for PM report/floor recap; (3) 🧹 ghost-job cleanup admin view; (4) **BOM import** blocked on Rich copying the
  "materials & parts"/BOM files into `SMartsheets projects` (M365 connector can't reach the original project folders);
  (5) catalogue shared-edit write-back (needs a blob-write flow like EOTM, or fold parts into Lists); (6) Al's
  planning-view extras: phase-chunked planning bars, PM capacity hours model; (7) **PROJECT tasks assigned to
  "MRA Shop" should surface in the ⚠ unassigned finder** (production-mtg ask, added 2026-07-14): tag them like
  Fleetio tasks get 🔧 (e.g. 📋 project), assigning one writes back to the project schedule (editProjectTask,
  like the design-board reassign). ⚠ OPEN QUESTION before building: scope window — Medtronic alone has dozens of
  future MRA-Shop tasks; probably only surface those with start/finish ≤ ~14 days out or overdue. Confirm w/ Rich
  (he offered to explain more). (8) at-MRA hatching now HARD-off (rev 21.8) — was stuck on for devices that tried
  the toggle; still awaiting the Al re-scope.
  ✅ CLEARED 2026-07-14 (rev 21.6–21.7): 🧹 ghost-task cleanup screen (☰ Menu; found 16 stale rows day one) ·
  gantt icon legend (🏷/⏸/🧩 w/ hover detail) · ⏱ new-project watchdog (alerts if a dash-created project hasn't
  landed in the Lists after ~40 min — the AWS case) · punch-list ⚠ Issue button (crew note+name → "⚠ ISSUE:" task
  on the same job assigned to the PM, TBD/blank → Rich; works from opener AND ?punch= deep link; hidden on print).
  ⚠ STALE ITEM KILLED: "full-screen Gantt detail-view consistency" was ALREADY SHIPPED as rev 8.2 (2026-06-25) —
  detail slider (Tasks→Phases→Milestones→Summary), arrows up top, ⚙ View menu; verified working 2026-07-14.
- **Gotchas this session:** python heredoc escapes bite (em-dash/quote SyntaxErrors abort BEFORE writing — file
  stays clean, just rerun); JS-string changelog items must escape inner double quotes (`class=\"k\"`); `ejSub` id
  was taken (bring-back banner) → checkboxes are `ajSubJob`/`ejSubJob`; repo's checked-in data.js is a stale June-16
  snapshot — headless tests must curl the LIVE data.js; playwright lives at /opt/node22/lib/node_modules/playwright
  + chromium at /opt/pw-browsers/chromium-1194 (screenshot-verify visual changes, send Rich the PNG).

## Shipped 2026-07-09 — Meeting view · Off-Site/Parts tile · closed-task search · stranded-edit fix · write-in assignees

*(The complete rev-by-rev history is the `CHANGELOG` array in `MRA_Dashboard.html` — the footer badge + "What's new"
modal read it, so it's authoritative. Revs between the last CLAUDE.md log (4.90, 2026-06-22) and rev 17.2 shipped via
that CHANGELOG. This logs the 2026-07-09 session's features + the gotchas worth NOT repeating.)*

### 🗓 Maintenance-Meeting view — "Assign to board" became a live board cross-check (rev 17.4–17.9)
- Every **Coming-back** card cross-checks the shop board by J# at render time (`_mtgJobMatches(u)` — numeric-row,
  non-leave jobs matched on digits-only J#). The button now tells the truth:
  - **already on the board → green `✓ On board · <bay(s)>`** — the badge carries EVERY live bay, deduped, shipped jobs
    excluded (`mjBays`/`mjLive`); click → that job's editor.
  - **split into several jobs** (e.g. 6154 Kentucky J1524 = Maintenance + Pedestal; Ford J1541) → badge lists all bays
    AND **every job is spelled out on the card** (`.mtg-onbl`/`.mtg-onbj`): name — bay · status · dates · open-task count.
    Click a line → `mtgOpenJob(row)`; the badge opens `_mtgJobPick` (picker + ➕ New job for this unit).
  - **not on the board → `🏭 Assign to board`** → `_mtgNewJob(i)` (pre-filled ➕ Add job: name, J#, arrival→leaving, Parking Lot).
- **rev 17.9:** a returning unit whose board job is **shipped** shows **🔄 bring back** on the badge/line/picker entry →
  routes through the existing `bringBackTo(row)` (editor pre-set Active · Parking Lot · today, ship history logged) so it
  can be re-assigned. Also: a HERE-NOW unit with **no Samsara tracker** shows a muted **📡 no GPS** chip (`.mtg-gpsno`)
  instead of nothing — Samsara only tracks ~135 units; client-owned trailers (e.g. **6042 Mott**) have no tracker, so
  don't imply a location can be verified when it can't.
- ‼️ **RICH LESSON (he was blunt, twice):** he scans the **BADGE**, not the lines under it. "· N jobs" counts were
  useless — the badge must carry the actual **locations**, and every job must be **spelled out in full** (name/bay/
  status/dates/tasks) with **no click required**. On this view, never hide load-bearing info behind a click.

### 📦 'Off Site / Parts' tile (rev 17.6) — build-and-ship work for units that AREN'T on site
- New bay value **`Off Site / Parts`** in `BAY_OPTIONS`. Jobs there get their own tile UNDER the General tile
  (auto-hides when empty).
- KEY: **`bayIsParts(b)`** (`/parts/i`) is an EXCEPTION to `bayIsHeld()` — so unlike On Hold / Off-Site, a Parts job's
  tasks **DO feed the crew queues** (the parts work is real shop work even though the unit's away). `isHeldBay` now
  delegates to `bayIsHeld` (one source of truth).
- Use for the JFSD-type case Rich raised: "we're building parts for it and shipping" — unit not here, work still tracked + queued.

### 🔎 Closed-task search from the shop floor (rev 18.0)
- Un-retired the Shop History view — now **menu-only** (no tab): **☰ Actions ▸ 🔎 Search closed / history** in BOTH
  Actions menus (top-bar `#bayPop` + floating `#floorActPop`), plus a footer link in the 🔍 global-search modal.
- `renderHistory()` gained an **Open/Closed-only** task filter (`#histDone`), reads the STRUCTURED task data (`j.tasks`)
  so closed lines show **closed date (`t.cl`) + crew (`t.who`)**, counts closed tasks in the header, and has a
  ← Back to floor button. Search by job #, job name, task wording, client, or person. Read-only (no code needed).

### ⏳ STRANDED-EDIT FIX (rev 18.1) — ‼️ ROOT CAUSE of "I assigned it and it's not showing / won't print"
- **The bug (Siemens DBX J110):** Rich assigned 6 brand-new 🔧 Fleetio tasks, they didn't show, he ran "MRA Lists to
  JSON" 4× — still blank. Cause: assigning a task whose row hasn't synced back yet queues the edit in the **by-id retry
  queue** (`pendRewrite`/`prwRetry`, localStorage `mra_prw`). Those tasks are named `🔧 #NNN …` → the emoji/`#` **can't
  be text-matched** in a SharePoint OData `$filter` (`_odSafe` blocks it), so the ONLY path is **by item-id**, which
  fires on the next refresh **while signed in**. An **idle sign-out** before that → the edits sat INVISIBLE on his
  device, never sent. Running Lists→JSON can't help — the writes never left the browser.
- **Fixes:** (1) `siSubmit()` calls `prwRetry()` immediately on sign-in — flush the queue the moment you authenticate.
  (2) A floating **⏳ "N edits waiting to sync" chip** (`#pendChip`, bottom-left; `updatePendChip()` fired from
  pendRewrite/pendDelete/prwRetry/signOut) shows whenever the queue is non-empty — tap = sign in & send now. Chip gone
  = saved. Hidden on wall/print. (Verified live: the 6 DBX tasks landed — Doug/Vendor/Sal/Sal+Wrap/Sal/Sal.)
- ‼️ **PRINT IS WYSIWYG:** the crew print (`buildCrewSheetHtml`) builds from the SAME in-memory `MRA_DATA`. If an edit
  isn't SAVED (only optimistic-local, or stranded in the queue) it won't print. "Run Lists→JSON to make it print" is a
  misconception — that flow pushes the board OUT to everyone else; it does NOT pull your own unsaved edits in. Saved = prints.

### ✏️ Write-in assignee names (rev 18.2)
- Add-task / Edit-task **Assigned-to** were `<select>` → now free-text `<input list="asgNames">` (shared `#asgNames`
  datalist at body level). `fillAsgNames()` fills it with the 6 crews + every distinct name already on any task
  (auto-learns; refreshed on modal/popover open). Two boxes = team effort (joined " / " via `_combineAssignees`).
- The 👤 quick-assign popover (`qaOpen`) gained a ✏️ type-a-name row (`#qaOther`; Enter or ➤ → `qaGoOther`).
- ⚠️ A typed name shows on the task/card/groups but does NOT get its own crew **column** or **print section** — only the
  six `PRINT_CREWS`/`ASSIGNEE_OPTIONS` crews do. (Told Rich; offered to promote a name to a real column later if wanted.)

### Housekeeping
- Also this session: modals no longer close on backdrop click (global capture-phase guard), Gantt print overhaul,
  hot-task 🔥 highlighting, out-today (reason kept private), bay-card date sort + drag reorder, meeting stay-length +
  Fleetio links + GPS truth-check — all in the CHANGELOG.
- Branch/deploy flow unchanged: dev+deploy on `claude/zealous-fermi-6n5pil`; every HTML change validated (`node --check`
  on each inline `<script>` wrapped in a function), `preview.html` kept as a copy, deploy via `deploy.yml` `mode=live`,
  verified live by polling the footer `rev:"…"`. NOTE: deploys occasionally sit in GitHub's runner queue and get
  cancelled after ~15 min — just re-fire the workflow; it's not a code fault.

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
  - **✅ STREAMLINED 2026-06-26 (Rich): catalogue is now SELF-CONTAINED — no longer loads from the secondary JSON files.**
    The 3 JSONs (247 products / 302 history) + `logo.png` are **embedded directly into `catalogue/index.html`** as
    `window.MRA_CAT_EMBED` (built by a python pass: `jsfor(o)=json.dumps(o).replace('</','<\\/')`); `fetchJsonFile()` now
    returns the embed (no network), the 15-min `setInterval(refreshExternalFiles)` was removed, and the logo is a data URI.
    Page is ~455KB, loads instantly, zero external fetches. The `catalogue/*.json` source files stay in the repo (still
    uploaded, now unused by the HTML) = the editable source of truth. **TO UPDATE the catalogue data later:** edit/replace
    those JSONs (or use the in-page editor's ⬇ download), then RE-EMBED (re-run the python inline pass) and redeploy —
    just dropping a new JSON in the folder no longer changes the live page since the HTML reads the embed.

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


## 📧 Daily task-email routing (Rich confirmed 2026-07-16) — wire when building the per-person email step
Rich CC'd on ALL. ⚠ TWO Jeffs: "Jeff" board column = Jeff Sellers (jsellers@gomra.com); Wrap Team's Jeff = W2 Graphic (jeff@w2graphic.com) — keep separate.
- **Sal** → shopsupport@gomra.com
- **Doug / Maintenance** → dcooley@gomra.com + spearce@gomra.com (Stephanie Pearce, maint coordinator — copied)
- **Electricians** → bec@beyerelectric.com (Chris Beyer, owner, external — email only, no login)
- **Wrap Team / MasterWraps** → masterwraps1@yahoo.com (Chad) + jeff@w2graphic.com (Jeff/W2) — copy both (external)
- **Jeff** → jsellers@gomra.com (Jeff Sellers, shop floor, gomra acct → also My Work)
- **Josh** → jeberhart@gomra.com (Joshua Eberhart, warehousing, gomra acct → also My Work)
- Al Karloff = akarloff@gomra.com (real; NOT al.karloff) · Luciana = luciana.giglio@gomra.com (confirmed).
- **PMs** Al/Megan/Luciana → project report; **Design** Sarah(swilliams)/Mark(markm)/Brandon(bchoy) → their task list.
Content = the per-person "My Work" engine (PM report for PMs, task list for design/crews). Fire in the ~6AM batch with the deficiency email. Emails resolved via the MRA Users list Email column (flow "Get items → Email"), so assignee NAME on the board must match the Users list entry (Steve-K gotcha). Group-crew leads (Beyer/Chad/W2) added as literal recipients in the flow since they're not in the Users list.
