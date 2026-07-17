> ✅ ALL 16 RESOLVED 2026-07-17 — colors→MRA orange, bay-grid drops, shop edit/delete, My Work close + expand, deep-links, dead range buttons, clickable bay name, General tile, crew alias, Fleetio-on-cards, age badge, home hover, project filters, collapse controls. Kept below for reference.

# Command Center — audit follow-ups (paused 2026-07-17)

The new modular board (`command/`) is LIVE but **locked to Rich only** (preview) while these are worked.
A 29-agent adversarial audit against `CC_SPEC.md` confirmed **16 real findings** (of 25 raised).
Fix these when work resumes, then re-run the audit + headless validation + deploy `mode=live`.

Endpoints/patterns are already ported in `command/app.js` (shopWrite/_listOps/_LF/_findId/roles/retry queue).

## HIGH

### command/app.js:92 (data-mapping)
**Problem:** The isOrphan helper (app.js:96) is defined but never applied, so orphan/pipeline ghost jobs are treated as active work and inflate every KPI, crew tally, lane, and the bay grid.

**Fix:** Add the orphan/pipeline exclusion to the two bay/lane model functions that currently guard on isLive only. In bayGridModel() (app.js:240) change `if(!isLive(j)) return;` to `if(!isLive(j) || isOrphan(j)) return;`, and in jobsInBay() (app.js:244) change the predicate to `isLive(j) && !isOrphan(j) && pred(j.bay)`. Also exclude orphan/pipeline in _projJobsFor() (app.js:205) so a pipeline job can't become a project's main job. This matches the live board, which filters `category!=='pipeline' && row.indexOf('orphan:')!==0` in its bay/floor code.

### command/app.js:484 (bells-pages)
**Problem:** Shop tasks have no edit/delete/reopen handle — openEditTaskModal (app.js:577) exists but is never called from any page, so shop-task text/due/comments/status/milestone cannot be changed and a task cannot be deleted from the Shop board.

**Fix:** Wire an ✎ edit affordance into taskLineHtml (app.js ~line 553, next to the 👤 quick-assign chip, gated by !WALL and edit permission) that calls openEditTaskModal(job, t) — e.g. a chip with onclick invoking a small resolver that looks up the job by proj and the task object by raw. Since openEditTaskModal already supports status change (including back to Open = reopen) and its modal already exposes submitDeleteTask, adding the single edit entry point restores edit, delete, and reopen for shop tasks.

### command/pages/tasks.js:32 (bells-pages)
**Problem:** My Work task rows render no ✓ close button, so a signed-in crew member/closer cannot close their own tasks from My Work — breaking the shipped 'log in to close' daily-email flow that deep-links to ?view=mywork.

**Fix:** In tasks.js taskLineInner, render the close chip for open shop tasks (and route project tasks to the verify/close path). Simplest correct fix: reuse the shared app.js taskLineHtml(t, job, {assign:false}) for shop items so the bells (close ✓, Fleetio detail, media, added-by) match by construction; for project items keep the project row but only close via the verify/sendBack path. Critically, because the outer .mwrow div has onclick="mwGo(...)", the close chip's handler must stop propagation (add event.stopPropagation in closeTaskBtn or wrap the closeHandle onclick) or clicking ✓ will also fire mwGo and navigate away instead of closing. Also register window.MRA_PAGES.mywork (or alias 'mywork'->'tasks' in the app.js:730 deep-link resolver) so ?view=mywork from the daily email actually lands on My Work.

### command/app.js:242 (runtime)
**Problem:** bayGridModel() forces every bay into a single Front/Middle/Back trio, so it silently drops live jobs and shows jobs under the wrong physical-position label on Home, Shop and the Floor TV.

**Fix:** Do not force a fixed Front/Middle/Back trio. Group live bay jobs by bay number, then bucket each job under its real bayPosOf(j.bay) into per-position ARRAYS (default '' -> Front), and have home/shop/floor render every job in each position bucket. This preserves each job's true position label and never discards overflow (e.g. multiple Front jobs in one bay).

## MEDIUM

