# CLAUDE.md — MRA Shop Floor Dashboard

## ✅ ROOT-CAUSED 2026-09-01 late (rev 37.80) — "my assignments keep coming back unassigned" was an AUTO-CLOSE, not lost assignments

Rich, night before a 5-day vacation, after a full day of re-assigning the same Parking-Lot Fleetio tasks (SMC J1542
+ others): "they keep coming back unassigned... you said you fixed it... causes a cluster fuck with the team because
they don't see them on the board assigned to them." Every earlier fix that day (37.73 reopen-instead-of-duplicate,
37.75 reopen-lands-unassigned, 37.78 confirm-before-reopen, 37.79 Unassigned-finder) treated symptoms. **Read the
live data before answering this time** — that's what found it:
- **The tasks were never unassigned. They were being marked DONE.** Live `data.js`: every 🔧 task on SMC J1542 still
  had its assignee (Doug/Sal), but ALL 14 were `st=Done` — 10 of them `cl=2026-09-01`, i.e. closed that same day —
  while all 12 of their Fleetio issues were STILL OPEN in Fleetio. Board-wide: **39 done-but-Fleetio-open tasks on
  11 jobs, ~25 closed 8/31–9/1**, incl. tasks assigned to **Electricians / Wrap Team (external, no login — can't
  close anything)** and two rows **created unassigned and closed the same day** (FM Global #1399 id 740, ABB #1143
  id 743). No human does that. A Done task (a) drops out of the crew columns → "the team doesn't see it", (b) drops
  out of the card's task list, and (c) under the 8/28 rule ("a Done task no longer suppresses the pill") the card
  re-drew the Fleetio issue as a bare ➕ row with no name → "it came back unassigned" → Rich re-added it → churn.
- **The writer: the Fleetio→board auto-close** (rev 3.8, 2026-06-17; `renderFloor`, the block right after
  `_fleetioTasked`): for every OPEN 🔧 task whose issue number is NOT in `D.fleetio.issues`, it `shopWrite`s a close
  and marks it Done — on any signed-in editor's render, guarded only by `issues.length>0`. "Not in the feed" ≠
  "resolved": (1) `Export-Data.ps1` pulls `issues?q[state_eq]=open` with cursor pagination — a failed page = a
  partial list; (2) an issue in any non-`open` Fleetio state vanishes from it; (3) **the pill's green ✓
  (`fioResolveBtn`) removes the issue from `D.fleetio.issues` locally and `fioApplyResolved` keeps hiding it for up
  to 6h (`mra_fio_resolved_v1`) whether or not Fleetio actually took the resolve** — so one tap of a green check that
  LOOKS like "mark done" made the next render auto-close (and WRITE) that task. Couldn't prove which of the three
  fired on 9/1 (no server log), doesn't matter — all three feed the same block.
- **FIXES SHIPPED (rev 37.80):** (1) `const FLEETIO_AUTOCLOSE_ENABLED=false` (next to `FLEETIO_AUTOCLOSED`) gates the
  block — closing a task is a human action again. Re-enable ONLY on a POSITIVE resolved signal from the export
  (e.g. an exported list of recently-resolved issue numbers), never on absence. (2) Bay card: `fl` split into `fl`
  (no task at all → ➕ rows, unchanged) and `flDone` (newest DONE row per issue #, Fleetio still open → muted
  strikethrough line "done on board · Doug · 9/1 · still open in Fleetio" with **↻** reopen (→ `addFleetioTask`,
  confirm-gated) and the green ✓). Pill reads "🔧 N done · Fleetio open" when only done ones remain. Keeps Rich's
  8/28 "if Fleetio shows it, show it" WITHOUT impersonating unassigned work. (3) `addFleetioTask` matches the
  existing row by ISSUE NUMBER (`🔧\s*#NNN(\D|$)`) — open row wins, else newest done row — and builds the task text
  whitespace-normalized; the reopen payload carries `_id` and `case 'editTask'` now passes it as `__id` so
  `_findId` targets that exact row (dup-safe). **Gotcha behind the #1374/#1375 recurring duplicates:** those two
  Fleetio titles have a TRAILING SPACE (`'Left Axle Front Rim '`, `'Missing Access Door '` — 9 open issues do), so
  the old exact-text `x.t===task` never matched the trimmed row already on the board → a fresh duplicate every ➕.
  (4) `queueAllFleetio` `have` set counts ANY row (open or done) so bulk-add can't mass-reopen. Verified headless
  against the live data: SMC expanded card = 12 ↻ rows / 0 ➕ rows / crew groups intact; Unassigned finder lists 0
  SMC Fleetio items; `addFleetioTask(smc,'1375')` → confirm → `editTask` on `_id 761`; fresh issue → `addTask`;
  0 page errors.
