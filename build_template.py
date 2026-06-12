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
    "I": ("Project", ["Medtronic", "Oakland Schools", "Trumpf", "Cisco",
                      "Washtenaw", "Siemens DI Pedestal", "SWC HI [CMI]",
                      "SMC [Hamilton]", "Thunder Bay MRI Bus",
                      "Siemens 53ft Replacement #1",
                      "Siemens 53ft Replacement #2", "Stryker"]),
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

add_dv("A", "=Lists!$I$2:$I$13")
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

tip = ("Tip: pick your Project (A), then fill Task, Start/Finish dates and "
       "Assigned for each phase. Add rows as needed; delete phases you don't "
       "use. Save and send back — it gets imported into the master schedule.")
ws["N2"] = tip
ws["N2"].font = Font(italic=True)
ws.freeze_panes = "A2"

wb.save("/home/user/MRA-Files/MRA_Project_Intake_Template.xlsx")
print("wrote MRA_Project_Intake_Template.xlsx")
