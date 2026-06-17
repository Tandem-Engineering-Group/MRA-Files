#!/usr/bin/env python3
"""Build the standard MRA Project Intake Template (.xlsx).

Layout (2026-06-17): a letterhead + a one-time info block (Project / Job # / PM),
then a task table that MIRRORS the master 'Project Tasks' sheet — same columns AND
the same look (dark header, gold milestone rows) so an upload/paste is an easy match.

Task table = master cols A..N:
    A=Project  B=Phase  C=Type  D=Task  E=Start  F=Finish  G=Duration
    H=Assigned To  I=Status  J=PM  K=Milestone  L=Comments  M=Task ID  N=Predecessor

Project (A) and PM (J) auto-fill down from the info-block boxes via formula (type once).
M=Task ID is assigned by the system on import (leave blank); N=Predecessor is by Task ID,
so it's system-managed too — both are shown greyed to match the sheet. The template ships
with 10 gold-shaded milestone rows (Milestone 1..10) as a ready scaffold.

Import-Intake.ps1 reads this sheet back (MIRROR layout: header A="Project" & D="Task").
Change a label/column here -> update the matching reader in Import-Intake.ps1.
"""
import os
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.drawing.image import Image as XLImage

HERE = os.path.dirname(os.path.abspath(__file__))
ORANGE = "E24E26"
NAVY = "1F3864"    # dark header band — matches the master Project Tasks sheet
GOLD = "FFE699"    # milestone row shading — matches the master
DARK = "1F2430"
GREY = "6B7280"
FIELD = "FFF7F4"   # very light orange tint for fill-in cells
AUTO = "F3F4F6"    # light grey for auto-filled / system columns (Project, PM, Task ID, Predecessor)

wb = openpyxl.Workbook()
ws = wb.active
ws.title = "Enter Here"

# ---- Lists sheet (dropdown sources; Project is intentionally NOT here) ------
lst = wb.create_sheet("Lists")
LISTS = {
    "B": ("Phase", ["Project Planning", "Creative Design", "Design & Detail",
                    "Fabrication", "Production",
                    "Electrical & Technology", "Graphics",
                    "Post Production", "Launch"]),
    "C": ("Type", ["Meeting", "Hard Date", "Design Task", "Materials",
                   "Production Task", "Client", "Logistics", "QA",
                   "Milestone"]),
    # Status MUST match the dashboard editor (PROJ_STATUS_OPTIONS).
    "D": ("Status", ["Not Started", "In Progress", "Completed", "On Hold"]),
    "E": ("Milestone", ["Yes", "No"]),
    "F": ("PM", ["Megan Fraser", "Al Karloff", "Stephanie Hardie", "Alex Karam",
                 "Luciana Giglio", "Frank Mancina", "Mark St Jean",
                 "Sherri Washington", "Sherrill Buchan", "Cindy Irland",
                 "Mitch Schirr", "Heather Maloney", "TBD"]),
    # Assigned To = canonical project assignees (orgs/groups + key people).
    # Editable here on the hidden Lists sheet; the column also accepts free text.
    "G": ("Assigned", ["MRA", "MRA Shop", "Combined Effort", "Megan Fraser",
                       "Al Karloff", "Gino Bitonti", "Sal", "Doug",
                       "MasterWraps", "Electricians", "Vendor", "Medtronic",
                       "Learning Undefeated", "IXL/TSS", "Brinkbit",
                       "Siemens DI", "Heitek", "Other"]),
}
for col, (head, vals) in LISTS.items():
    lst[f"{col}1"] = head
    for i, v in enumerate(vals):
        lst[f"{col}{i+2}"] = v
lst.sheet_state = "veryHidden"

# ---- Column widths (task table mirrors master A..N) -------------------------
widths = {"A": 26, "B": 18, "C": 13, "D": 42, "E": 11, "F": 11, "G": 9,
          "H": 20, "I": 13, "J": 15, "K": 10, "L": 26, "M": 9, "N": 12}
for c, w in widths.items():
    ws.column_dimensions[c].width = w

thin = Side(style="thin", color="D1D5DB")
box = Border(left=thin, right=thin, top=thin, bottom=thin)
bottom = Border(bottom=Side(style="thin", color="C9CDD3"))

# ---- Letterhead -------------------------------------------------------------
logo_path = os.path.join(HERE, "logo.png")
if os.path.exists(logo_path):
    img = XLImage(logo_path)
    img.width = 104
    img.height = 104
    ws.add_image(img, "A1")

for r, h in {1: 26, 2: 24, 3: 16, 4: 20, 5: 8}.items():
    ws.row_dimensions[r].height = h

ws.merge_cells("C1:N2")
t = ws["C1"]
t.value = "PROJECT INTAKE  —  TASK SCHEDULE"
t.font = Font(bold=True, size=20, color=ORANGE)
t.alignment = Alignment(vertical="center")

ws.merge_cells("C3:N3")
a = ws["C3"]
a.value = "950 E Whitcomb Ave  ·  Madison Heights, MI 48071  ·  p 248.629.2929 / f 248.629.2921"
a.font = Font(size=9, color=GREY)

ws.merge_cells("C4:N4")
d = ws["C4"]
d.value = ("Fill this out, then upload it on the dashboard (Projects ▸ ⬆ Upload Filled Template) "
           "or drop it in the Intake Inbox folder — or copy the task rows and Paste → Values into "
           "the master Project Tasks sheet.")
d.font = Font(size=9, italic=True, color=GREY)