### command/pages/shop.js:56 (bells-pages)
**Problem:** Shop 'Bay Calendar' range buttons (1 Month / 3 Months) are dead: setCal stores CAL and calls drawCal, but drawCal/ganttDates compute the horizon purely from item dates and never read CAL, so the chart never changes.

**Fix:** In drawCal, compute an explicit horizon from CAL (today → today+1mo for 'month', today+3mo for 'quarter') and pass opts.lo/opts.hi (or opts.months) into ganttDates; update ganttDates to honor those bounds instead of the fixed today-7/today+30 auto-fit.

### command/pages/sales.js:34 (bells-pages)
**Problem:** Sales 'Portfolio Gantt' range buttons (3/6/12 Months) are dead: salesRange sets MONTHS_N and re-renders, but ganttDates ignores MONTHS_N so the horizon never changes.

**Fix:** Make the horizon honor MONTHS_N: at sales.js:34 pass `{labelW:200, months:MONTHS_N}`, and in ganttDates (app.js:568) when `opts.months` is set, force `hi = Date.parse(today) + opts.months*30*DAY` (capping/extending the horizon to the selected window; frac() already clamps overflowing bars to [0,1]).

### command/pages/shop.js:20 (bells-pages)
**Problem:** The Shop bay card body/job-name is not clickable despite carrying the 'click' class and a hover outline (styles.css:92) — the root <div class="slot detail click"> has no onclick, so only the small ✎ Edit job button opens the editor.

**Fix:** Add onclick="openJobEditor('${escA(j.row)}')" to the .job name div at command/pages/shop.js:22 (rather than the root card, to avoid double-firing with the inner task/sched lines that have their own openProjectEditor onclicks and do not stopPropagation). This satisfies CC_SPEC.md:433 "Job name -> job editor".

### command/pages/tasks.js:59 (bells-pages)
**Problem:** My Work 'My Projects' rows do not expand to reveal the actual past-due tasks (who · due · phase); they only show the '⚠ N past-due (with …)' summary and click straight to the editor.

**Fix:** In projHtml, give each My Projects row a ▾/▸ caret toggling a per-render expanded set (e.g. MW_PROJ_OPEN), and when open render subrows from `_pmtBehindBits(p).od` (who · due · phase, each with onclick openProjectEditor(p.name)) plus a trailing '✎ Open '+p.name+' editor →' link; keep the collapsed row's '⚠ N past-due (with …)' summary. Add window.mwToggleProj to flip the set and re-render.

### command/pages/projects.js:45 (bells-pages)
**Problem:** Non-official projects are unconditionally filtered out with no 🏷/⏸/🗄 view toggles, so a project flagged nonOfficial can never be viewed/opened on the Command Center, and parked/archived projects have no filter+count controls.

**Fix:** Add a view-filter bar to the Projects page render(): 🏷 hide non-official (default on), ⏸ hide parked, 🗄 show archived — each showing a live count of affected projects — and drive the `projs` filter from those toggle states (persisted per-device) instead of the hardcoded `!p.nonOfficial`, so non-official projects can be surfaced on demand. Build the awaiting-verification scan (line 48) from the UNFILTERED project list (or always include hidden projects' pending-verify tasks) so a non-official project's sign-off tasks still reach its PM.

### command/pages/floor.js:17 (bells-pages)
**Problem:** Floor crew columns are six hard-coded literal names and CREW_ALIAS (app.js:98) omits Doug/Doug Cooley→Maintenance and Steve K→MRA Design, so tasks assigned 'Maintenance', 'Doug Cooley', or 'MRA Design' never appear in any floor crew column, diverging from the live board's alias-merged counts.

**Fix:** In floor.js (and shop.js By-Assignee), match crews like the live board's PRINT_CREWS regex — e.g. resolve each canon name to a lane where the Doug lane = /\bdoug\b|maintenance/i — or extend CREW_ALIAS so 'maintenance' and 'doug cooley' canonicalize to 'Doug' before the byCrew lookup, so Maintenance/Doug Cooley work folds into the Doug column and counts match the live board.

### command/pages/shop.js:15 (bells-pages)
**Problem:** Shop bay tiles have no ⊟/⊞ collapse-all-tasks button and no per-job ▾/▸ caret, so every job's full task list is always fully expanded with no way to collapse (and no remembered state).

**Fix:** In shop.js, wrap each bayCard's `<div class="ctasks">` in a collapsible container and add a per-tile ⊟/⊞ tasks button plus a per-job ▾/▸ caret, backed by a localStorage-persisted per-device Set (mirroring the real board's toggleTileJobs), so bay tiles can collapse/expand their task lists and remember that state across renders and reloads.

