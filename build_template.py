#!/usr/bin/env python3
"""Build the standard MRA Project Intake Template (.xlsx).

Professional, branded layout modeled on the customer Hard-Date Schedule:
a letterhead (logo + address), a one-time info block (Project / Job # / PM /
dates -- Project & Job# are FREE TEXT because ~half of intakes are brand-new
jobs), then a clean task table.

Import-Intake.ps1 reads this sheet back. The two MUST stay in sync:
  * Info block labels:  "Project / Client", "MRA Job #", "Project Manager"
  * Task table header row:  A="Phase", B="Type", C="Task", D="Start",
                            E="Finish", F="Duration", G="Assigned To",
                            H="Status", I="Milestone", J="Comments"
  * Task data starts on the row after that header.
Change a label or column here -> update the matching reader in Import-Intake.ps1.
"""
import os
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.drawing.image import Image as XLImage

HERE = os.path.dirname(os.path.abspath(__file__))
ORANGE = "E24E26"
DARK = "1F2430"
GREY = "6B7280"
FIELD = "FFF7F4"   # very light orange tint for fill-in cells

wb = openpyxl.Workbook()
ws = wb.active
ws.title = "Enter Here"

# ---- Lists sheet (dropdown sources; Project is intentionally NOT here) ------
lst = wb.create_sheet("Lists")
LISTS = {
    "B": ("Phase", ["Phase 1 - Planning", "Phase 2 - Design & Detail",
                     "Phase 3 - Fabrication",
                     "Phase 4 - Electrical & Technology Integration",
                     "Phase 5 - Graphics, Soft Launch / QS / Handover"]),
    "C": ("Type", ["Meeting", "Hard Date", "Design Task", "Materials",
                   "Production Task", "Client", "Logistics", "QA"]),
    "D": ("Status", ["Not Started", "Upcoming", "In Progress",
                     "Completed", "TBD", "N/A"]),
    "E": ("Milestone", ["Yes", "No"]),
    "F": ("PM", ["Megan Fraser", "Al Karloff", "Stephanie Hardie", "Alex Karam",
                 "Luciana Giglio", "Frank Mancina", "Mark St Jean",
                 "Sherri Washington", "Sherrill Buchan", "Cindy Irland",
                 "Mitch Schirr", "Heather Maloney", "TBD"]),
    "G": ("Assigned", ["Megan Fraser", "Al Karloff", "Steve K", "Rich Miller",
                       "Ted O'Malley", "Gino Bitonti", "Sean Payton",
                       "Chris Beyer", "Sarah Williams", "Lindsay Smith",
                       "Kevin R. Sweeney", "Chris Nusbaum", "Luciana Giglio",
                       "MRA Design", "MRA Engineering", "MRA Electrical",
                       "MRA Shop", "MRA Tech", "MRA QA", "MRA Ops",
                       "MRA Procurement", "Art Guild", "Art Guild AV",
                       "W2 Graphics", "Master Wraps", "Logistics", "Fleet",
                       "Vendor", "Client", "All"]),
}
for col, (head, vals) in LISTS.items():
    lst[f"{col}1"] = head
    for i, v in enumerate(vals):
        lst[f"{col}{i+2}"] = v
lst.sheet_state = "veryHidden"

# ---- Column widths (task table: A..J) ---------------------------------------
widths = {"A": 34, "B": 15, "C": 46, "D": 12, "E": 12,
          "F": 10, "G": 22, "H": 15, "I": 11, "J": 30}
for c, w in widths.items():
    ws.column_dimensions[c].width = w

thin = Side(style="thin", color="D1D5DB")
box = Border(left=thin, right=thin, top=thin, bottom=thin)
bottom = Border(bottom=Side(style="thin", color="C9CDD3"))

# ---- Letterhead -------------------------------------------------------------
# Logo (orange MRA mark) floats over the left of the wide column A.
logo_path = os.path.join(HERE, "logo.png")
if os.path.exists(logo_path):
    img = XLImage(logo_path)
    img.width = 104
    img.height = 104
    ws.add_image(img, "A1")

for r, h in {1: 26, 2: 24, 3: 16, 4: 20, 5: 8}.items():
    ws.row_dimensions[r].height = h

ws.merge_cells("C1:J2")
t = ws["C1"]
t.value = "PROJECT INTAKE  —  TASK SCHEDULE"
t.font = Font(bold=True, size=20, color=ORANGE)
t.alignment = Alignment(vertical="center")

ws.merge_cells("C3:J3")
a = ws["C3"]
a.value = "950 E Whitcomb Ave  ·  Madison Heights, MI 48071  ·  p 248.629.2929 / f 248.629.2921"
a.font = Font(size=9, color=GREY)

ws.merge_cells("C4:J4")
d = ws["C4"]
d.value = ("Fill this out, then drop it in the Intake Inbox folder - it imports "
           "into the shop schedule automatically.")
d.font = Font(size=9, italic=True, color=GREY)

# ---- Info block (one-time header fields) ------------------------------------
def label(ref, text):
    c = ws[ref]
    c.value = text
    c.font = Font(bold=True, size=10, color=DARK)
    c.alignment = Alignment(horizontal="right", vertical="center")