# ---- Info block (one-time header fields) ------------------------------------
def label(ref, text):
    c = ws[ref]
    c.value = text
    c.font = Font(bold=True, size=10, color=DARK)
    c.alignment = Alignment(horizontal="right", vertical="center")

def field(top_left, span_to, prompt=None, title=None):
    ws.merge_cells(f"{top_left}:{span_to}")
    c = ws[top_left]
    c.fill = PatternFill("solid", fgColor=FIELD)
    c.border = bottom
    c.alignment = Alignment(vertical="center", indent=1)
    c.font = Font(size=11, color=DARK)
    if prompt:
        dv = DataValidation(allow_blank=True, showInputMessage=True,
                            showErrorMessage=False, prompt=prompt, promptTitle=title or "")
        ws.add_data_validation(dv)
        dv.add(top_left)
    return c

INFO0 = 6   # Project field = B6, PM field = B7 (referenced by the autofill formulas)
for i, rr in enumerate((INFO0, INFO0 + 1, INFO0 + 2)):
    ws.row_dimensions[rr].height = 20

label(f"A{INFO0}", "Project / Client:")
field(f"B{INFO0}", f"D{INFO0}", title="Project / Client",
      prompt="Type the project name. Brand-new jobs are welcome - just type it. It auto-fills down column A.")
label(f"F{INFO0}", "MRA Job #:")
field(f"G{INFO0}", f"H{INFO0}", title="MRA Job #",
      prompt='Job number if you have one, or type "NEW".')

label(f"A{INFO0+1}", "Project Manager:")
field(f"B{INFO0+1}", f"D{INFO0+1}", title="Project Manager",
      prompt="The PM for this project — auto-fills down column J.")
label(f"F{INFO0+1}", "Issue Date:")
field(f"G{INFO0+1}", f"H{INFO0+1}")

label(f"A{INFO0+2}", "Prepared By:")
field(f"B{INFO0+2}", f"D{INFO0+2}")
label(f"F{INFO0+2}", "Attn / Client Contact:")
field(f"G{INFO0+2}", f"H{INFO0+2}")

# ---- Task table header (dark band, like the master sheet) -------------------
HDR = INFO0 + 4
ws.row_dimensions[HDR - 1].height = 8
heads = ["Project", "Phase", "Type", "Task", "Start", "Finish", "Duration",
         "Assigned To", "Status", "PM", "Milestone", "Comments", "Task ID", "Predecessor"]
LEFT_COLS = {1, 2, 4, 8, 10, 12}
for c, h in enumerate(heads, start=1):
    cell = ws.cell(row=HDR, column=c, value=h)
    cell.font = Font(bold=True, color="FFFFFF", size=11)
    cell.fill = PatternFill("solid", fgColor=NAVY)
    cell.alignment = Alignment(vertical="center",
                               horizontal="left" if c in LEFT_COLS else "center",
                               indent=1 if c in LEFT_COLS else 0)
    cell.border = box
ws.row_dimensions[HDR].height = 24

# ---- Body ------------------------------------------------------------------
DATA0 = HDR + 1
NMILE = 10                      # ship 10 gold milestone scaffold rows
LASTROW = DATA0 + 300
auto_fill = PatternFill("solid", fgColor=AUTO)
gold_fill = PatternFill("solid", fgColor=GOLD)
projF = '=IF($B$%d="","",$B$%d)' % (INFO0, INFO0)
pmF = '=IF($B$%d="","",$B$%d)' % (INFO0 + 1, INFO0 + 1)

for idx, r in enumerate(range(DATA0, LASTROW)):
    is_mile = idx < NMILE
    for c in range(1, 15):     # A..N
        ws.cell(row=r, column=c).border = box
    ws.cell(row=r, column=1, value=projF)      # A Project (autofill)
    ws.cell(row=r, column=10, value=pmF)       # J PM (autofill)
    ws.cell(row=r, column=5).number_format = "m/d/yyyy"   # Start
    ws.cell(row=r, column=6).number_format = "m/d/yyyy"   # Finish
    if is_mile:
        ws.cell(row=r, column=3, value="Milestone")        # C Type
        ws.cell(row=r, column=4, value="Milestone %d" % (idx + 1))  # D Task
        ws.cell(row=r, column=9, value="Not Started")      # I Status
        ws.cell(row=r, column=11, value="Yes")             # K Milestone
        for c in range(1, 15):
            ws.cell(row=r, column=c).fill = gold_fill
    else:
        ws.cell(row=r, column=1).fill = auto_fill          # A grey (autofill)
        ws.cell(row=r, column=10).fill = auto_fill         # J grey (autofill)
        ws.cell(row=r, column=13).fill = auto_fill         # M Task ID (system)
        ws.cell(row=r, column=14).fill = auto_fill         # N Predecessor (system)

# ---- Dropdowns (Project/PM auto-filled; Task ID/Predecessor system) ---------
def add_dv(col_letter, src, last=LASTROW - 1):
    dv = DataValidation(type="list", formula1=src, allow_blank=True,
                        showErrorMessage=False, showDropDown=False)
    ws.add_data_validation(dv)
    dv.add(f"{col_letter}{DATA0}:{col_letter}{last}")

add_dv("B", "=Lists!$B$2:$B$10")   # Phase
add_dv("C", "=Lists!$C$2:$C$10")   # Type
add_dv("H", "=Lists!$G$2:$G$19")   # Assigned To
add_dv("I", "=Lists!$D$2:$D$5")    # Status
add_dv("K", "=Lists!$E$2:$E$3")    # Milestone
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
print("wrote", out, "| header row", HDR, "| data starts", DATA0, "| milestone rows", NMILE)