- **✅ DATA REPAIR DONE 10:25 PM — all 34 reopened, VERIFIED 34/34 in the 02:27:45Z export.** Rich's next message
  ("Like the SWC job… all these were assigned as well… go through all the jobs") named SWC IL #907 — one of the
  8 "older" closes (8/22) — as not done, so scope was ALL 34, not just the 26 from 8/31–9/1. Two test writes first
  (id 729 with `"field_7":""`, id 761 with `"field_7":null`) — **BOTH cleared the Closed date** (verified st=Open,
  cl=None, done=False before the batch), then 32 more via `scratchpad/reopen_batch.py` at 1.5s spacing, all 202,
  all landed. Mechanism: `mergeById` on "MRA Shop Tasks" `{"field_5":"Open","field_7":""}`. `build_from_lists`
  sets `done` if Status matches done|complete **OR Closed is non-empty** — clearing `field_7` is REQUIRED. Per job:
  SMC 12 · FM Global J1410 6 · SWC IL 3 · SWC NY1 3 · Cisco Pod 2 · Siemens DBX 2 · General 2 · Post ADLM/Trumpf/
  Mammo Mandy/Ferguson 1 each. Any that were genuinely finished get re-closed by one human ✓ — nothing lost.
  The older SWC IL rows whose issues are NO LONGER open in Fleetio (#1085, #1071, #1070…, 20 of them) were left
  Done — those closes may well have been the auto-close working as designed; no evidence either way.
- **LESSONS (Rich, verbatim, twice tonight): "read the program before you make an assumption" / "hold yourself
  accountable."** Both the watchdog fiasco (below) and this were solved in minutes once the actual code/data was
  read instead of reasoned about. When Rich says something "keeps coming back," pull live `data.js`, dump the
  rows (who/st/done/op/cl/_id) and grep every writer of that field BEFORE proposing anything.

## ✅ FIXED 2026-08-06 (rev 37.0) — Fleetio watchdog "Add to board + assign" button did nothing

Rich, from a real Fleetio issue popup (#1280, Siemens DBX J1110-92 steps): "I'm hitting assign to board, but
nothing's happening. I don't think it works." Reproduced headlessly against the live site/data rather than
guessing — confirmed two real, distinct bugs stacked on top of each other:

- **Root cause of "nothing happens":** every OTHER `👤 Assign` button on the page (`_mcIssRow`, `_mcMinePanelHtml`)
  calls `event.stopPropagation()` before opening the crew-picker popover — except this ONE button, inside the
  Fleetio-issue detail modal (`mcIss()`). Without it, the click bubbles up to a page-wide "click outside closes
  the popover" listener on `document`, which fires for that SAME click (since the listener sees the event on its
  way up, after `qaOpen()` already added the `.show` class moments earlier in the same tick) — closing the
  popover the instant it opens. Net effect: tap the button, see nothing, because the popup opens and closes
  faster than a repaint. **Fixed**: added the missing `event.stopPropagation();`, matching every other call site.
- **Second, related bug found while tracing it**: `_mcIssJob()` (matches a Fleetio issue to its board job) had a
  broken fallback — its asset-digit check compared the issue's OWN job-number digits against the issue's OWN
  asset text (neither side referenced the candidate job `j` at all), so the condition was either always-true or
  always-false for a given issue regardless of which job was being tested. In practice this meant: whenever the
  real matching job wasn't found by exact job-number (e.g. because it's since shipped and got filtered out of the
  "active" set — exactly issue #1280's case, Siemens DBX J1110-92 shipped), the broken fallback would grab the
  FIRST job in the filtered list, unrelated or not, and silently attach the issue there instead of correctly
  falling back to the 🛠 General list. **Fixed**: the fallback now correctly checks the asset text against each
  CANDIDATE job's own digits (`nj(j.jobNum)`), matching the already-correct pattern used elsewhere
  (`queueAllFleetio`, the Fleetio-tab job matcher at ~line 13434).
- Verified headless against the real live issue #1280 both before and after: before the fix, `_mcIssJob('1280')`
  returned the WRONG job ("Post ADLM Inventory Storage") and the popover never showed (`display:none` after a
  real Playwright click); after the fix, `_mcIssJob('1280')` correctly returns `null` (its real job shipped) and
  the popover opens correctly (`display:flex`, visible rect), falling back to 🛠 General as intended.
- ⚠️ Not yet confirmed by Rich on his actual device — ask him to retry assigning a Fleetio issue from My Work and
  confirm it now works before considering this fully closed.

## ✅ FIXED 2026-08-06 — My Work "Questions for you" had no source link (3 of 4 sections did)

Rich, looking at a real question on his phone: "How do I see where this is coming from... didn't we ask that
for every section?" Checked the actual rendering code for all 4 My Work brief sections — he was right, but the
gap was narrower than he thought: **Waiting on you** (📧 Open email), **Appointments** (small 📧 icon), and
**Teams messages** (💬 Open chat) all already use the `_mcMailHref()` helper to show a real link back to the
source when the brief item carries a `link` field. **Questions for you** was the one section that never got
this — no link field in its schema, no button in its render code, nothing.

- **Fixed**: added the same 🔗 Source link to the Questions panel, reusing `_mcMailHref()` — no new mechanism,
  just applying the existing one consistently.
- ⚠️ **Existing questions won't show a link** — they were built before this fix and their source id/link was
  never captured, so there's nothing to link to. Not a bug, just predates the fix; new questions going forward
  will carry it once the routine change below is saved.
- **Also true for Waiting/Appointments right now**: the code has always supported `x.link`, but the recurring
  refresh routine's instructions only ever told it to capture `id` (a raw Graph message id) for those two
  sections, never the actual clickable `link` (webLink). So even though the code path is real, it's likely been
  rendering empty for those too. Gave Rich an updated Routine instructions block (superseding the projectMail
  one from earlier today) adding `link` capture to questions/waiting/appts.
- **Inbound this week** has no link mechanism at all (code or schema) — flagged as a known remaining gap, not
  fixed yet; asked Rich whether he wants it too before building it (inbound items are shipment/tracking info,
  less clearly "one single source message" than the other three).

## ✅ SHIPPED 2026-08-05 — Time Tracking: separate "Time Trends" report for Monthly / All-time ranges

Rich sent 2 screenshots of the Finance report with "All time" selected: "the formatting is screwed... we
don't really need to see the time cards in these formats. We were looking for trends over time and charts
and graphs." Root cause: `buildFinanceReport()` in `time/index.html` always built the "Weekly Time Summary"
format — a day-by-day grid PER WEEK, stacked one block after another. Fine for This week/Last week (1 block),
tolerable for This month (~4-5 blocks), but unreadable for All time (his real data spans June–August, 9+ weeks
→ 9+ stacked grids, no big-picture read at all).

- **Fix, not a patch on the same report**: `buildFinanceReport()` now branches — if `$('fRange').value` is
  `'m'` or `'all'`, it calls a new `buildTimeTrendsReport(rows, rangeLbl)` instead of building the weekly grid.
  This week/Last week are completely unchanged (verified byte-for-byte behavior — same function, same code path).
- **New report, chart-first, no grid**: masthead+stat-tile header (same visual language, reused INK/MUT/BRAND
  design tokens from the Airy redesign) → **Hours by week** bar chart (chronological, reads as a real trend
  over time) → **Hours by month** bar chart (only shown when the range spans 2+ calendar months) → **Hours by
  job** → **Hours by person**. All four are simple CSS bar-rows (same pattern already used for job-code totals
  in the weekly report) — no chart library, no day-by-day grid anywhere.
- **Button adapts automatically** (`updateFinBtnLabel()`, called from `renderTracking()` on every range
  change): the single 📊/📈 button relabels itself "📊 Finance report" for This week/Last week, "📈 Time
  trends" for This month/All time, with a matching tooltip — so Rich sees which report he'll get before
  clicking, no need for a second button.
- Verified headless against a synthetic 9-week/4-job/6-person dataset: button label switches correctly across
  all 4 range options; the All-time print shows all 4 chart sections with correct totals and explicitly does
  NOT contain the "Hours by employee and day" grid header; the This-week print still produces byte-equivalent
  Weekly Time Summary output (job code totals + day-by-day grid), confirming zero regression on the
  recently-shipped Airy design. Screenshots of both reports eyeballed before shipping.

## ✅ SETTLED 2026-08-05 (rev 36.96) — Quote Generator customer format, FINAL: one intro paragraph + plain priced list

Three quick round-trips after 36.93 shipped, each based on Rich actually looking at the real AWS quote render:
- 36.94: dropped ALL per-section text (title + price only) — Rich: "you can't just have the bowl [bold]
  statements... we had like the scope of work before" — too far, it read like a bare price list.
- 36.95: put the per-section description back (cleaned of internal notes) — Rich: "no this is not what I want...
  generally we would have a one line on top of everything with a generic statement of work not underneath each
  individual one" — wrong shape: description belongs ONCE at the top, not repeated under every section.
- 36.96 (this one, confirmed with Rich BEFORE shipping — he said "yes that sounds correct"): the existing
  **Work description** box (already in the form, previously hidden whenever any category was used) now always
  prints as ONE general intro paragraph above the section list. Each section goes back to bold title + price
  only. Removed the now-dead `_qCustClean`/`.q-secbody` from the 36.94/36.95 attempts.
- **This is the real, final format** — don't re-litigate it without Rich raising it again. Layout: Scope of Work
  header → one intro paragraph (from Work description, blank if he hasn't typed one) → bold-title/price row per
  category → Scope of Work Subtotal (if >1 section) → the usual all-inclusive Total box.
- Verified against the real AWS quote both with and without an intro paragraph filled in; confirmed the
  section list still ties to the same $54,485.25 subtotal / $57,754.36 total throughout all 4 iterations.

## ✅ FIXED 2026-08-05 (rev 36.94) — Customer quote sections were leaking internal line-item notes

Same-day follow-up to rev 36.93 below. Rich, after I applied real categories to his live AWS quote: "just
remember for the customer quote we just need the bold statement only not all the details." Real bug behind
the ask — the grouped sections were printing each category's underlying line-item **descriptions** too (not
just title+price), and some of those real line items carry internal-only annotations (`⚠ PLACEHOLDER — swap
for Chad's actual quote + markup once confirmed`, `⚠ TBD — awaiting Monday surface inspection; likely Chad,
possibly Sarah`) — meaning a document meant for the customer could leak internal notes verbatim. Fixed:
`_qCustomerHtml`'s section rows now render ONLY the bold category title + its summed price — no description
line at all. The full itemized detail (including those internal annotations, appropriately) stays exactly
where it belongs: the Detailed/internal print. Removed the now-unused `.q-secbody` CSS. Verified against the
real AWS quote render — clean 6-line "title — $price" list, same $57,754.36 total, no leaked internal text.

## ✅ REDESIGNED 2026-08-05 (rev 36.93) — Quote Generator priced sections now derive from Labor/Materials, not a separate editor

Rich pushed back HARD on the rev 36.91 design (screenshots + blunt feedback): "Your detailed quote under normal
state breaks out labor and materials automatically. I don't want to fucking type anything in, but I want the
ability to tweak it. So you should automatically do this just like you do on the detailed quote... You have all
the data already. I don't understand why you're making me type it again." He was right — the 36.91 design made
him re-type the whole scope into a SEPARATE title/description/price editor even though his real Labor line
items + Material line items (which he'd already built, 15+17 of them on the real AWS quote) already carried
every dollar amount. Full rework, not a patch:

- **Removed entirely**: the standalone `QUOTE.scopeSections` array + its editor (`qAddSection`/`qDelSection`/
  `qToggleScopeMode`), the `QUOTE.scopePriced` toggle checkbox, and the paragraph-auto-split machinery
  (`_qSplitScopeBlocks`/`_qLooksLikeScopeHeader`) built for it in rev 36.91/36.92 — all dead weight once the
  mechanism changed; none of it shipped to real users beyond Rich's own same-day testing.
- **New mechanism**: every Labor line and every Material line gets one new optional field, **Category** (a
  small text input with `<datalist>` autocomplete pulling from categories already used elsewhere in the same
  quote — type it once, click-select it after that). `_qCatGroups()` groups `lines`+`mats` by trimmed category
  name and sums each group's `amt`/`line` (post-markup) automatically. `_qCompute()`'s `sections` array is
  fully DERIVED — `{title, price, body}` per category, `body` auto-built by joining that category's own line
  descriptions (zero separate typing for the description either). **Critically: `subtotal` stays exactly
  `laborTotal+matsLine+consLine`, unchanged from before this feature ever existed** — categories only REGROUP
  money already counted, they never add a second charge on top (this was the actual root cause of the "$0.00
  Scope item / total doesn't match" complaint in the prior design, where sections were a separate additive
  bucket).
- **No toggle, fully automatic**: if zero lines have a category, the customer quote renders exactly like the
  original plain single-paragraph "Work description" always has (verified byte-identical, no `q-secrow` HTML
  present at all). The moment ANY line has a category, the customer quote automatically switches to the
  grouped, priced view — no checkbox to remember. Uncategorized lines/materials (if some lines ARE
  categorized but others aren't) fall into an honest **"Other work"** section rather than silently vanishing
  from the customer's total; nonzero Shop Supplies gets its own section the same way.
- **Internal breakdown** (`_qDetailHtml`) gets a small "By category" reference block right at the top, clearly
  labeled "(this is how the customer quote will group it — same money as the Labor/Materials rows below, just
  regrouped)" so Rich can eyeball the split before printing without it reading as a second charge.
- Verified headless against a representative reconstruction of Rich's real AWS quote (7 labor + 5 material
  lines spanning Interior Flooring Replacement / Graphic Updates / AV and Display Upgrades / General
  Maintenance and Repairs + 2 intentionally uncategorized lines): all 4 named sections + "Other work" grouped
  and summed correctly, `sectionsTotal === subtotal` exactly (no double-counting), and the zero-category
  fallback case renders identically to pre-feature behavior. Screenshot of both the customer print and the
  actual editor form (category fields visible + working, datalist populated) eyeballed before shipping.
- ⚠️ **Migration note for Rich's real in-progress AWS quote**: since categories are new information that can't
  be inferred from his existing line-item text with certainty, his already-built 15 labor + 17 material lines
  will show the plain-paragraph fallback (empty, since he never used the Work description box either) until he
  goes through and tags the relevant lines with a Category — same ~5 categories from his original screenshot.
  This is a one-time, per-line tag (autocomplete makes repeats fast), not a re-typing of the scope narrative.
- **Actually done, same session** (Rich: "so you can't do that for me"): fetched the LIVE `quotes.json`, found
  his real AWS Revamp record (`qmsggczmx`), and hand-categorized all 15 labor + 15 material lines (only 15
  material lines actually existed, not 17) by matching each description to his original 5 scope headers —
  2 lines (`PM & Coordination`, `Mounting hardware/fasteners/misc`) didn't clearly fit any category and were
  deliberately left untagged so they land honestly in the auto-generated "Other work" bucket rather than being
  force-fit. Wrote it back through the same "MRA Quote Write" flow used elsewhere, verified by re-fetching, and
  rendered the actual customer print to confirm: 6 sections, `$54,485.25` sections subtotal ties exactly to the
  pre-existing Labor+Materials subtotal, same `$57,754.36` grand total as before (no double-counting).
  ⚠️ Told Rich to reload his own browser tab before further edits — his open session's in-memory `QUOTE` predates
  this server-side change and autosave would otherwise overwrite it with the uncategorized version.

## ✅ FIXED 2026-08-05 (rev 36.92) — Quote Generator: phantom autosaves + broken header/body auto-split

Two real bugs found within hours of shipping rev 36.91 (below), both from Rich actually using it live.

- **"These 2 keep coming back. not sure. the untitled. bug?"** — Rich saw two saved-quote cards titled
  "Untitled", $1,017.60, "today", in the shared quote store. Root cause confirmed by the exact math:
  8 hrs × the $120 default rate + 6% tax = **$1,017.60 exactly** — the untouched DEFAULT filler labor line
  every new quote starts with. `_qHasContent()`'s autosave guard was counting that line's `hours:8` as "real
  content" (added there to match the old manual-Save guard's behavior) — but with autosave, that meant just
  **opening** the Quote Generator (never typing anything) silently saved a blank quote 1.5s later, every
  time. Fixed: a labor line only counts if it has a real description (`l.d`), not just leftover default hours.
  **Cleaned up the 2 live phantom records** directly in the shared `quotes.json` (fetched it, removed the two
  blank-cust/blank-proj/$1,017.60 rows by id, POSTed the cleaned array back through the same "MRA Quote
  Write" flow the dashboard itself uses) — verified by re-fetching, 8 real quotes remain, 0 blank ones.
  Verified the fix headless: opening the Quote Generator and waiting past the autosave debounce with zero
  typing now saves nothing.
- **Auto-split was pairing headers with the WRONG text.** When rev 36.91 shipped, turning on 🧩 priced
  sections auto-split the existing plain-paragraph scope by blank lines — but a real scope paragraph has a
  blank line **between a header and its own body text too** (not just between sections), so the naive split
  put each header in its own section with an empty body, and its actual description became a separate,
  bogus "section" of its own. Fixed with a two-pass split (`_qLooksLikeScopeHeader`): a block counts as a
  header only if it's a single short line (≤70 chars) with no ending punctuation — then it's paired with the
  block that immediately follows as its body. Verified against Rich's exact real AWS scope text (5 sections:
  Interior Flooring Replacement / Graphic Updates / Welding Equipment Area Reconfiguration / AV and Display
  Upgrades / General Maintenance and Repairs) — all 5 headers now pair with their correct body text.

## ✅ SHIPPED 2026-08-05 (rev 36.91) — Quote Generator: priced scope sections + autosave

Rich sent a real customer quote (American Welding Society / "AWS Revamp") as a screenshot and asked for a
price next to each scope subsection (Interior Flooring Replacement, Graphic Updates, Welding Equipment Area
Reconfiguration, AV and Display Upgrades, General Maintenance and Repairs) — "make it professional and make
it selectable to turn on and off this feature." Mid-turn he also asked, separately, for the Quote Generator
to autosave so he doesn't have to hit Save.

- **New per-quote toggle**: `QUOTE.scopePriced` (off by default — nothing changes for existing/legacy quotes).
  Off = the same single free-text "Work description" paragraph as always. On = the Work-description box
  becomes a repeatable **section editor** (title + description + its own $ price per section, same ＋Add/✕
  pattern as the existing Labor/Materials line-item editors). `QUOTE.scopeSections=[{title,body,price}]`.
- **Money math**: each section's price is a real contribution to the quote total (`_qCompute()`'s
  `sectionsTotal`, folded into `subtotal` before tax) — NOT just cosmetic. Toggle off = zero contribution,
  identical to before. The internal breakdown (`_qDetailHtml`) gets a matching "Scope of Work (priced
  sections)" bucket + subtotal line, same convention as Labor/Materials/Supplies.
- **Customer-facing print** (`_qCustomerHtml`): each section renders as its own row — bold title + price on
  the same line, description below in muted text, thin divider between sections, and (when there's more than
  one) a bold "Scope of Work Subtotal" row — then the same all-inclusive Total box as always underneath.
  New CSS: `.q-secrow/.q-sectop/.q-secprice/.q-secbody/.q-secsub`.
- **Autosave**: quotes now save themselves ~1.5s after the last keystroke (`_qScheduleAutosave`/
  `_qAutoSaveNow`), upserting the SAME saved record by a persistent `QUOTE.id` instead of creating a new row
  every time (the old `qSaveQuote()` always inserted a fresh id — harmless when only triggered by a manual
  click, but would have flooded the shared `quotes.json` store with near-duplicate rows once wired to fire
  automatically on every edit). `qNewQuote()`/`qLoadQuote()`/`closeQuote()` all flush any pending autosave
  FIRST so a just-typed edit within the last 1.5s is never lost when switching quotes. The 💾 button still
  works — it's now just a "force it right now" shortcut, not required.
- Verified headless (Playwright, live-URL POST blocked via route-abort so the test never touched the real
  shared `quotes.json`): toggle-on creates a default empty section, ＋Add section works, internal breakdown
  shows the correct summed subtotal, autosave fires and upserts (not duplicates — confirmed same id across
  two edits 1.5s apart), and the printed customer HTML shows both section titles/prices/subtotal correctly.
  Also regression-checked the toggle-OFF path renders byte-identical to the pre-existing plain-paragraph
  behavior (no `q-secrow`/subtotal leaking in). Screenshot of the rendered print eyeballed before shipping.

## ✅ SHIPPED 2026-08-04 — Weekly Time Summary rebuilt to Claude Design + real InfoWheels 3D scan wired in (Builder rev 2)

Two separate pieces of work from the same session, both live.

- **Time Tracking finance report → Claude Design "Airy" direction.** Rich sent a full design handoff
  (spec doc + two HTML directions, Dense/Airy) from a Claude Design session; picked Airy. Rebuilt
  `buildFinanceReport()` in `time/index.html` to match the design tokens/layout exactly (name-rail
  employee cards, job-code bars, tabular figures, Called-In exception tinting+badge) while keeping the
  SAME data-reconciliation logic (job totals, week totals, per-job breakdowns, grand total all still
  tie out — only the presentation changed). **First pass had a real bug**: kept the OLD alphabetical
  sort on the job-code-totals section instead of the design's explicit "sorted desc by total" rule —
  Rich caught it ("didn't follow claude design, font etc") by comparing screenshots; per-row styling was
  actually pixel-identical to the reference (verified computed colors: exception cell `#FBF1EE` bg /
  `#C1401F` text, byte-for-byte spec match), the sort order was the real divergence. Fixed + redeployed.
  Verified headless against real seeded data + synthetic Called-In and multi-week test cases before each ship.
