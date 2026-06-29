# MRA Workbook — Easier Data Entry (setup guide)

Goal: make it easy for a team member to **find, edit, and add** rows without
scrolling hundreds of lines or mistyping values. Two source sheets:
**Input** (shop floor — one row per trailer) and **Project Tasks** (projects —
many rows per project).

> **Back up first:** File → Save a Copy → `MRA_Shop_Board_BACKUP`. The live
> dashboard reads this file, so work on a copy until you're happy.

---

## Fastest path: run the macro (Setup-Entry.bas)
This does the whole setup *inside Excel* (lossless — nothing in your workbook
is stripped):

1. Open `MRA_Shop_Board_v6_9_7.xlsx`.
2. Press **Alt+F11** → **Insert → Module** → paste the contents of
   `Setup-Entry.bas` → press **F5** and run **SetupMRAEntry**.
3. Close the editor → **File → Save** (keep it **.xlsx** / same name). If Excel
   warns about macros on save, choose **Yes** to save without the macro — the
   dropdowns and Lists sheet stay.

It creates a hidden **Lists** sheet, adds all the dropdowns below, and turns on
the **Project filter** so you can show one project at a time.

*(If your IT blocks macros, use the manual steps below — same result.)*

---

## Manual setup (if you prefer, or macros are blocked)

### 1) Lists sheet (dropdown source)
New sheet named **Lists**; in row 1 add these headers and fill the values down:

- **Bay:** Bay 2 Front, Bay 2 Back, Bay 3 Front, Bay 3 Back, Bay 4 Front, Bay 4 Back, Bay 5 Front, Bay 5 Back, Parking Lot, On Hold/Off-Site, Next Up, APL/Holidays
- **ShopStatus:** Active, Scheduled, On Hold, Shipped, Done, Leave, TBD
- **Phase:** Phase 1 - Planning, Phase 2 - Design & Detail, Phase 3 - Fabrication, Phase 4 - Electrical & Technology Integration, Phase 5 - Graphics, Soft Launch / QS / Handover
- **Type:** Meeting, Hard Date, Design Task, Materials, Production Task, Client
- **ProjStatus:** Not Started, Upcoming, In Progress, Completed, TBD, N/A
- **Milestone:** Yes, No
- **PM:** Megan Fraser, Al Karloff, Stephanie Hardie, Alex Karam, Luciana Giglio, Frank Mancina, Mark St Jean, Sherri Washington, Sherrill Buchan, Cindy Irland, Mitch Schirr, Heather Maloney, TBD
- **Assigned:** Megan Fraser, Al Karloff, Steve K, Rich Miller, Ted O'Malley, Gino Bitonti, Sean Payton, Chris Beyer, Sarah Williams, Lindsay Smith, Kevin R. Sweeney, Chris Nusbaum, Luciana Giglio, MRA Design, MRA Engineering, MRA Electrical, MRA Shop, MRA Tech, MRA QA, MRA Ops, MRA Procurement, Art Guild, Art Guild AV, W2 Graphics, Master Wraps, Logistics, Fleet, Vendor, Client, All
- **Project:** Medtronic, Oakland Schools, Trumpf, Cisco, Washtenaw, Siemens DI Pedestal, SWC HI [CMI], SMC [Hamilton], Thunder Bay MRI Bus, Siemens 53ft Replacement #1, Siemens 53ft Replacement #2, Stryker

Then right-click the Lists tab → **Hide**.

### 2) Project Tasks sheet
- Ensure row 1 is one clean header row: Project | Phase | Type | Task | Start | Finish | Duration | Assigned To | Status | PM | Milestone | Comments.
- Click a data cell → **Insert → Table** (check "My table has headers").
- **Table Design → Insert Slicer** → Project, Phase, Status, Milestone. Click a project to show only its rows.
- **Data → Data Validation → List** on each column, Source = the matching Lists range:
  Project `=Lists!$I$2:$I$13`, Phase `=Lists!$C$2:$C$6`, Type `=Lists!$D$2:$D$7`,
  Assigned To `=Lists!$H...`, Status `=Lists!$E$2:$E$7`, PM `=Lists!$G...`, Milestone `=Lists!$F$2:$F$3`.

### 3) Input (shop) sheet
- Move the "HOW TO USE STATUS" legend off the data area so there's one clean header row.
- Insert → Table; add a **Bay** (and Status) slicer.
- Dropdowns: Bay `=Lists!$A$2:$A$13`, Status `=Lists!$B$2:$B$8`, PM `=Lists!$G...`.

---

## One-time cleanup (makes filters/dropdowns clean — also improves the dashboard)
- **Phase:** standardize the two "Phase 5" variants to one; replace "Schedule (from Al)" with a real phase.
- **Project names:** consistent spelling everywhere (e.g., "Siemens" not "Seimans").
- **Assigned To:** decide whether "A / B" combos stay or get a single owner (this powers Team Capacity).

## Guardrails (so the dashboard keeps working)
- Do **not** reorder or insert columns in the middle, and do **not** move the data
  up/down from where it starts (Input data on its current row; Project Tasks from row 2).
  Tables, slicers, dropdowns, filters, and grouping are all safe — they don't move data.
- Leave the **Milestone (Yes/No)** column as-is — it drives the Gantt's milestone gates.
- You only edit the workbook. Never edit the dashboard or `data.js` by hand.
