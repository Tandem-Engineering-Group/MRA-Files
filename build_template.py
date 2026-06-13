#!/usr/bin/env python3
"""Build the standard MRA Project Intake Template (.xlsx).

Mirrors the layout CreateIntakeFile produces in MRA-Entry-Tools.bas so the
downloadable template and the macro-generated file are the same 'standard'.
Project-tasks side only.
"""
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.worksheet.datavalidation import DataValidation

ORANGE = "E24E26"

wb = openpyxl.Workbook()
ws = wb.active
ws.title = "Enter Here"

lst = wb.create_sheet("Lists")

# ---- Lists (dropdown sources) -------------------------------------------
LISTS = {
    "C": ("Phase", ["Phase 1 - Planning", "Phase 2 - Design & Detail",
                     "Phase 3 - Fabrication",
                     "Phase 4 - Electrical & Technology Integration",
                     "Phase 5 - Graphics, Soft Launch / QS / Handover"]),
    "D": ("Type", ["Meeting", "Hard Date", "Design Task", "Materials",
                   "Production Task", "Client"]),
    "E": ("ProjStatus", ["Not Started", "Upcoming", "In Progress",
                         "Completed", "TBD", "N/A"]),
    "F": ("Milestone", ["Yes", "No"]),
    "G": ("PM", ["Megan Fraser", "Al Karloff", "Stephanie Hardie", "Alex Karam",
                 "Luciana Giglio", "Frank Mancina", "Mark St Jean",
                 "Sherri Washington", "Sherrill Buchan", "Cindy Irland",
                 "Mitch Schirr", "Heather Maloney", "TBD"]),
    "H": ("Assigned", ["Megan Fraser", "Al Karloff", "Steve K", "Rich Miller",
                       "Ted O'Malley", "Gino Bitonti", "Sean Payton",
                       "Chris Beyer", "Sarah Williams", "Lindsay Smith",
                       "Kevin R. Sweeney", "Chris Nusbaum", "Luciana Giglio",
                       "MRA Design", "MRA Engineering", "MRA Electrical",
                       "MRA Shop", "MRA Tech", "MRA QA", "MRA Ops",
                       "MRA Procurement", "Art Guild", "Art Guild AV",
                       "W2 Graphics", "Master Wraps", "Logistics", "Fleet",
                       "Vendor", "Client", "All"]),
    "I": ("Project", ["2Heads Global Design Ltd (J1548)", "ABB (J1407)", "Aga Kahn Foundation (J1537)", "Age of Union (J1500)", "Amazon (J1513)", "Arizona 250 (J1554)", "Art Guild (J1563)", "ASICS (J1408)", "AWS (J1217)", "Baltimore Aircoil (J1555)", "Barton Malow (J1506)", "Beckman-Coulter-East (J1396)", "Beckman-Coulter-West (J1396)", "Bell Helicopters (J1440)", "BioMerieux (J1461)", "Booz Allen - US Army (J1527)", "Boston Scientific 40ft (J1491)", "Boston Scientific DX (J1507)", "Boston Scientific SE (J1496)", "BPIR Rodeo (J1468)", "Brain Tumor Foundation (J1481)", "Catholic Charities USA (J1538)", "Cirrus Aircraft (J1549)", "CISCO (J1558)", "Climate Action Campaign (J1560)", "County of Essex (J1467)", "Czarnowski (GA) (J1544)", "D&G - Canada (J1536)", "D&G - USA Midwest (J1535)", "Duracell (J1383)", "Expandable B.V. (J1494)", "Ferguson BizBox (J1557)", "FM Global (J1410)", "Fortinet III (J1476)", "GRAIL (J1470)", "Hershey (J1373)", "Hillrom/Baxter (J1445)", "Hologic (J1551)", "Hyperfine (J1453)", "Hyperfine Box Truck #6110 (J1556)", "Jewish Federation (J1526)", "Knightscope (J1447)", "LexCare Hearoes (J1546)", "Medtronic (J1553)", "Meijer (J1143)", "Mkt/Grinder (J1511)", "Moon Surgical (J1509)", "MOTT (J1428)", "MRA Internal (J1014)", "NHL United by Hockey (J1495)", "NYBC Pod #1 (J1517)", "NYBC Pod #2 (J1531)", "NYBC Pod #3 (J1532)", "NYBC Pod #4 (J1533)", "Oakland Schools (J1420)", "Oasis Live '25 - The Department (J1539)", "Omnicell (J1446)", "On Running (J1559)", "P&G - Tide (J1521)", "PGA of Americas (J1519)", "Promaster Retro-Fit (J1775)", "PSE&G / Impact XM (J1508)", "QuidelOrtho (J1384)", "Road Show Group (J1774)", "RoadShowGrp / ShowTruckMktng (J1530)", "Saskatchewan Health Authority (J1545)", "Schaeffler (J1497)", "Score (Canada) Limited (J1523)", "SEMI Foundation (J1550)", "SENO Medical (J1454)", "SENO Medical - Box Truck (J1541)", "Siemens Big Betty (J1381)", "Siemens Canada (J1501)", "Siemens Demo Pool (J1209)", "Siemens DI (J1524)", "Siemens DX #3005 (J1110W)", "Siemens DX #92 (J1110E)", "Siemens Global Warehousing (J1391)", "Siemens Mammo III (J1480)", "Siemens Mammo Mandy (J1424)", "Sigenergy (J1562)", "Simon Wiesenthal Center - MA (Massachusetts) (J1552)", "SMC Corporation (J1542)", "Sobeys/Safeway (J1400)", "STI Pod - #1052 (J1561)", "Stryker (J1412)", "SWC California (J1486)", "SWC Florida 1 (J1514)", "SWC Florida 2 (J1515)", "SWC Hawaii (J1512)", "SWC Illinois (J1422)", "SWC NY1 (J1487)", "SWC NY2 (J1488)", "Tim McGraw (J1421)", "Tissot US MotoGP (J1529)", "TravisMathew (J1387)", "Warhammer (J1434)", "Washtenaw Community College (J1543)", "Weill Cornell Imaging (J1540)", "WFCU (J1479)", "Windsor Champ (J1519)", "Winnipeg Regional Health Authority (J1547)"]),
}
for col, (head, vals) in LISTS.items():
    lst[f"{col}1"] = head
    for i, v in enumerate(vals):
        lst[f"{col}{i+2}"] = v