- **InfoWheels 3D Builder rev 2 — a real CAD scan finally landed.** Brandon exported the actual model
  (asked for a smaller export after the first 2.6GB attempt was unusable; his "half size" pass was
  still 461MB — floor for what Rhino's ReduceMesh could do without visibly losing detail). Got it off
  his machine via a purpose-built transfer path (see below), then **decimated it myself**: `open3d`
  quadric-edge-collapse in a Python venv, 2.78M → 150,000 triangles, **461MB → 17MB**. Wired it into
  `builder/index.html` as a **"🔍 Real 3D scan (beta)"** toggle alongside the existing Rev 1 procedural
  placeholder van (kept, not replaced — see why below). Committed as `builder/infowheels.obj`
  (17MB in-repo, `no-cache, must-revalidate` on its deploy step — deliberately NOT a long/immutable
  cache given the exact "new logo not showing" caching bug documented elsewhere in this file).
  - **Why a toggle, not a replacement**: the raw export has NO group/object separation (`grep "^g \|^o "`
    → zero matches) and only ONE material (`usemtl Default` × 1716, all pointing at the same material) —
    it's one fused mesh, not separate shell/cabinet/floor parts. So it can't support the existing
    per-part customization (accent color, floor/wall finish, cabinet slots) without Brandon/Mark
    re-exporting with real named groups — a different, future ask. Rev 2 disables (greys out,
    `pointer-events:none`) those controls while the scan is active, keeps wrap-color live-tinting the
    whole mesh (`applyWrap()` updates `scanMesh.material.color` too), and disables the Interior toggle
    (no separate interior geometry to show). The procedural van is UNCHANGED and still the default.
  - **Real bug hit + fixed during headless verification**: the scan loaded but the viewport was blank —
    root cause was the raw OBJ being in **millimeters** while the scene (built for the procedural van)
    uses **meters** with a fixed fog range (18–40 units) tuned for that scale. The unscaled scan's
    ~9000-unit bounding box put the camera thousands of units past the fog falloff → fully swallowed
    into the background color, not actually invisible/broken, just fogged out. Fixed with a single
    `geo.scale(.001,.001,.001)` on load. Caught this BEFORE shipping via headless Playwright + screenshot
    verification (WebGL via `--use-gl=swiftshader`) — a blank canvas with zero console errors doesn't
    mean it works, always screenshot 3D output, don't trust "no errors" alone.
  - Loaded lazily on first toggle (not on page boot) since it's a genuine 17MB download, absolute-path
    fetch (`/builder/infowheels.obj`) since this same HTML is ALSO published at root `/builder.html` —
    a relative fetch would resolve wrong from that copy.
  - **Large-file transfer mechanism (reusable for next time Brandon has a big export):** chat/email
    upload has a hard ceiling well under 100MB (confirmed twice — a 2.6GB and then a 472MB `.obj` both
    silently failed, only their tiny `.mtl` sidecar came through). Built `upload3d.html` (self-contained
    drag-and-drop page, chunked Put Block + Put Block List straight to Azure Blob REST, no server) +
    a new `objsas` mode in `deploy.yml` that mints a short-lived (3-day) write-scoped SAS for the
    existing private `pipeline` container + sets CORS so a browser can talk to blob storage directly.
    Verified the block-upload mechanics myself with a real test blob (small file, PUT block ×2 + PUT
    blocklist, GET back to confirm byte-exact reassembly) before ever handing the link to Brandon.
    ⚠️ Test blob cleanup attempt failed (403 — SAS token is `racwl`, no delete permission by design);
    harmless leftover, needs a manual delete or will fall out of any future container cleanup.

## ⚠️ 2026-08-04 — `deleteTime` is CONFIRMED STILL NOT BUILT (a stale code comment said otherwise — don't trust it)

Rich asked to clear out old test entries from Time Tracking (keep last week + this week, delete everything
older — 156 test rows from 6/29–7/23, keep 42 real rows from 7/27 on). Before touching real payroll data,
went to verify `delEntry()`'s server-side delete actually works, since `time/index.html` had a comment
claiming a "real deleteTime branch" was built + verified 2026-07-30 — **that comment was wrong.**
- **Proof, not a guess**: added a safe throwaway entry (`claudetest1785840800verify`, "ZZ Test QA Ignore",
  0.1 hr), confirmed via `time.json` that it landed for real in the **MRA Time Entries** SharePoint list
  (ID 219). POSTed `{action:'deleteTime', id:...}` to the same `TIME_WRITE_URL` `delEntry()` uses — got
  HTTP 202 (accepted) like every no-cors POST here. Watched `time.json` rebuild itself **over an hour
  later** (its own Last-Modified header moved forward, confirming the rebuild flow is NOT stalled/hung —
  this is not the recurring "DATA PIPELINE STALLED" issue) — and the test row was still sitting there,
  completely untouched: **`Created` and `Modified` timestamps identical**, meaning nothing on the flow
  side ever acted on it. The POST is accepted by the trigger; nothing downstream handles `action=='deleteTime'`.
- **This matches the ORIGINAL 2026-07-30 caveat below** ("the `deleteTime` branch ... still needs to be
  built") — that was correct and never actually got resolved, despite a later code comment in
  `time/index.html` (removed this session) asserting it had been fixed and verified "same as the edit fix."
  Don't trust in-code comments claiming a flow branch works — if in doubt, re-run the safe-throwaway-entry
  test before relying on it, exactly like this.
- **Fixed this session**: corrected the misleading comment + softened `delEntry()`'s confirm() dialog so a
  manager clicking delete isn't told the row is "removed from SharePoint for good" when it isn't — it now
  says plainly that the SharePoint-side delete isn't wired up yet and the row will reappear on refresh.
- ⚠️ **Leftover test row NOT cleaned up**: `claudetest1785840800verify` / "ZZ Test QA Ignore" / 0.1 hr /
  2026-08-04 is still sitting in the live **MRA Time Entries** list (ID 219 as of this session) — harmless
  (tiny, obviously fake, dated today) but needs a manual SharePoint delete, or will get swept up naturally
  once the real `deleteTime` branch exists and the bulk cleanup below finally runs.
- **Rich's actual ask (clear pre-7/27 test hours) is BLOCKED on this** — cannot bulk-delete 156 real rows
  through a mechanism just proven not to reach SharePoint. Next step: build the `deleteTime` branch in
  "MRA Time Write" (Condition `action=='deleteTime'` → Get items filter `EntryID eq '<id>'` → Delete item —
  identical shape to the `editTime` branch already built below), verify with the SAME safe-throwaway-entry
  test, THEN run the bulk cleanup.
- **Real, unrelated bug found + fixed in passing**: a manager's own newly-added time entry didn't show up
  in "Your week" / Tracked hours until the next shared sync, because `submit()` only pushed the new entry
  into the local `ENTS` array — but a signed-in manager's view reads `activeEntries()` = the synced
  `SHARED` array once loaded, which `submit()` never touched (unlike edit/delete, which already mutate
  `SHARED` directly). Fixed: `submit()` now pushes into `SHARED` too when it's loaded, so adds show up
  immediately for managers exactly like they always did for plain employee kiosks.

## ✅ FIXED 2026-08-04 — Logo update round 2: the MRA_LOGO constant + Quote Generator had NO image at all

Follow-up to "🎨 Updated MRA logo everywhere" (rev 36.82) and the caching fix (rev 36.83) below. Rich swapped in a
new logo (adds the "mobile.experiential" wordmark, transparent background) and asked for it "everywhere — all
reports, quotes, prints, etc." Round 1 swapped `logo.png` + `catalogue/logo.png`. Round 2 (36.83) fixed a real bug —
the `logo.png` deploy step had no cache-control header, so browsers held the old cached copy forever — but even
after that was confirmed fixed via curl (correct header, correct fresh bytes), **Rich sent screenshots proving a
real Work Order print and a real Quote Generator print still showed the wrong/no logo.** Lesson: byte-level/header
checks are not the same as tracing every render path — don't repeat that gap.
- **Root cause found**: there is a SEPARATE, standalone embedded copy of the logo — `const MRA_LOGO =
  "data:image/png;base64,…"` (search that exact string to find it) — completely independent of the `logo.png`
  file. It's the ONLY logo source for: `buildWorkOrders` (Maintenance Work Order print), the Job Punch List print,
  and all 3 "Hard-Date Schedule" customer-PDF print layouts. Swapping `logo.png` does nothing for any of these —
  `MRA_LOGO`'s payload has to be edited directly (find the closing `"` after the marker, replace the whole base64
  string with the new file's base64).
- **The Quote Generator letterhead had NO image at all** — it was 100% CSS-styled text (`<span class="mra">MRA</span>`
  + the rest of the company name in a big bold font, no `<img>` anywhere). "Update the logo" could never make that
  surface change because there was nothing to update — it had to be converted to actually render an `<img
  src="'+MRA_LOGO+'">` first. Fixed (`_qCustomerHtml`, the `head` var) + added `.lh-logo{height:44px;width:auto}` CSS.
- **Fixed 2026-08-04** (rev 36.85): `MRA_LOGO`'s base64 swapped to the current logo; Quote Generator now renders a
  real image. **Verified by actually rendering the pages**, not just checking bytes: local headless run against a
  copy of the LIVE `data.js` — `openQuote()`+`quoteCustomer()` and `printWorkOrders(PRINT_CREWS,{})` (28 real work
  orders) — screenshotted, confirmed `naturalWidth/naturalHeight` matched the new file (318×360) and the image
  `complete` (no broken-image icon) on both. Zero page errors. Then deployed live and re-confirmed via curl.
- ⚠️ **Note for later, not yet acted on**: the new logo's "mobile.experiential" wordmark sits below the orange
  square in the file, but every surface that shows the logo (dashboard header, all report letterheads, Work Orders,
  Quote Generator) displays it at a small compact-badge height (34–48px, unchanged from before — that's how big the
  OLD square-only logo always was there). At that height the wordmark shrinks to a few px and is essentially
  illegible (confirmed by zooming into a screenshot — it's there, just unreadable). This was never flagged by Rich
  as a problem; flagging it here in case he wants specific spots enlarged so the wordmark actually reads — don't
  silently resize things across the app without asking, it touches a lot of layouts at once.
- **`preview.html` gap found while chasing this**: it's a genuinely stale, unsynced snapshot — **it has no Quote
  Generator at all** (0 occurrences of `quoteCustomer`/`openQuote`/`_qCustomerHtml`), ~3000 lines behind
  `MRA_Dashboard.html`. Its `MRA_LOGO` copy was still swapped to the current logo for consistency (rev bump not
  applicable — preview.html doesn't carry the CHANGELOG rev), but there was no letterhead-image gap to fix there
  since the feature itself doesn't exist in that file. Don't assume preview.html mirrors MRA_Dashboard.html for any
  feature added since whenever it was last synced — check before relying on it to represent what's live.
- **If the logo changes again**: check `logo.png`, `catalogue/logo.png`, catalogue's OWN embedded base64 (separate
  from the file, inside `catalogue/index.html`), AND `MRA_LOGO` in `MRA_Dashboard.html` — four independent places,
  not one. Grep for `data:image/png;base64` in each file to find embedded copies before declaring "done."

## ✅ FIXED 2026-07-30 — Time Tracking: real edit/delete, job-picker double-prefix bug, 0-hr Called In tile

Follow-up to the "duplicated payroll rows" incident below — this is where that got actually fixed, plus two
more bugs Rich caught live the same day.

- **Real `editTime` branch built + VERIFIED.** "MRA Time Write" now has a genuine edit path: Condition
  (`action=='editTime'`) → Get items (SharePoint, filter `EntryID eq '<id>'`) → Update item (`PatchItem`,
  `Id` = `first(body('Get_items'))?['ID']`, straight quotes in the filter, body parsed via
  `json(triggerBody())?['field']` same as every other no-cors flow here). Tested end-to-end with a safe
  throwaway entry (`claudetest1785444436`, "ZZ Test QA Ignore") before touching anything real: `addTime` →
  confirmed landed → `editTime` → confirmed the SAME row updated (Hours 1→2, no duplicate). `time/index.html`
  `saveEditEntry()` now sends the real POST again (previously local-device-only per the incident below).
  **Real correction made same day**: Brian Glenn's and Kayla Roe's 7/30/26 Airstream entries (both showing
  4 hrs) corrected for real to 7 and 5 hrs respectively via this mechanism — confirmed same row updated, no
  duplicate created.
- **Delete function added** (Rich: "give me a delete function here so i dont have to go to the list").
  `delEntry()` in `time/index.html` now POSTs `{action:'deleteTime', id}` to the same flow and the 🗑/×
  button is wired up on both the manager Tracking view and "Your week". ⚠️ **The `deleteTime` branch in
  "MRA Time Write" still needs to be built** (Get items by EntryID → Delete item, same shape as editTime) —
  until that exists, clicking delete removes the row from the current view/device but the row is NOT
  actually removed from SharePoint and will reappear on the next shared refresh. Build + test the same way
  editTime was (safe throwaway entry first) before relying on it for a real row.
- **Job-picker double-prefix bug fixed** (Rich caught it live: "look how J1110 is written. looks wrong" —
  screenshot showed "1110 · 92 · 92 · Siemens DBX J1110-92"). Root cause: `jobListItems()` regex-stripped
  the job-number prefix back off a label that `boardJobs()` had just built, to recover the bare project name
  — but the regex (`\d{3,6}` then one separator char) can't span a **hyphenated job number** like `1110-92`;
  it only eats `J1110-`, leaving a stray `92 ·` fragment that then gets prepended again. Any board job whose
  `jobNum` contains a hyphen (sub-unit numbering, e.g. trailer 92 within job family 1110) hit this. **Fixed**:
  `boardJobs()` now returns the raw `project` name directly (`name:j.project`) so `jobListItems()` doesn't
  need to regex-strip anything back off. Verified via a Node sandbox reproducing the exact case — old code
  produced `"1110-92 · 92 · 92 · Siemens DBX J1110-92"`, new code produces the correct
  `"1110-92 · 92 · Siemens DBX J1110-92"` (job code · unit number · description, no duplication).
- **"Called In" 0-hour stat tile removed** (Rich: "remove this called in up top pls" — Finance Report header
  showed a `CALLED IN 0.00` tile). `payChips` in `buildFinanceReport()` rendered one tile per PayType present
  in the range with no floor — Called In is a 0-hour flag by design (see the earlier "0-hours time entry"
  feature), so it always showed a useless 0.00 tile. Fixed: tiles only render for pay types with hours > 0
  (Leave/Sick/etc. with real hours still show correctly).

## ✅ FIXED 2026-07-30 — SHOP-task attachments silently dropped by Move/Copy and drag-to-another-trailer

Rich clarified his attachment complaint was about the **shop floor screen specifically** (shop tasks), not
the project Gantt (see the entry right below — that was a real bug too, found first, but not the one he
meant). Shop-task attachments live in their own **Files column** (not a comments tag like project tasks),
written by a dedicated `setTaskFiles` action whenever a task is first created or edited with files attached.
Found the actual bug: the **⇄ Move / ⧉ Copy buttons** in the shop task editor (`etMoveCopy`) and plain
**drag-a-task-card-onto-another-trailer** (`ftDropJob`) both move/copy a task by calling `addTask` to
recreate it on the destination job — but `addTask` has no files field, and neither function carried the
source task's `files` forward or fired a follow-up `setTaskFiles` for the new row. The new task was simply
born with zero attachments every time. **Fixed** (rev 36.76): both paths now grab the source task's `files`
and re-attach them to the new row via `setTaskFiles`, same as when a brand-new task gets files attached.
Verified headless for both the Move/Copy buttons and drag-and-drop — the new row now correctly carries the
attachment through. ⚠️ **Not proven over real use yet** (same caveat as always) — and **attachments already
lost by moving/copying a task before this fix are NOT recoverable** — Rich needs to re-attach the electrical
PDF and the Airstream/On Cloud file to wherever those two tasks live now.

## ✅ FIXED 2026-07-30 — Project-task attachments could get silently wiped by Gantt drag actions
(Found while chasing the report above — turned out to be a real but DIFFERENT bug, on project tasks not
shop tasks. Kept fixed and documented since it's a genuine gap, but it is NOT what Rich's PDFs went missing from.)

Rich reported PDFs disappearing from project tasks (an electrical package on Medtronic – Buildout J1553,
one on the Airstream/On Cloud job) with no idea why — "I can't have shit disappearing." Root cause found
by auditing every code path in `MRA_Dashboard.html` that writes a project task (`action:'editProjectTask'`,
12 call sites): project-task attachments live as a hidden `[files:]` tag riding inside the task's Notes/
comments field (`_withFiles`/`_taskFiles`, same pattern as the `[by:]`/`[due0:]`/`[pt:]` tags). 11 of the 12
call sites correctly resend the task's full `comments` on every save specifically so an unrelated edit can't
blank it — but **two didn't**: `pdApplyOrderById`/`pdResetOrder` (dragging a task to reorder it in the Gantt,
or the "reset order" button) and `gLinkApply` (dragging to link a predecessor) sent a payload with no
`comments` field at all. Anyone reordering a task or drawing a dependency arrow on a project's Gantt — a
completely normal PM action, nothing to do with attachments — could silently wipe that task's Notes field
and, with it, the `[files:]` tag. **Fixed** (rev 36.75): both paths now resend `comments:t.cm||''` like every
other write. Verified headless: attaching a file, then simulating both a drag-reorder and a predecessor-link
write, now correctly preserves the `[files:]` tag through both. ⚠️ **Not proven over real use yet** — same
caveat as other write-path fixes here — and **attachments already lost before this fix are NOT recoverable**
(the tag pointing to them is gone from that task's Notes row) — Rich needs to re-attach the electrical PDF on
Medtronic J1553 and whatever was on the Airstream/On Cloud job.

Guidance for Claude when working in this repository.

## ⚠️ RECURRING "DATA PIPELINE STALLED" ISSUE — READ BEFORE TOUCHING POWER AUTOMATE (do not re-suggest fixes already applied)

The board banner "⚠ DATA PIPELINE STALLED — the board hasn't synced from the Lists in Nm" = the
**"MRA Lists to JSON"** flow has a stuck/hung run. **This has recurred repeatedly (not a one-off) and
Rich is done being told to re-apply the same fix — check this section before saying anything about it.**

**⚠️ CURRENT FLOW NAME (2026-08-26): "MRA Lists to JSON v4".** Rich has copied/renamed this flow
multiple times over its history (v2 → "Copy of - Copy of - MRA Lists to JSON v3" → now v4) — every
mention of "v2"/"v3" below in this section is HISTORICAL, describing whichever copy was live at the
time. Don't assume the name in an old note is still current — ask Rich or check Power Automate directly
if it matters which exact flow you're pointing at.

**✅ 10-MINUTE SELF-TERMINATE WATCHDOG BUILT + CONFIRMED LIVE 2026-08-26, on "MRA Lists to JSON v4".**
Rich was (rightly) frustrated that every fix so far had only put timeouts on individual actions
(`Create blob (V2)`/`Create file`, PT2M + retries — see the 2026-08-04/2026-08-06 entries below) and
those had ALREADY been caught, on camera, not firing — a run sat hung 39+ minutes past its own PT2M
setting with zero error. He'd been told a flow-level "kill it after N minutes no matter what" is a
standard, easy thing to build and wanted to know why that hadn't been done. It's a real, standard
pattern (a parallel watchdog branch off the trigger, ending in Terminate) — built same session:
- A **parallel branch** off the **Recurrence** trigger (added via the "+" under Recurrence → "Add a
  parallel branch", NOT "Add an action" — that's the option that creates a second column racing the
  main chain instead of extending it) contains just two actions: **Delay** (Count=10, Unit=Minute) →
  **Terminate** (Status=**Failed** — chosen over "Cancelled" specifically because Rich had already been
  confused once by an unexplained "Canceled" run status; "Failed" reads unambiguously; Code="auto
  cancel", Message="Auto-terminated: flow exceeded 10 minutes — likely hung step (recurring stall
  issue)"). Confirmed via Rich's own screenshots: parallel branch correctly sits alongside the WHOLE
  main chain (Mark run started → Get Jobs → ... → Create file), not partway down it, so it races the
  entire run, not just one step — matters since the hang has rotated between different steps recurrence
  to recurrence (Create blob one time, Create file another). Delay confirmed Count=10/Minute via
  screenshot of its own Parameters tab.
- **What this fixes vs. doesn't:** stops a stuck run from sitting for hours occupying the flow's
  "Degree of Parallelism = 1" slot and blocking every later trigger behind it (the mechanism that turned
  single hangs into multi-hour outages before, e.g. the 2026-08-06 21st-recurrence queue-jam). Does
  **not** fix WHY a step hangs in the first place (still the open, unconfirmed stuck-blob-lease theory —
  the ask to Rich's partner to check the `pipeline` container for a lease is still standing, untried).
  A run should now self-clear within ~10 min and the next 2-min recurrence picks up clean; the GitHub
  `pipeline-watchdog.yml` banner (fires past 20 min stale) should mostly stop firing once this is live.
- Not yet proven over a real stretch of time (same caveat as every fix in this section) — if the board
  goes stale again, check whether it self-recovered within ~10-15 min (watchdog working, root cause
  still there) vs. sat stale for real (watchdog itself failed somehow) before re-diagnosing from scratch.

**❌ 2026-09-01 — THE 8/28 WATCHDOG BELOW DOES NOT KILL STUCK RUNS. CAUGHT ON CAMERA. NOT MICROSOFT'S FAULT — MINE.**
Rich, leaving on a 5-day vacation the next morning: "why isn't our cancel program working? ... That's on you.
You can't keep blaming everyone else." He was right. Evidence (his screenshots, 9:15 PM): flow "MRA Lists to
JSON v4", a run started 6:57 PM still **Running at 2h18m**, and inside it the watchdog branch had fully
completed at 7:43:43 PM — `Delay` 10m ✓, `Condition` 0.1s ✓, `Terminate` **Skipped**
(`ActionBranchingConditionNotSatisfied`), False side 0 actions. So at its own 10-minute mark the Condition
(`RunDone is equal to false`) evaluated **false** — it concluded the run was already done — on a run that then
hung two more hours. The kill switch asked "am I stuck?" and got the wrong answer. Meanwhile healthy runs in
the same history were closing at exactly queue-wait + 10:00 (46:29, 48:12, 53:14, 58:14, 1:03, 1:08 — durations
climbing because the stuck run was eating one of the 3 parallelism slots, leaving zero slack vs the 5-min
recurrence). Degree of Parallelism was ALREADY 3 (Rich raised it 8/31 — don't tell him to do it again; I did,
twice, and got rightly chewed out) and only ONE copy of the flow is enabled (Rich confirmed) — both ruled out.
- **✅ ROOT CAUSE CONFIRMED BY READING THE ACTUAL PROGRAM (Rich sent the Condition's Code view, 9:34 PM):**
  ```
  "equals": [ "RunDone", "False " ]
  ```
  **Both operands are plain typed text.** The left is the literal word `RunDone`, NOT `@variables('RunDone')` —
  the variable was never being read at all. The right is the word `False` with a trailing space. So the
  watchdog has asked "does the text 'RunDone' equal the text 'False '?" on every run since 8/28 — never true —
  and has never once been capable of terminating anything. The `Set variable` placement theory was moot.
  **Fix given to Rich (exact clicks, new designer, Condition → Parameters tab):** (1) left box → delete the
  text → ⚡ dynamic content → pick **RunDone** under Variables (must become a token pill); (2) right box →
  delete the text → **fx** → `false` → Add (pill); (3) verify in Code view: line 7 = `@variables('RunDone')`,
  line 8 = `false`/`@false`, no quotes, no space; (4) Save → Run. Terminate stays on the True side (correct).
  **✅ APPLIED + SAVED BY RICH 9:44 PM 2026-09-01** — Code view confirmed `"@variables('RunDone')"` /
  `"@false"` before Save; Save accepted the cross-branch variable reference with no validation error (the
  designer's ⚡ dynamic-content pane shows NOTHING for this Condition because `Initialize variable` lives in
  the sibling branch — that's exactly why a word got typed there on 8/28; the fx expression works regardless).
  First attempt produced `"@'RunDone'"` (just the quoted name) — always re-check Code view for the
  `variables(` wrapper. Two runs already in flight at save time (9:36/9:41 PM) still ran the OLD definition.
  **Still not proven** until a run-history entry shows Failed / `auto cancel` on a real hang.
  **✅ ALSO APPLIED 9:50 PM — `Terminate 1` (Status: Succeeded) added as the LAST action of the main chain**
  (screenshot: Create blob (V2) → HTTP → Mark run done → Set variable → **Terminate 1**). Reason: the Delay
  branch made EVERY healthy run sit at exactly 10:00 (Power Automate won't close a run until both parallel
  branches finish), permanently eating 2 of the 3 parallelism slots — Rich: "it's always stuck on this delay
  stage." Now healthy runs close in ~1-2 min (Delay shows Cancelled inside the run — correct, main chain won);
  stuck runs never reach Terminate 1, so the 10-min Condition → Terminate(Failed) still kills them. **Final
  flow shape as of 2026-09-01:** Recurrence (parallelism 3) → [main chain … Set variable RunDone=true →
  Terminate 1 Succeeded] ‖ [Delay 10m → If `@variables('RunDone')` equals `@false` → Terminate Failed
  "auto cancel" / else nothing].
  **✅ CONFIRMED WORKING 9:56 PM, first run after the save: `00:01:34 Succeeded`** — against `00:10:01` for
  every single run before it (9:21/9:26/9:31/9:36/9:41/9:46/9:51 all exactly 10:01). Board `listsAsOf` also
  confirmed advancing on the normal ~5-min cadence right after. All 3 parallelism slots are free again instead
  of 2 being permanently occupied by runs doing nothing — that was the mechanism that turned a single hiccup
  into a multi-hour backlog, and it's gone.
  **⚠️ STILL UNPROVEN: the kill switch itself.** Nothing has hung since the Condition was fixed, so the
  `Terminate (Failed, "auto cancel")` path has never actually executed. Do NOT call the watchdog verified
  until a run-history entry shows **Failed / auto cancel**. And the ROOT CAUSE of why a step hangs at all is
  still unknown — everything done 9/1 makes a hang self-clear in ~10 min instead of hours; it does not stop
  hangs from happening. The stuck-blob-lease theory (partner-owned Azure access) is still untried, and the
  Microsoft support ticket was drafted but not confirmed filed.
  **LESSON (Rich's words: "read the program before you make an assumption"):**
  when a Power Automate step misbehaves, get the **Code view** screenshot FIRST. Parameters view shows a
  typed word and a real variable token nearly identically; Code view does not lie. Never diagnose a Condition
  from the Parameters/Run-results view alone again.
- **Why 8/28 looked "verified" when it wasn't:** it was only checked by watching healthy runs come back
  Succeeded — which they do identically whether the Condition works or is permanently false. The ONLY test that
  proves a watchdog works is a run that actually hangs (or a deliberately stalled test run) getting killed at
  ~10 min. That was never done. **Rule going forward: do not call this watchdog fixed until a run-history entry
  shows a run killed by it (Failed, Code `auto cancel`) — not before.**
- **⚠️ I ALSO GAVE RICH A WRONG INSTRUCTION TONIGHT AND HAD TO RETRACT IT:** told him to add a Terminate(Failed)
  to the empty False side. Under the real design that side is the HEALTHY path — it would have marked every good
  run Failed at 10 min (the exact 8/26 bug again). Retracted within minutes. If a future session sees a
  Terminate on BOTH sides of that Condition, the False-side one is the mistake — remove it.
- The GitHub `pipeline-watchdog.yml` re-alert interval was tightened 60 → 30 min the same night (both branches)
  since Rich is the sole recipient and away for 5 days.

**✅ FOUND + FIXED 2026-08-28 — the watchdog above was firing on EVERY run, not just hung ones (this is
the real explanation for the huge "Failed" run-history backlog Rich found spanning 8/26-8/28, and very
likely a contributing factor in some of the "recurrence" entries above too, in hindsight).** Rich sent a
screenshot of a run: every single action in the main chain green-checked, total real work under 2
minutes (Get Jobs 6s → Get Project Tasks 39s → Get Shop Tasks 38s → Get Users 0.5s → Create file 3s →
Create blob (V2) 2s → HTTP 0.3s → Mark run done 1s) — yet the banner read "Flow run failed." Root cause:
the 8/26 watchdog's Terminate action was unconditional. The parallel Delay(10min)→Terminate branch has
no way to know the main chain already finished — it counts down 10 minutes and terminates-as-Failed
**every time**, whether or not the real work already succeeded. Two real consequences, not just cosmetic:
(1) every run's history entry reads "Failed" even on a totally healthy sync, which is exactly the wall of
red Rich found and reasonably panicked over; (2) because Power Automate won't consider the overall run
resolved until BOTH parallel branches finish, every run now takes the full 10 minutes to close out — and
since this flow also recurs every 10 minutes, there was **zero slack**: the tiniest real-world timing
jitter cascades into the next trigger queuing up behind the previous one (Degree of Parallelism = 1),
which is the queue-pileup pattern from both the 8/26 run history (failures every 5 min, each one's
duration exactly 5 min longer than the last — the signature of a growing backlog) and the 8/28 one
(runs sitting "Waiting," 10 min apart, ages climbing toward 1h37m+).
- **Fix (built by Rich, verified via his own screenshots, both halves confirmed in place):** added a
  Boolean variable **`RunDone`**, `Initialize variable` = **false** right after `Mark run started` (top
  of the main chain), and a new `Set variable RunDone = true` step as the very last action in the main
  chain, right after the existing `Mark run done`. On the watchdog branch, inserted a **Condition**
  (`RunDone` is equal to `false`) between `Delay` and `Terminate`; the existing `Terminate` (Status
  Failed, Code `auto cancel`, same message as before) now lives inside the Condition's **True** branch
  only, with **False** left as "No Actions." So the watchdog now only actually terminates if the main
  chain is STILL running after 10 minutes — a normal run sets `RunDone=true` and finishes clean, and the
  watchdog branch sees that and does nothing.
- **What this does and doesn't fix, same distinction as the original 8/26 note:** stops the false
  "Failed" status on healthy runs, and restores real slack between the recurrence interval and how long a
  normal run takes to close out (so a routine bit of timing jitter no longer cascades into a multi-run
  queue-jam). Does **not** fix WHY a step occasionally hangs in the first place — that root cause (the
  unconfirmed stuck-blob-lease theory, or whatever else) is still open and still worth chasing if a
  genuinely stuck run recurs.
- Not yet proven over a real stretch — watch the next several run-history entries and confirm they read
  **Succeeded** (not Failed) when the main chain completes normally, and that the very next scheduled
  trigger after one starts on time rather than queuing. If "Failed" entries keep showing up even now, the
  RunDone wiring itself needs re-checking (e.g. confirm the Set-variable step is really the LAST thing in
  the main chain, after every write step, not accidentally inserted somewhere earlier).

**✅ WATCHDOG BUILT 2026-08-06 (`.github/workflows/pipeline-watchdog.yml`, on both branches — it uses
`schedule:`, which only reads from the DEFAULT branch, same rule as `export.yml`).** Checks the live
`data.js`'s `listsAsOf` every 10 min; if stale past 20 min, the job **deliberately fails** with a clear
message instead of silently logging. Debounced via a tiny committed state file
(`.github/watchdog-state.json`) — only fails once per stale episode, re-fails hourly if still
unresolved, clears itself the moment the pipeline recovers. Don't rebuild this if it comes up again;
check whether it's still there and firing correctly first.
- **⚠️ 2026-08-19 — the notification itself was BROKEN, not just the underlying stall.** A real stall
  hit (banner showed "1h 56m" on Rich's phone); the watchdog DID fire correctly (confirmed in its own
  run history — a genuine failure logged during the episode), but Rich: **"you never fix it and to
  reach out didn't work"** — no email ever reached him. Root cause found: this workflow relied on
  **GitHub's own failure-notification email** (the "zero new setup" design from 2026-08-06, based on
  Rich once seeing a similar email for a *different* workflow — that assumption doesn't hold here).
  GitHub sends a **scheduled** workflow's failure email to whoever **last modified that workflow file
  on the default branch** — which was **Claude's own commit identity** (`noreply@anthropic.com`), not
  Rich's real GitHub account. So the email had nowhere real to land, structurally, regardless of any
  notification setting on Rich's side. **Fixed**: the watchdog now ALSO sends a real, direct email via
  the same **`MC_MAILSEND`** Power Automate flow the dashboard itself already uses for Tell-Claude /
  pricing-approval emails (`rmiller@gomra.com`, proven mechanism, zero dependency on GitHub accounts or
  notification settings). Verified the exact POST mechanism against the live flow (real 202, then sent
  a one-time labeled test email) before relying on it in the workflow. Still deliberately fails the
  GitHub Actions job too (keeps the run-history trail), but the **email is now the real notification
  path** — if this recurs and Rich says the email itself didn't arrive, the bug is somewhere else
  (MC_MAILSEND itself, or his inbox rules) — don't re-diagnose the GitHub-notification angle again,
  it's confirmed dead.

- **2026-08-06 (21st recurrence, same day as the 19th/20th) — a REAL, separate, GitHub-Actions-side
  problem found and fixed (does NOT explain every recurrence, but is a genuine compounding factor).**
  Rich pushed back hard on "it's just flaky Power Automate/Azure" and asked for an actual deep-dive
  instead of the standard explanation. Pulled the real run history for the **"Cloud export (data.js)"**
  GitHub Action (`export.yml` — separate from "MRA Lists to JSON" itself, but triggered by its trailing
  `repository_dispatch` step): in the ~4 hours before this recurrence, **only 8 of the last 30 runs
  actually succeeded** — 15 sat in GitHub's `windows-latest` runner queue for exactly 15 minutes and
  got auto-cancelled, 7 failed outright. Root cause: "MRA Lists to JSON" fires a trigger for this
  workflow roughly every **2 minutes** (the interval Rich changed it to on 2026-07-16), and `export.yml`
  had `concurrency: cancel-in-progress: false` — meaning every trigger queued up and waited its turn
  rather than dropping stale ones. Whenever GitHub's shared `windows-latest` pool has any above-normal
  latency handing out a runner (common enough — this session hit the same "sits in queue" pattern on
  unrelated `deploy.yml` runs the same day), a 2-minute cadence leaves zero slack: triggers pile up
  faster than they drain, and the ones at the back miss GitHub's own 15-minute cutoff. **Fixed**: flipped
  `cancel-in-progress` to `true` in `export.yml` on BOTH branches (the working branch AND the default
  branch `claude/exciting-keller-wm7u2p` — repository_dispatch/schedule-triggered runs always execute
  the workflow file version from the DEFAULT branch, so the fix only takes effect there). Verified safe
  first: the only write to the live site is one atomic single-file `az storage blob upload --overwrite`
  of `data.js` at the very end of `Export-Data.ps1`, so a cancelled run can never leave a half-written
  file live — it just contributes nothing and the old `data.js` stays put until a run actually finishes.
  **✅ CONFIRMED RESOLVED, same session, with hard timestamped proof — this recurrence was NOT a Power
  Automate hang at all.** Rich pushed back hard on guessing (rightly — several wrong theories got floated
  in a row: PAT expiration, event_type mismatch, multiple enabled flow copies) and demanded actual data.
  Screenshots of the live flow ("Copy of - Copy of - MRA Lists to JSON v3") showed **every run succeeding
  every 5 minutes for the full 75-minute duration of the stall**, including the final `HTTP` notify step:
  correct URI (`.../MRA-Files/dispatches`), correct body (`event_type: run-export`), and a **204** response
  every time, from a token not expiring until 2027. So the flow was 100% healthy the whole time — the
  historical "hung on Create blob/Create file" pattern (below) does NOT apply to this recurrence. Built a
  temporary catch-all diagnostic workflow (`on: repository_dispatch` with no `types:` filter, so it fires
  on ANY dispatch regardless of event_type) to get a direct answer instead of another guess. Result: **the
  very first dispatch cycle after the `cancel-in-progress:true` fix above landed on the default branch —
  6:29:17 PM, to the second — succeeded end-to-end** (both the catch-all and `export.yml` itself fired and
  completed), and the live board's `listsAsOf` updated 4 seconds later. Real mechanism: the earlier 5–9 PM
  queue pileup (73% failure rate, documented above) jammed GitHub's concurrency-group queue for this job
  badly enough that it stopped creating NEW runs entirely — even though every individual `repository_
  dispatch` API call kept getting accepted (204) the whole time, so nothing looked wrong from the Power
  Automate side. The `cancel-in-progress:true` fix cleared the jam; the next real dispatch went straight
  through. Diagnostic workflow deleted once confirmed (see its own commit for the exact evidence chain).
  **Lesson for next time a stall shows a 204/green everywhere and still doesn't publish**: don't assume the
  Power Automate flow is hung just because the board is stale — check whether GitHub is actually spawning
  runs for the dispatch (a temporary no-`types:` catch-all workflow is the fastest way to get a direct,
  unambiguous answer instead of guessing).
- **2026-08-06 (20th recurrence, same day as the 19th) — hang moved to a DIFFERENT step this time.**
  Stalled again ~2h after the 19th recurrence's manual rerun (banner at 1h47m). Rich screenshotted the
  stuck run again: this time every step through `Compose` completed fine (`Select` 0s → `Get Project
  Tasks` 47s → `Select 1` 0.2s → `Get Shop Tasks` 30s → `Select 2` 0.1s → `Get Users` 1s → `Select 3` 0s
  → `Compose` 0.9s, ~80s total) but it hung on **`Create file`** — with `Create blob (V2)` never even
  starting. **This is the important new fact: last time (19th) the hang was on `Create blob (V2)`; this
  time it's on `Create file` instead.** Same symptom (spinning past its own already-correct `PT2M`
  timeout + Exponential/Count 4/Interval `PT10S` retry, confirmed present on this step back on
  2026-08-04), different action, different connector (SharePoint this time, not Azure Blob). **This
  argues AGAINST the leading "stuck blob lease" theory being the sole cause** — a lease on the Azure
  blob wouldn't explain a SharePoint `Create file` step hanging. More likely explanation: whatever's
  wrong isn't specific to one action/connector, it's something that can stall ANY write step in this
  flow — e.g. a similarly-stuck lock/checked-out state on whatever SharePoint file `Create file` writes
  to, or a platform-level issue with how this environment's timeout/retry gets honored for long-running
  connector calls in general. **Next time this happens, keep noting WHICH step is stuck each time** —
  if it keeps rotating between different actions, that pattern itself is the clue (points to something
  systemic, not a single fixable resource) — if it keeps landing on the SAME action, that narrows it
  back down. Cancelled + reran as normal; the blob-lease ask to the partner (below) still stands, but
  broaden it to also ask whether the SharePoint file `Create file` writes to could be locked/checked out.
- **2026-08-06 (19th recurrence) — FIRST TIME actually caught mid-hang, live in run history. Real new
  evidence, not a re-guess.** Stalled again (banner at 42m). Per the standing ask below ("open the stuck
  run FIRST, before cancelling, and see which step is still running"), Rich did exactly that and
  screenshotted it. Confirmed: every step before `Create blob (V2)` completed fast and clean (`Select 1`
  0.2s → `Get Shop Tasks` 29s → `Select 2` 0.1s → `Get Users` 0.2s → `Select 3` 0s → `Compose` 0.3s →
  `Create file` 3s, all green checks, ~33s total) — **the hang is `Create blob (V2)` specifically**, still
  spinning with no error at 39+ minutes elapsed. Confirmed its Settings tab: **Action timeout `PT2M`,
  Retry policy Exponential interval, Count `4`, Interval `PT10S`** — exactly the fix applied back on
  2026-07-29, still correctly in place. **This is the important part: those settings should force a
  hard fail well under 10-15 minutes in the worst case, and they did not.** An action still hanging PAST
  its own configured timeout+retries points away from "needs another timeout tweak" and toward the
  underlying Azure Blob write itself being blocked on something Power Automate's retry policy can't route
  around — most likely a **stuck lease/lock on the actual blob** (`pipeline` container, the file this step
  writes) left behind by an earlier failed/aborted run. Told Rich to have his **partner** (owns Azure
  Storage access) check that specific blob for an active lease and break it if present — this hasn't been
  tried yet and is now the leading suspect, ahead of the `Get *` steps (already hardened + ruled out below).
  ⚠️ Not yet confirmed — waiting on the partner to actually check for a lease.
  **Same-day update**: Rich tried checking this himself in the Azure Portal signed in as his @tandemeng.com
  account (confirmed in the right tenant, "TGCS (tandemeng.com)") — every blade ("Storage center", "All
  storage resources") threw a generic "Error fetching data: service error", and searching "mrashopdash" by
  name in the top search returned nothing. **Confirmed: Rich has no working Azure access under this login**,
  consistent with the existing Access note above (Azure is partner-owned) — this isn't a new problem to
  troubleshoot, just confirmation he can't self-serve this check. The lease check has to go through the
  **partner** — gave Rich the exact ask to forward (check the `pipeline` container's blob for a stuck lease).
- **2026-08-04 (18th recurrence) — two prior "still open" questions FINALLY checked and BOTH ruled out,
  true cause still unknown.** Found THREE copies of this flow existing: `MRA Lists to JSON` (original),
  `Copy of - MRA Lists to JSON v2`, `Copy of - Copy of - MRA Lists to JSON v3`. Confirmed via screenshots
  on the active one (v3): `Create blob (V2)` and `Create file` both already have the correct `PT2M` timeout
  + Exponential/Count 4/Interval `PT10S` retry — **no P2TM typo on either, that question is answered,
  both clean.** Recurrence Concurrency Control was already On/Degree 1. **Initially guessed the OTHER TWO
  copies being simultaneously enabled was the culprit (multiple flow definitions colliding on the same
  write, which per-flow Concurrency Control can't prevent) — Rich corrected this: v2 and the original were
  ALREADY disabled before this stall happened, not something newly turned off. So that's NOT the cause
  either.** Net result: every setting on v3 checks out correct, no duplicate-flow collision, yet it still
  stalled — **the actual root cause remains unfound.** Next suspects (per the original note below, still
  untried): the `Get Jobs` / `Get Project Tasks` / `Get Shop Tasks` / `Get Users` SharePoint "Get items"
  steps earlier in v3's flow (visible in the canvas: Recurrence → Get Jobs → Select → Get Project Tasks →
  Select 1 → Get Shop Tasks → Select 2 → Get Users → …) have never had Action Timeout/Retry Policy added,
  unlike the two blob/file write steps. A `Get items` action can hang if it's set to return all items with
  no pagination threshold, or gets throttled by SharePoint with no retry to recover. Check each `Get *`
  step's Settings tab the same way the write steps were just checked, and add the same `PT2M`/Exponential/
  4/`PT10S` treatment if any is missing it.
  - **Checked + FIXED same session:** all four Get steps (`Get Jobs`/`Get Project Tasks`/`Get Shop Tasks`/
    `Get Users`) were IDENTICALLY under-protected — no explicit Action Timeout (blank), Pagination On/
    Threshold `5000`, Retry Policy `Default` (not the explicit Exponential/4/`PT10S` the write steps have).
    Not one-bad-step, a systemic gap across all four reads. Rich added **Action Timeout `PT5M`** (longer
    than the write steps' `PT2M` since a paginated multi-thousand-row read can legitimately take longer)
    **+ Retry Policy Exponential interval/Count 4/Interval `PT10S`** to all four, saved. ⚠️ Not yet proven
    over a real stretch — if the banner recurs again, this round of fixes didn't hold either.
  - **Filter Query is blank on `Get Jobs`** (pulls the ENTIRE list every 5-min run, no date/status
    filter) — real gap, left as-is (the flow's job is to export everything, filtering would need matching
    changes downstream), just noting it exists.
  - **Checked real list item counts (Site Contents, 2026-08-04): all four are small — Jobs 107, Project
    Tasks 734, Shop Tasks 492, Users 12.** Nowhere near the pagination Threshold of `5000` — the
    silent-truncation risk is RULED OUT, and this also makes the "growing list slows the flow down"
    theory less likely (734 rows is trivial for SharePoint to page through, shouldn't cause multi-minute
    hangs by itself). **Net status after this whole session: every externally-checkable cause has now
    been checked and hardened (no typo, no duplicate-flow collision, all Get steps now have explicit
    timeout+retry, list sizes ruled out) but NONE was confirmed as an actual smoking gun for why it
    hangs.** ⚠️ **NEXT TIME it stalls: before cancelling, open the stuck run in run history FIRST and
    screenshot/note which specific step still shows as running/not-completed.** That's the one diagnostic
    that hasn't been tried — it would show exactly where time is going in real time, instead of auditing
    settings after the evidence (the hung run) is already gone. Cancel + rerun as normal after capturing it.
- ✅ **ALL THREE PARTS DONE (Rich confirmed 2026-07-29) — do NOT ask Rich to redo any of these:**
  1. **`Create blob (V2)`** step → Settings → **Action Timeout = `PT2M`**, **Retry Policy = Exponential
     interval, Count `4`, Interval `PT10S`**.
  2. **`Create file`** step (a separate SharePoint write, earlier in the same flow) → same treatment:
     Action Timeout `PT2M`, Retry Policy Exponential interval, Count `4`, Interval `PT10S`.
  3. Trigger (**Recurrence**) → Settings → **Concurrency Control: Degree of Parallelism = `1`** — was
     found set to `50`, Rich changed it to `1` and saved, confirmed done 2026-07-29.
  - Rich says a past session told him to raise it 1→50 "2 days ago"; I have **no record of that** in this
    file and couldn't confirm it happened as he describes — doesn't change the fix either way. **Do not
    raise this above 1 for this flow** unless the reason is written here first. If capping it at 1 ever
    causes visible lag (Maximum waiting runs climbing), the fix is slowing the Recurrence interval, not
    raising parallelism back up.
- ✅ **TYPO ROOT CAUSE FOUND + FIXED 2026-07-29 evening (Rich confirmed "Done") — do NOT re-litigate this.**
  The banner recurred again same day (~9:01 PM) and Rich dug into the actual failed run (flow shown as
  **"Copy of - MRA Lists to JSON v2"** in his Power Automate) — the **`Create file`** step's **Action
  Timeout** had been typed as **`P2TM`** instead of **`PT2M`** (T and 2 swapped). That's not a valid
  ISO-8601 duration, so `Create_file` was failing INSTANTLY (0.1s, `InvalidTemplate... 'P2TM' is not a
  valid TimeSpan value`) on every single run, not just occasionally — meaning since the 7/29 "done" fix
  went in, this step was actually broken 100% of the time, not intermittently. Rich retyped it to
  `PT2M` and confirmed done. **Still not proven over a real multi-day stretch** (same caveat as always
  with this flow) — if the banner recurs again, don't assume it's this same typo; check fresh.
  - ⚠️ **Still open, not yet checked:** whether the `Create blob (V2)` step has the same P2TM/PT2M swap
    (it got the identical value the same original session — plausible the same typo happened twice, but
    unconfirmed either way). Check it next time you're in this flow with Rich.
  - ⚠️ **Still open, not yet checked:** the flow name "Copy of - MRA Lists to JSON v2" suggests a possible
    duplicate flow floating around — confirm only ONE has the Recurrence trigger enabled.
  - If the banner recurs again after all the above, the next suspects are `Get Shop Tasks` / `Get Users`
    (other connector actions in this same flow, not yet timeout-protected) — check those next.
- **Immediate workaround (Rich already knows, the banner says it too):** cancel the stuck run(s) →
  Run manually. Don't re-explain this to him either — he's done it many times.
- Older note below ("Pipeline incident... resolved 2026-07-17") turned out to NOT be fully resolved —
  it's the same recurring issue, kept for history but superseded by this section.

## ⚠️ BUG INCIDENT 2026-07-29 — Time Tracking edit feature duplicated real payroll rows (FIXED, cleanup still owed)

The ✎ edit-entry feature added to `time/index.html` today POSTed `action:'editTime'` to the SAME
`TIME_WRITE_URL` that only ever handled `action:'addTime'` (create a row in the **MRA Time Entries**
SharePoint list). That flow almost certainly has no branching on `action` at all — it was only ever
built to create — so every edit of a previously-synced entry silently created ANOTHER row instead of
correcting the original, inflating real hours. Confirmed live: Brent Burns showed **50 hrs** in the
manager/finance view (shared list) vs the real **30 hrs** in his own device's "Your week" view, caused
by a duplicated "Fab Gen mount for Doug" / General / 10 hrs entry for 7/27/26.
- ✅ **Fixed same day**: `saveEditEntry()` no longer POSTs anything to `TIME_WRITE_URL` — edits are
  local-device-only until a real update branch exists in that flow. Do not re-add that POST without
  first building (with Rich, in Power Automate) a genuine `editTime` branch that does a SharePoint
  **Update item** by `EntryID`, not another Create item.
- ⚠️ **NOT done yet — real data cleanup still owed**: any entry edited via ✎ during today's testing
  (2026-07-29) likely has a duplicate row sitting in the live **MRA Time Entries** SharePoint list right
  now. Known duplicate: Brent Burns, 7/27/26, "Fab Gen mount for Doug", General, 10 hrs (two copies).
  There may be others from other test edits made today — check the list directly (SharePoint → MRA
  Site → MRA Time Entries, or via the flow's "Get items") for same Employee+Date+Job+Hours+Notes rows
  and delete the extra copy. I don't have write access to SharePoint to do this myself.
- If a real "editTime" flow branch gets built later, match by the `EntryID` field (the client-generated
  id sent in the edit POST body) — that's the stable key, not SharePoint's own row `ID`.

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
## 🧭 COMMAND CENTER (Quintin layout) — state as of 2026-07-17 late (READ THIS FIRST next session)

- **LIVE at `/command/index.html`, LOCKED TO RICH ONLY** (preview): classic header shows a 🧭 button
  only for super-admin; the page itself full-screen-locks on the live host unless the signed-in MSAL
  user is Rich (`ccAccessOK` in `command/app.js` — delete its superadmin gate to open it up). Off-host
  previews stay unlocked for dev/testing.
- **⚠ THE BIG PIVOT (Rich, blunt — screenshots of a mess on iPad):** my rebuilt Shop board + Projects
  gantts were "a complete shit show / unreadable / piss poor". His call: **"leave it how we had it and
  just move the menu."** SO: **Shop / Projects / Maintenance pages now EMBED the real `MRA_Dashboard.html`**
  (iframes: bare / `?view=projects` / `?view=fleetio`) inside Quintin's left-nav shell — every classic
  bell + ALL admin functions work via the embed, zero duplication. Guards: only one `.ccframe` alive at
  a time (`showPage` removes hidden ones — iPad memory), render guards stop the 60s poll reloading it,
  classic hides its 🧭 button when `window.self!==window.top`. **DO NOT resume rebuilding those three
  pages from scratch** — Rich is extremely concerned about money burned on the rebuild attempt; reuse first.
- **ONE BOARD, ONE SKIN (2026-07-18, Rich: "Build it"):** the rail is now the ONLY nav. Board pages
  (Shop→floor · Projects→projects · Maintenance→fleetio · Assets→assets · My Work→mywork) share ONE
  persistent iframe (`#boardFrame` in `#boardhost`, never reloaded — `BOARD_VIEWS`/`boardSetView()` call
  the board's own `setView` via contentWindow); the board hides its brand AND tab row under `.ccembed`;
  shell collapses to a 60px icon rail + no top bar (`body.railmode`) on board pages; themes sync
  (`syncBoardTheme`). Home flows naturally (home-mode canvas removed). CC pages left: Home/Tools/Sales
  (tasks.js/shop.js etc. remain but unrouted).
- **Still new-format (Rich OK'd colors = MRA orange `--brand:#e04826`, Block 9 in styles.css):** Home
  (bay canvas + weekly overlap + coming due), My Work (tasks.js, mirrors the classic engine incl. verify/
  close/expand), Tools, Sales, + a Floor View overlay (floor.js). `command/app.js` carries a full port of
  the edit engine (same `_LF`/`shopWrite`/by-id retry queue), the SSO+role system (same rules as classic,
  fail-open off-host), and `ganttDates`. All 16 adversarial-audit findings in `command/CC_FOLLOWUPS.md`
  were fixed BEFORE the pivot (bay-grid drops, dead range buttons, etc.) — most now moot for the three
  embedded pages but the fixes live on in Home/My Work/app.js.
- **📁 gomra MIGRATION — TIM RAN PHASE 1 (2026-07-17 evening, VERIFIED):** `Migrate-Data-To-Lists.ps1
  -Fresh` against `https://gomra.sharepoint.com/sites/MRADashboard` → **96 jobs (exact match to live),
  384 shop tasks (live 385), 567 project tasks (live 564 — same-day drift), 0 users (by design)**.
  Lists exist + loaded; NOTHING switched — live board still reads/writes Tandem. REMAINING before cutover:
  (1) **MRA Users** on gomra is EMPTY — 12 users must be re-entered (old list stores hashed codes `h`,
  no plaintext → re-enter by hand w/ Name/Code/Role/Active, or issue new codes); (2) repoint the 4 flows
  (MRA Lists to JSON / MRA Lists Write 2 / MRA Email / MRA Daily My Work Emails) → gomra site + gomra
  connections — do this WITH Rich, GUI, one at a time, Tandem stays live as rollback; (3) Tim still owes
  admin consent for the "M365 MCP Client for Claude" app so I can read gomra sites directly.
- **Pipeline incident (2026-07-17 ~16:00Z, NOT actually resolved — recurred repeatedly since, see the
  ⚠️ RECURRING section at the very top of this file for current status):** "MRA Lists to JSON" hung on
  Create blob (V2) — two runs stuck 3+ hrs, listsAsOf frozen 45 min. Diagnostic tell: `listsAsOf` stale
  while `generatedAt` ticks = that flow hung on the blob step.

## 📧 WEEKLY EXECUTIVE REPORT (Tony) — built 2026-07-18, revs 29.1→29.9 (state)

- **Lives at `?exec=1`** (+ ☰ Actions → 📧 Executive report (weekly)). **LOCKED TO RICH on the live host**
  (the `_execQ` boot branch waits for MSAL, renders only for `isSuperAdmin()`; off-host renders ungated for
  dev). ⚠ While locked, an emailed link shows Tony a lock screen — **"open it for Tony" = extend the gate
  check** (allow tony@gomra.com), THEN Rich builds the Monday 6 AM Send-email-V2 flow (5 steps given in chat).
- **Structure (research-backed, Rich-trimmed):** orange "WEEK IN 30 SECONDS" box (with ▲/▼ closed-vs-last-wk
  delta) → 5-6 stat tiles → 4 charts (shop output/wk · health strip · crew load w/ overdue red · progress-vs-
  plan w/ expected tick) → project CARDS (status chip, PM, % · ▶ start→finish · open · closed-this-wk; amber
  past-due strip; greens one card each) → program timeline (capped month ticks + per-row dates) → closed-by-job
  pills + 🚢 ships + ◆ milestones (NO task-level highlights — Rich killed them, "Tony doesn't care") → shop
  floor GROUPED BY BAY (cards) → next two weeks. Mobile-first (media query <640px); phone-validated.
- **Accuracy hardening (Rich hit a bad snapshot at 12:06 AM — shipped jobs in bays, 0 closed):**
  (1) **⚠ DATA CHECK FAILED banner** — report refuses to present silently when source!=='lists' (workbook
  fallback), listsAsOf missing/>60 min, or doneN===0 (implausible); names the reason + "refresh in ~5 min".
  (2) **Shipped-this-week** = scan ALL non-leave/non-orphan jobs (incl. pipeline category), take the LATEST of
  the 🚢 notes-tag date vs completionISO when Status=Shipped — the tag alone missed status-flip ships,
  re-ships w/ stale tags (Washtenaw), and pipeline builds (Sigenergy IW163, SWC IL2).
- **🔗 LOCKSTEP (rev 30.5):** exec ?exec=1 · PM ?recap=1&pm= · Floor recap ?recap=1 all count via shared
  `_rptLaneJobs/_rptOpenT/_rptOpenCounts` (board-lane rules). The 149-check verifier
  (`scratchpad/verify_exec.mjs`, run against local serve/ of the LIVE files) includes cross-report
  assertions — run it before ANY report change ships. Deficiency ?fix=1 shares the project-task math
  but is not yet in the cross-check suite (Rich may ask).
- The transient bad-snapshot mechanism (partial lists.json → statuses/closed dates missing) is the same flow
  fragility as the Create-blob hang — if it recurs often, harden "MRA Lists to JSON" (retry/validate step).

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
- **rev 27.6 — MY WORK web made interactive (Rich, blunt: "web has no hover / not clickable / doesn't say what the 31
  past-due ARE / follow our standard").** Fixed the web tab to the board standard: **every row hover-highlights**
  (`var(--panel2)`, `.row.mw-click:hover` scoped to `#myworkView`) and is **click-through** (`mwGoShop`→`openEditJob(row)`,
  `mwGoProj`→`openProjectEditor(name)`); **stat tiles** are clickable → `mwTileGo` scrolls to that section (ids
  `mwsec-od/due/verify/pend/proj`). **My Projects rows EXPAND** (`MW_PROJ_OPEN` Set + `mwToggleProj`) to list the actual
  **past-due tasks** (`_pmtBehindBits(p).od`: who/due/phase, each → project editor) + an "✎ Open … editor →" link; the
  collapsed health line now carries the SAME **"⚠ N past-due · with: X (n), Y (n)"** breakdown as the emailed report
  (parity — his "the 2 are not the same" complaint). Data engine stamps a `nav:{k,row|proj}` on every item; `_mwNavAttr`
  builds the onclick + a › chevron affordance. Milestone/completed/awaiting/marked-ready rows all hover+click too.
  Verified headless (38 mw-click rows, tiles, "with:" present, Cisco expands to 19 past-due subrows + open-editor link,
  zero pageerrors) + screenshot eyeballed. **Sent Rich sample emails** (Al/PM, Sarah/design, Sal+Doug/crew, +a PM demo
  with the ✅ sign-off section populated) since live data has 0 Pending-Verification right now.
- **rev 27.7 — MY WORK tab limited to a per-person allowlist (Rich 2026-07-17: "only show for Megan, Al, Luciana,
  Brandon, Mark, Sarah, Sal, Jeff, Josh and Doug/Stephanie. Don't need it for anyone else").** New `mwTabAllowed()` +
  `MYWORK_EMAILS`/`MYWORK_NAMES` (matched by email OR `_nmKey` display name); `applyRoleUI` hides the `.tab[data-view=
  "mywork"]` + redirects off it if the current view is mywork, and only auto-lands allowed non-admins on it. Rich
  (super-admin) always keeps it (person-picker). Anon shop TV never shows it; **fail-open unchanged** off-host/preview.
  The mywork tab was previously NEVER role-gated (in every role's `tabs`), so this is the first gate on it — the per-role
  `tabs` arrays still list mywork; the allowlist is the finer gate layered on top. Verified headless: allowlist people +
  name-fallback + Rich = shown; Cindy(shopedit)/Tony(exec)/Quintin(admin-not-listed)/anon = hidden; tab element
  hides/shows correctly. **Add someone later = append their email to `MYWORK_EMAILS` (+ name to `MYWORK_NAMES`).**
  NOTE: the `?mywork=Name` email/deep-link page is NOT gated by this (daily email recipients follow the routing table).
- **rev 27.8 — MY WORK shows every task's FULL detail (Rich 2026-07-17: crew need "fleteo pictures + all fleteo info +
  all comments"; design/PM need "the subproject, comments, and any other information for every task").** `myWorkFor`
  now stamps each item with `cm` (comments, machine-tags stripped by `_mwCleanCm`), `fnum` (Fleetio # from `🔧 #NNN` in
  the task text), and for project tasks `phase`/`ptype`/`parent` (walks back to the previous non-sub task) + `files`.
  Tab (`_mwRow`): reuses the board's own `fioDetHtml(fnum)` (clamped Fleetio description) + `mediaHtml(_taskMedia(files,
  fnum))` (photo/file thumbs w/ hover-zoom) + a `🔧 #NNN` badge + a 📝 comments line + project `↳ parent · phase · type`.
  Email (`buildMyWorkHtml` → shared `detailOf(x)`): Fleetio # + asset + description, 📝 comments, up to 4 photo thumbs +
  file links, and the project subproject/phase/type — on li/pli/ali. Verified live-data headless: Sal 13 Fleetio+16
  comments+photos, Doug 16 Fleetio+19 comments, Sarah 5 parent+17 phase, Al 21 phase — email renders Fleetio/comments/
  photos; screenshots eyeballed (Sal crew + Mark design). Deployed before the 6 AM email so today's send carries it.
  **DAILY EMAIL FLOW IS BUILT + LIVE** (Rich built it 2026-07-16 night): "MRA Daily My Work Emails" — Recurrence (Mon-Fri
  6 AM Eastern) → Initialize variable `Recipiants` (Array, the 12-recipient JSON) → Apply to each → Compose `EmailBody`
  (concat HTML w/ `encodeUriComponent(items('Apply_to_each')?['name'])` link) → Send email V2 (To=`items('Apply_to_each')
  ?['to']`, CC rmiller@gomra.com, Body=EmailBody Outputs). Add/remove a person = edit the Recipiants array.
- **rev 27.9 — tasks show WHO added them (Rich 2026-07-17: "for the general tasks ... put their name for the guys ...
  in case they have questions ... part of everything").** No creator field existed in the data (task keys: t/who/op/
  due/cm/st/done/ml/files/_id) and the ActivityLog Who is blank (known bug), so the creator now rides the **comments
  column as a hidden `[by:Name]` tag** (same pattern as `[repeat:]`/`[pt:]` — zero SharePoint/flow change). Helpers
  `_taskBy`/`stripBy`/`_withBy`/`_byLine` by stripRepeat. **Stamp:** central in `shopWrite` on `addTask`/`addProjectTask`
  (skips user 'Shop'/'Design Team'; won't dup). **Preserve through edits:** shop editor loads `stripBy(stripRepeat(cm))`
  + `window._etBy`, saves `_withBy(_withRepeat(...),_etBy)`; project editor same with `window._ptBy` (reset '' on add).
  **Display "🧑 added by X":** crew-column + bay-card task lines (`_byLine(o.cm)`), daily letter, and MY WORK tab
  (`_mwRow`) + email (`detailOf`) via `by:_taskBy(t.cm)` on items. **Strip the raw tag everywhere** a comment shows:
  `_mwCleanCm` now includes `by`; fixed all raw-cm sites (crew sheet + work orders `_mwCleanCm(o.cm)`, daily letter,
  design-board parent note, unassigned finder ctx). Verified headless: stamp/skip-Shop/no-dup/strip/extract all pass;
  board shows "added by" 3×, My Work + email show it, **zero raw `[by:` in any visible text** (the innerHTML "leak" was
  my own `<script>` source comment — innerText clean). ⚠️ Only NEW tasks get it; no record of who created older ones.
- **rev 28.0 — RESCHEDULE with a paper trail (Rich 2026-07-17: "extend the due date but don't make the old one
  disappear — hash through it; for projects push it out OR slide the whole start→finish range; sometimes slide the
  entire schedule").** Original due kept as a hidden **`[due0:YYYY-MM-DD]` comment tag** (same rides-comments pattern as
  `[by:]`/`[repeat:]` — no list/flow change). Shown **struck through before the current due** (`~~old~~ → new`) on board
  task lines (both `odue` sites: bay + crew), My Work tab (`_mwRow`) + email (`li`), via `_due0Strike(cm,curISO)` / item
  `due0:_taskDue0(t.cm)`. **Auto-capture:** on save, if the new due/finish is LATER than the old and no `[due0:]` yet,
  stamp the old one (shop `submitEditTask` uses `window._etDue0/_etDueOld`; project `submitProjTask` uses `_ptDue0/_ptFinOld`);
  preserved across edits; `_mwCleanCm` + both editor comment-boxes strip `due0`. **Controls:** shop editor ⏩ Push due
  (+1wk/+2wks/+1mo/N days = `etPushDue`); project editor ⏩ Push finish (`ptPushFinish`, finish only) / Slide range
  (`ptSlideRange`, start+finish together); project-editor modal ⏩ **Shift schedule** (`projShiftAllBtn`) = slides EVERY
  dated task's start+finish by N days (+later/−earlier), each keeping old finish struck, via bulk `editProjectTask` writes.
  Helpers `_taskDue0/stripDue0/_withDue0/_isoAddDays`. Validated headless: push/slide/shift math, 12-task shift fired 12
  ops with new dates + due0, struck display in tab/email/board, no raw `[due0:` leak, zero pageerrors.
- **rev 28.1 — Josh CLOSE-ONLY login (Rich 2026-07-17).** New role **`closer`** (`jeberhart@gomra.com` + name Joshua
  Eberhart): can **✓ close his OWN tasks and nothing else**. Built so **no global CLOSE_PIN is ever set** → every other
  write stays blocked exactly like a view-only role. `ssoIsCloser()`; `ensureAuth` still returns view-only for closer;
  `closeTaskByName` has a closer branch that closes with a LOCAL `'1974'` pin (not the global) + `_canCloseHere` own-task
  guard; `closeHandle` renders the ✓ only on the closer's own tasks. `body.closeronly` CSS reveals `.closebtn`, hides
  `.qa/.ttool/.editjob/.jgrip/.leaveadd/.fladd`. Also added **`BOARD_NAME_BY_EMAIL` + `boardNameFor()`** (jeberhart→Josh,
  jsellers→Jeff, shopsupport→Sal, dcooley→Doug) and pointed `myWorkWho()` at it — fixes the signed-in **My Work** match for
  Josh/Jeff/Sal/Doug (their board name ≠ full sign-in name). Validated headless: own-task ✓ only, close fires as "Josh"
  pin 1974, others' close + all edits blocked, global pin stays null, zero pageerrors. ⏭ Josh will need to actually be a
  gomra login (he is) — role resolves by email OR name.
- **🔜 OPEN (Rich 2026-07-17): (1) 🦺 SAFETY — new OSHA safety SharePoint site `gomra.sharepoint.com/sites/OSHASafety`;
  wants a ☰ Safety link + a dashboard UPLOAD that stores files there + eventually a safety dashboard (graphs). Plan:
  Menu link now; upload = a Power Automate "MRA Safety Upload" flow (HTTP trigger → Create file in the OSHASafety doc
  library, pin-gated, base64 like EOTM) + a dashboard upload modal; graphs = phase 2 off a SharePoint List of safety
  items (decide fields w/ Rich). (2) 📁 MOVE THE CLAUDE FILES Tandem→gomra SharePoint (the big pipeline migration in the
  runbook — repoint every flow's Site Address + re-auth as gomra, likely recreate the Lists; Tim creates the site first).**

## Shipped 2026-07-17 (late) — Safety upload LIVE · email-close · Jeff closer · migration teed up (rev 28.2 → 28.7)
- **🦺 SAFETY LIVE (rev 28.2–28.5).** ☰ Menu **🦺 Safety** (data-perm="safety" — shown to design/editor/exec-owners/admin,
  hidden from anon/staff/shopedit/closer) opens a panel: 🔗 open the OSHASafety site + **📤 upload a file** (folder picker =
  Safety Talk / Eyewash PM / PMHV Safety and License / Standards / Inspections / Incidents / Training / Other · date · note).
  `SAFETY_UPLOAD_URL` set to the **"MRA Safety Upload"** flow; base64 no-cors POST like EOTM; `pin:CLOSE_PIN||'1974'` so
  view-only owners can upload. **Flow (Rich built):** HTTP trigger → Create file (SharePoint). ⚠️ **GOTCHAS hit + fixed:**
  (1) body arrives **text/plain** (no-cors) → must parse with **`json(triggerBody())?['x']`**, NOT `triggerBody()?['x']`
  (that returned empty → Condition False → Create file skipped; 202 but no file). We ended up neutralizing the pin Condition
  (compare `1`=`1`) since it wasn't needed. (2) SharePoint **cross-tenant**: the Site Address dropdown only shows the
  connection's tenant — must **Change connection → sign in as rmiller@gomra.com** (first-party SharePoint connector = no
  admin consent needed, unlike the MCP app). (3) Final bug: Site Address was set to **MRA Dashboard** site, not **OSHASafety**
  → files landed on the wrong gomra site; fixed to OSHASafety. Create file expressions: Folder Path
  `concat('/Shared Documents/', replace(json(triggerBody())?['category'],'/','-'))`, File Name `concat(json(triggerBody())
  ?['date'],' - ',json(triggerBody())?['fileName'])`, File Content `base64ToBinary(json(triggerBody())?['fileB64'])`.
- **rev 28.6 — close a task FROM the daily email after sign-in (Rich: "click it, then he has to log in").** Email gets a
  **🔒 Log in to close** button → `?view=mywork` deep-link (new `?view=<tab>` support in the initial-view logic) opens the
  LIVE board on My Work → SSO login gate → then **✓ close on each own task** in My Work. `_mwCanClose(proj,raw)`
  (closer→own via `_canCloseHere`, editor/shared-pin→any, view-only→none) + `mwCloseTask()`; shop items now carry `proj`+`raw`.
- **rev 28.7 — Jeff Sellers close-only (same as Josh).** Added `jsellers@gomra.com` + name to the `closer` role (uses the
  existing closer path + `BOARD_NAME_BY_EMAIL` jsellers→Jeff). To add more closers: append email to ROLE_BY_EMAIL:'closer'
  + name to ROLE_BY_NAME closer[].
- **🔐 Connecting Claude's M365 MCP to gomra = BLOCKED on Tim.** Trying to reconnect the "M365 MCP Client for Claude" app
  as rmiller@gomra.com hit **"Need admin approval"** (gomra tenant requires admin consent for the 3rd-party app). Tim grants
  it once (Entra → Enterprise apps → grant admin consent, OR the "Have an admin account?" link on the consent screen). Until
  then my M365 read is Tandem-only (can't see gomra sites to verify). Not blocking — migration data comes from public data.js.
- **📁 MIGRATION PLAN (Lists + flows Tandem→gomra `MRADashboard`), teed up, NOT yet run.** Site URL isn't in repo code (it's
  in the flows). **Phase 1 (Tim, PnP PowerShell, one-time):** `./Provision-MRA-Lists.ps1 -SiteUrl ".../sites/MRADashboard"`
  then `./Migrate-Data-To-Lists.ps1 -SiteUrl ".../sites/MRADashboard"` (creates the 5 Lists — Users/Jobs/Shop Tasks/Project
  Tasks/Holidays — with exact internal names, then fills from data.js). **Phase 2 (Rich+Claude, GUI, like Safety):** repoint
  4 flows to gomra (Change connection→gomra + Site Address→MRADashboard): **MRA Lists to JSON** (read→data.js), **MRA Lists
  Write 2** (write←dash), **MRA Email** + **MRA Daily My Work Emails** (read MRA Users + Project Tasks trigger). Azure/blob
  flows (EOTM/Fleetio/Design/export) need NO change. Workbook shuttle + fleet path stay on Tandem for now (separate cleanup).
  Tandem stays live as rollback until gomra verified.

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


## 📥 File project mail — `agent.projectMail` in the brief (KEEP IT ALIVE — do NOT drop it)
The dashboard "File project mail" panel (My Work) reads **`agent.json` → `projectMail`** = an array of
`{project,id,link,subject,from,when,pm,snippet}` (id/link are the real Outlook message id + webLink). It groups by
project, shows **📁 File all** (bulk move) per project + per-email **📁 File →**, and flags projects with no Outlook
folder as **⚠ NO BOX**. Recognized folders = `MAIL_BOXES` in `MRA_Dashboard.html`
(`medtronic, trumpf, oakland, cisco, on cloud, swc`) — add a substring when Rich makes a new folder.

⚠️ **THE BUG THAT KEEPS BITING RICH ("my mail disappeared"):** the scheduled brief-refresh republishes `agent.json`
**without** `projectMail`, wiping it. **Any session/scan that republishes `agent.json` MUST preserve + refresh
`projectMail`.** Rule:
1. **Fetch the CURRENT live `agent.json` first** (`https://mrashopdash.z13.web.core.windows.net/agent.json`).
2. **Refresh** `projectMail`: scan **rmiller@gomra.com** inbox (M365 `outlook_email_search`, I'm signed in there) for
   CLIENT/VENDOR project emails, ~last 21 days, grouped by the active projects (`data.js` `projects[].name`). Classify by
   the `[Project]` / `| Project` subject markers + client domain. **EXCLUDE:** "MRA Command Center — you have a new task",
   Fleetio notifications, "Sales Pipeline"/Salesforce report, the Monday exec snapshot, auto accept/decline. Dedup by
   subject (strip `RE:`/`FW:`), keep newest per thread, ≤8 per project. Copy id/link/subject/from/when **verbatim**.
3. If you **can't** refresh (no M365) → **carry forward** the existing `projectMail` from step 1 — never publish without it.
4. Publish via the **Agent Publish** flow (id `71b277ea`) as **`{json: JSON.stringify(agent)}` text/plain** (shape B — raw
   JSON returns 202 but silently doesn't write). URL in scratchpad `agent_publish_url.txt`.
Dashboard-side safety net (rev 36.37): the device keeps a **self-renewing 30-day cache** of `projectMail`
(`mra_mc_pmail_v1`, re-stamped every load even when `agent.json` lacks it), so it can't blank on an active device — but
that's a net, not the fix. The fix is step 1–4 above every refresh. (Filed items track in `mra_mc_filed_v1` + the
"MRA Email Filer" flow, `MAIL_FILE_URL`; they correctly drop off after filing.)

## ⚠️ FOUND + PARTIALLY FIXED 2026-07-30 — 💬 Teams messages panel had NEVER carried real data (Rich: "I have
never gotten 1 message but have had many over the past few days")

**Root cause: same class of bug as the `projectMail` one above, but worse — `teamsMsgs` was never populated with
real data even once.** The My Work panel (`💬 Teams messages`, built earlier as its own task) reads `agent.json`
`teamsMsgs[]` and renders correctly (verified headless — count badge, snippets, ✓ Not for me / ↩ Restore, 💬 Open
chat links all work). But the live `agent.json` had `teamsMsgs:null` — turned out the ONLY prior write to that
field was `agent_with_teams.json` in the scratchpad, which is a **fake test fixture** (`"19:chat1/msg1"`, canned
sample text) built to verify the UI renders, never real scanned Teams data. Whatever process republishes
`agent.json` has simply never included a Teams-scan step.
- **Confirmed the data source itself works fine**: M365 MCP `get_me` shows the connection IS signed in as
  `rmiller@gomra.com` (not blocked/Tandem-only, contrary to an earlier assumption elsewhere in this file — that
  may have been fixed since, or scoped differently; don't assume Tandem-only without checking `get_me` first).
  `teams_list_chats` and `chat_message_search` both return real, current chats/messages (dozens of active 1:1s,
  group chats, meeting chats, messages from today).
- **Fixed for today**: manually built 8 real `teamsMsgs` entries (rule: for each active chat, if the LATEST
  message isn't from Rich, surface it — matches the panel's own code comment) from a live scan (`chat_message_search`
  with a broad query + `afterDateTime`, grouped by `chatId`, kept the newest per chat, filtered to sender ≠ Rich
  Miller), merged into the live `agent.json` (preserving every other field), and published via the same **Agent
  Publish flow** (`agent_publish_url.txt` in scratchpad) used for `projectMail`. Verified headless against the
  real published data: panel shows all 8, count badge correct, dismiss/restore + chat links work.
- **⚠️ NOT actually recurring yet — this was a one-time manual fix, not a running scan.** Whatever job republishes
  `agent.json` on its normal cadence will overwrite this with `teamsMsgs:null` again the next time it runs, UNLESS
  that job's own instructions are updated to include a Teams-scan step. **Rule for any future session/scan that
  republishes `agent.json` (same shape as the `projectMail` rule above): fetch the current live `agent.json` first,
  then refresh `teamsMsgs` — for each of the user's active Teams chats (`teams_list_chats`), find the latest
  message; if its sender isn't Rich, include `{id:chatId+'#'+messageId, who, chat, snippet, when, link, history?}`
  (id must be stable across refreshes so dismissed items via `mcDismissWaitKey` stay dismissed — don't regenerate
  a new id for the same message on every scan). If you can't scan Teams, carry the existing `teamsMsgs` forward —
  never publish `null` over real data.**
- **Confirmed 2026-07-30 (Rich): the 4x/day refresh IS a real Claude Code scheduled Trigger** — Rich: "We set up
  the 4x a day in Claude. Some setting you had me do." So it's a platform Trigger (not a Power Automate flow),
  separate from any one session — but I have no tool in-session to list/inspect/edit Triggers directly, so I still
  don't know its exact stored prompt/instructions. **Next session: ask Rich to open wherever that Trigger lives
  (Claude Code on the web project/environment settings) and paste back what it currently runs**, so its
  instructions can be updated to include the `teamsMsgs` (and now `pricingFinds`, see below) refresh rules.
- **Bridge in place 2026-07-30**: started a same-session `CronCreate` job (every 3h) that re-scans Teams and
  republishes `teamsMsgs` following the rule above, PLUS the pricing-scan and pricing-approval rules below.
  ⚠️ Session-only — dies when this Claude session ends, hard-capped at 7 days regardless. Not a substitute for
  fixing the real Trigger.
- **✅ FOUND + FIXED 2026-07-30.** It's a Claude Code **Routine** (not a "Trigger" — different name, same idea),
  called **"MRA My Command refresh"**, repo `Tandem-Engineering-Group/MRA-Files`, Microsoft 365 connector, schedule
  **6:05 AM / 10:05 AM / 2:05 PM / 6:05 PM, Monday–Friday** (found via Claude Code web UI → sidebar → Routines).
  Rich screenshotted its Instructions box — confirmed root cause: it builds `agent.json` **from scratch every
  run** with only 8 keys (`generatedAt/generatedText/questions/waiting/appts/inbound/projects/tasks`) and POSTs
  that as the WHOLE object — `teamsMsgs`/`pricingFinds` were never in its key list, so every run (weekdays,
  4×/day) silently wiped them back to nothing. **This is the actual mechanism behind the "my mail disappeared"/
  "0 Teams messages" bugs** — not a separate unknown process. Gave Rich full replacement Instructions text (in
  chat, per his standing preference) that: (0) fetches the current live `agent.json` first and carries
  `teamsMsgs`/`pricingFinds` forward instead of building fresh, (2) adds `teamsMsgs`/`pricingFinds` to the managed
  key list with the same field shapes documented above, and folds in the **pricing-approval action** (scan for
  "[Pricing approved]" emails → edit `MATERIALS_REF` in this repo → commit/deploy → clear from `pricingFinds`) so
  Part C doesn't need the session-only bridge cron either.
- **✅ CONFIRMED WORKING 2026-07-30 evening.** Rich saved the new instructions and hit the manual **Run** button
  in the Claude Code UI to test. Verified live: `generatedAt` advanced to a genuinely fresh timestamp (was stuck
  for hours before), `teamsMsgs` came back with 6 real entries from its OWN independent scan (different count
  than this session's manual seed — proof it actually re-ran the scan, not just carried old data forward),
  `pricingFinds` correctly present as `[]` (nothing new to flag, matches this session's own from-scratch email
  sweep earlier the same day), and every original field (waiting/appts/inbound/projects/questions) still came
  through intact. **The routine is the real, durable fix now — the session-only bridge cron has been stopped**
  (nothing left in `CronList`). Next real scheduled run is the normal weekday cadence (6:05/10:05/14:05/18:05).
  ⚠️ Rich also asked for a manual "run it now" button directly on the dashboard's My Work page — investigated
  whether Claude Code Routines expose a copyable webhook/API URL (like the Power Automate flows this dashboard
  already calls); the Runs list has API/Webhook FILTER tabs but neither showed an actual URL to copy as of this
  session — still open, asked Rich to check the pencil/edit view for a dedicated Triggers/Integrations section.
  If no simple webhook URL exists, this may need a real Claude Code API key + authenticated request (bigger
  lift than the usual "paste a flow URL" pattern) — don't build a fake/broken button; confirm the real mechanism
  first.

## ✅ BUILT 2026-07-30 — 📦 "Pricing to review" box on My Work (finds real material/labor quotes, Rich approves/skips)

Rich: "add a box to my work where you look for material quotes and pricing and then add them to my part catalogue
and quote generators. As well as look for labor quotes... I get a box and you give me the story and I say yes or
no to add it." Built as a new My Work panel, same shape/mechanics as the Teams messages panel:
- **UI (live, rev 36.78)**: `agent.json` gets a new `pricingFinds[]` field — `{id, kind:'material'|'labor', item,
  price, unit, source, story, link}`. Panel renders each as a card (item/price/source/story + 🔗 Source link) with
  **✓ Add it** / **✗ Skip** buttons, reusing the exact same `_mcDismissed()`/`mcDismissWaitKey`/`mcRestoreWaitKey`
  dismiss-list mechanism as Teams messages (key prefix `price:` so it doesn't collide). Wired into every layout
  (widget-grid `order`/`newMap`, `_mcLaneDefs`, `_mcChipItems`, `MC_LANES_DEFAULT`) same as every other lane.
- **✓ Add it** (`pfApprove()`) emails the approval decision to rmiller@gomra.com via the same `MC_MAILSEND` channel
  `mcAsk()`/Tell Claude uses, then dismisses the card — **same decide-now-act-later pattern as Tell Claude**:
  Rich's yes is the decision, a FUTURE Claude session reads the approval email and does the actual write.
- **✅ "Act on approval" half BUILT 2026-07-30 (rev 36.79), Rich: "build the 2nd part of the pricing review pls".**
  Both material AND labor approvals land in `MATERIALS_REF` (not `QUOTE_REF` — a single approved line doesn't have
  the shape of a full job quote, so `MATERIALS_REF`'s simple `{family,category,byUnit:[{unit,lowCost,highCost,
  vendors,orders,latest}]}` is the right target for both; labor items just get a `"Labor/…"` category prefix).
  Proved end-to-end on the real seed: the $6,550 chrome-wrap upcharge is now a real `MATERIALS_REF` family
  ("Chrome/Mirror Wrap Finish Upcharge", category "Graphics Media/Vinyl", unit "vehicle") and the card was cleared
  from the live `pricingFinds`. **The recurring bridge cron (Part C)** now does this automatically going forward:
  search rmiller@gomra.com for "[Pricing approved] …" emails → for each, check if that item is STILL in the live
  `pricingFinds` (if it's already gone, already actioned, skip) → if still there, insert the `MATERIALS_REF`
  family, syntax-check, bump CHANGELOG, commit/push/deploy, then remove it from `pricingFinds` and republish.
  Batches multiple pending approvals into one deploy rather than one per item. **Still session-only** (dies with
  this Claude session) — once the durable Trigger's prompt is found/updated (see above), fold Part C into it too.
- **Scan rule for whoever refreshes `agent.json` next (same shape as `projectMail`/`teamsMsgs` above):** search
  rmiller@gomra.com email (`outlook_email_search`, query like "quote"/"pricing", last ~2 weeks) and Teams
  (`chat_message_search`) for real material or labor pricing/quotes NOT already reflected in `MATERIALS_REF`/
  `QUOTE_REF` — a vendor quoting a dollar figure for a specific material/service is a good candidate; vague "we're
  working on pricing" mentions are not. Build `{id (stable — e.g. a hash of the source message id, so re-scans
  don't create duplicate cards for the same finding), kind, item, price, unit, source, story, link}` per find,
  merge into `pricingFinds` (append new ones, don't duplicate existing ids, drop ones Rich already approved/skipped
  if you can tell — check the dismissed-list convention), publish. If you can't scan, carry existing
  `pricingFinds` forward — never publish `null`/`[]` over real unactioned finds.
- **First real seed (2026-07-30)**: a $6,550 full-chrome-wrap material upcharge (vs standard vinyl) from the real
  On x MRA Airstream buildout quote thread (On Running, via Luciana Giglio, 7/28/26 email) — genuine, unactioned,
  not yet in the Catalogue or Quote Generator. Verified headless (renders, count badge, Approve/Skip both wired,
  zero page errors) before publishing.

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