def field(top_left, span_to, prompt=None, title=None):
    """A fill-in cell. Hint (if any) is an on-select tooltip, NOT a stored
    value, so the importer never mistakes a placeholder for real data."""
    ws.merge_cells(f"{top_left}:{span_to}")
    c = ws[top_left]
    c.fill = PatternFill("solid", fgColor=FIELD)
    c.border = bottom
    c.alignment = Alignment(vertical="center", indent=1)
    c.font = Font(size=11, color=DARK)
    if prompt:
        dv = DataValidation(allow_blank=True, showInputMessage=True,
                            showErrorMessage=False,
                            prompt=prompt, promptTitle=title or "")
        ws.add_data_validation(dv)
        dv.add(top_left)
    return c

INFO0 = 6   # first info row
for i, rr in enumerate((INFO0, INFO0 + 1, INFO0 + 2)):
    ws.row_dimensions[rr].height = 20

label(f"A{INFO0}", "Project / Client:")
field(f"B{INFO0}", f"D{INFO0}", title="Project / Client",
      prompt="Type the project name. Brand-new jobs are welcome - just type it.")
label(f"F{INFO0}", "MRA Job #:")
field(f"G{INFO0}", f"H{INFO0}", title="MRA Job #",
      prompt='Job number if you have one, or type "NEW".')

label(f"A{INFO0+1}", "Project Manager:")
field(f"B{INFO0+1}", f"D{INFO0+1}")
label(f"F{INFO0+1}", "Issue Date:")
field(f"G{INFO0+1}", f"H{INFO0+1}")

label(f"A{INFO0+2}", "Prepared By:")
field(f"B{INFO0+2}", f"D{INFO0+2}")
label(f"F{INFO0+2}", "Attn / Client Contact:")
field(f"G{INFO0+2}", f"H{INFO0+2}")

# ---- Task table -------------------------------------------------------------
HDR = INFO0 + 4                       # blank spacer row between info & table
ws.row_dimensions[HDR - 1].height = 8
heads = ["Phase", "Type", "Task", "Start", "Finish", "Duration",
         "Assigned To", "Status", "Milestone", "Comments"]
for c, h in enumerate(heads, start=1):
    cell = ws.cell(row=HDR, column=c, value=h)
    cell.font = Font(bold=True, color="FFFFFF", size=11)
    cell.fill = PatternFill("solid", fgColor=ORANGE)
    cell.alignment = Alignment(vertical="center",
                               horizontal="left" if c in (1, 3, 7, 10) else "center",
                               indent=1 if c in (1, 3, 7, 10) else 0)
    cell.border = box
ws.row_dimensions[HDR].height = 24

# Phase 1-5 skeleton rows
DATA0 = HDR + 1
phases = LISTS["B"][1]
for i, ph in enumerate(phases):
    r = DATA0 + i
    ws.cell(row=r, column=1, value=ph)             # A Phase
    ws.cell(row=r, column=8, value="Not Started")  # H Status
    ws.cell(row=r, column=9, value="No")           # I Milestone

# Light borders + date format down the table body
LASTROW = DATA0 + 300
for r in range(DATA0, LASTROW):
    for c in range(1, 11):
        ws.cell(row=r, column=c).border = box
    ws.cell(row=r, column=4).number_format = "m/d/yyyy"  # Start
    ws.cell(row=r, column=5).number_format = "m/d/yyyy"  # Finish

# ---- Dropdowns (Project deliberately omitted - free text) -------------------
def add_dv(col_letter, src, last=LASTROW - 1):
    dv = DataValidation(type="list", formula1=src, allow_blank=True,
                        showErrorMessage=False, showDropDown=False)
    ws.add_data_validation(dv)
    dv.add(f"{col_letter}{DATA0}:{col_letter}{last}")

add_dv("A", "=Lists!$B$2:$B$6")    # Phase
add_dv("B", "=Lists!$C$2:$C$9")    # Type
add_dv("H", "=Lists!$D$2:$D$7")    # Status
add_dv("I", "=Lists!$E$2:$E$3")    # Milestone
add_dv("G", "=Lists!$G$2:$G$31")   # Assigned To
# PM dropdown on the info-block PM field
dv_pm = DataValidation(type="list", formula1="=Lists!$F$2:$F$14",
                       allow_blank=True, showErrorMessage=False, showDropDown=False)
ws.add_data_validation(dv_pm)
dv_pm.add(f"B{INFO0+1}")

# ---- Final touches ----------------------------------------------------------
ws.freeze_panes = f"A{DATA0}"
ws.sheet_view.showGridLines = False
ws.print_options.horizontalCentered = True
ws.page_setup.orientation = "landscape"
ws.page_setup.fitToWidth = 1
ws.page_setup.fitToHeight = 0
ws.sheet_properties.pageSetUpPr.fitToPage = True
ws.page_margins.left = ws.page_margins.right = 0.4
ws.page_margins.top = ws.page_margins.bottom = 0.5

out = os.path.join(HERE, "MRA_Project_Intake_Template.xlsx")
wb.save(out)
print("wrote", out, "| header row", HDR, "| data starts", DATA0)