lst.sheet_state = "veryHidden"

# ---- Header row ----------------------------------------------------------
heads = ["Project", "Phase", "Type", "Task", "Start", "Finish", "Duration",
         "Assigned To", "Status", "PM", "Milestone", "Comments"]
for c, h in enumerate(heads, start=1):
    cell = ws.cell(row=1, column=c, value=h)
    cell.font = Font(bold=True, color="FFFFFF")
    cell.fill = PatternFill("solid", fgColor=ORANGE)
    cell.alignment = Alignment(vertical="center")
ws.row_dimensions[1].height = 22

# ---- Phase 1-5 skeleton rows --------------------------------------------
phases = LISTS["C"][1]
r = 2
for ph in phases:
    ws.cell(row=r, column=2, value=ph)        # Phase
    ws.cell(row=r, column=9, value="Not Started")  # Status
    ws.cell(row=r, column=11, value="No")     # Milestone
    r += 1

# ---- Dropdowns -----------------------------------------------------------
def add_dv(col_letter, src):
    dv = DataValidation(type="list", formula1=src, allow_blank=True,
                        showDropDown=False)
    ws.add_data_validation(dv)
    dv.add(f"{col_letter}2:{col_letter}300")

add_dv("A", "=Lists!$I$2:$I$103")
add_dv("B", "=Lists!$C$2:$C$6")
add_dv("C", "=Lists!$D$2:$D$7")
add_dv("H", "=Lists!$H$2:$H$31")
add_dv("I", "=Lists!$E$2:$E$7")
add_dv("J", "=Lists!$G$2:$G$14")
add_dv("K", "=Lists!$F$2:$F$3")

# ---- Sizing, filter, tip -------------------------------------------------
for col in "ABCDEFGHIJKL":
    ws.column_dimensions[col].width = 16
ws.column_dimensions["D"].width = 40
ws.auto_filter.ref = "A1:L1"

# Pre-format Start/Finish as real dates so typed values parse correctly
# (the dashboard only reads dates from genuine date cells, not text).
for row in range(2, 301):
    ws[f"E{row}"].number_format = "m/d/yyyy"
    ws[f"F{row}"].number_format = "m/d/yyyy"

tip = ("Tip: pick your Project (A), then fill Task, Start/Finish dates and "
       "Assigned for each phase. Add rows as needed; delete phases you don't "
       "use. When done, save this file and drop it in the team 'Intake Inbox' "
       "folder (ask your PM for the link) — it imports into the schedule "
       "automatically. Use real dates in Start/Finish (e.g. 6/15/26).")
ws["N2"] = tip
ws["N2"].font = Font(italic=True)
ws.freeze_panes = "A2"

wb.save("/home/user/MRA-Files/MRA_Project_Intake_Template.xlsx")
print("wrote MRA_Project_Intake_Template.xlsx")