### command/pages/shop.js:15 (bells-pages)
**Problem:** Shop bay cards do not list a job's open Fleetio issues with ➕ add / ✓ resolve — only issues already added as 🔧 shop tasks show, so an open Fleetio issue on a floor unit is invisible on that job's Shop card.

**Fix:** In bayCard (command/pages/shop.js), after building `sched`, add a per-job open-Fleetio-issue section: collect from D().fleetio.issues the issues whose normalized J# equals the job's (same digits-only match used by mtBoardJob/fioMraRange), exclude any already represented on the board (a j.tasks row whose _taskFnum matches the issue num), and render each remaining issue as a line showing the 🔧 # + summary + overdue/age badge + fioDetHtml(num) + mediaHtml, with a ➕ button that calls the add-as-shop-task path (the mtAddToBoard logic: shopWrite addTask with task '🔧 #'+num+' '+summary) and a ✓ / Fleetio ↗ (fioHref('issue',num)) resolve affordance.

### command/pages/shop.js:93 (runtime)
**Problem:** Shop renders no General tile and no card for bay-grid-dropped jobs, yet those jobs' open tasks appear in the task lists with dead click-throughs (goShopJob finds no #job-<row> element).

**Fix:** In command/pages/shop.js render(), add a General tile section (mirroring the Off Site/Parts block at line 93) that renders jobsInBay(isGeneralBay) as bayCards — which already emit id="job-${row}" — and auto-hides when empty, so goShopJob('general') resolves. isGeneralBay is already defined in app.js:90.

## LOW

### command/pages/maintenance.js:8 (bells-pages)
**Problem:** Maintenance Open-Issues rows omit the age badge (green <30d / amber 30-90d / red >90d); age is computed (_fioAge) and only shown inside the click-to-open ticket modal, hiding load-bearing staleness info behind a click.

**Fix:** In command/pages/maintenance.js issueRow (line 10), render the already-computed age badge in the row next to the new/overdue badges, e.g. add `${age!=null?ageBadge(age):''}` after the 🆕 new / overdue spans (or in the priority/meta cell), matching what mtTicket does at line 19.

### command/pages/home.js:9 (bells-pages)
**Problem:** Home bay slots do not highlight on hover: they render class 'slot click' but the only slot hover rule is '.slot.detail.click:hover' (styles.css:92), and the '.homeslot:hover' rule (styles.css:91) matches no element.

**Fix:** In styles.css, either change the emitted Home class to `homeslot` in home.js, or (simpler) add `.slot.click:hover` to the highlight selector lists at styles.css:91 and :94 alongside the dead `.homeslot:hover`, e.g. `.slot.click:hover{background:var(--panel2)}` — this covers Home's "slot click" markup without affecting Shop's outline hover.

### command/app.js:677 (bells-pages)
**Problem:** Only ?view=<tab> deep-linking is implemented; ?mywork=<Name>, ?punch=, ?wo=, ?recap=/?pm=, ?fix=1 are ignored, and ?view=floor lands on a blank main area off the live host (floor is an overlay, not a .page section).

**Fix:** In initCC's deep-link block (app.js:729-731): (1) before the ?view lookup, handle the report/person params — if searchParams has mywork, showPage('tasks') and set the selected person; map punch/wo/recap/pm/fix to their nearest page/report state so each lands correctly. (2) Restrict the ?view whitelist to real nav pages (or explicitly exclude 'floor'): e.g. accept v only if document.getElementById(v) is a .page section, and route v==='floor' through openFloor() instead of showPage(). Also harden showPage() to fall back to 'home' when there is no matching .page#name section so a stray ?view=floor can never blank the screen.

