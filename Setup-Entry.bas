' ============================================================================
'  MRA workbook - one-time data-entry setup
'  Adds a hidden "Lists" sheet, dropdown menus on the Input + Project Tasks
'  sheets, and turns on the Project filter. Runs entirely inside Excel
'  (nothing in your workbook is stripped). Run ONCE, then save as .xlsx.
'
'  HOW TO RUN:
'   1) Open MRA_Shop_Board_v6_9_7.xlsx
'   2) Press Alt+F11 (VBA editor) -> Insert -> Module -> paste all of this
'   3) Press F5 (or Run > Run Sub) -> pick SetupMRAEntry
'   4) Close the editor, then File > Save. If it warns about macros,
'      choose "Yes" to save as .xlsx (keep the same name) - the dropdowns
'      and Lists stay; the macro itself isn't needed again.
' ============================================================================
Option Explicit

Sub SetupMRAEntry()
    Dim wb As Workbook: Set wb = ThisWorkbook
    Dim lst As Worksheet, ws As Worksheet
    Application.ScreenUpdating = False
    Application.DisplayAlerts = False

    ' --- (re)create the hidden Lists sheet ---
    On Error Resume Next: wb.Sheets("Lists").Delete: On Error GoTo 0
    Set lst = wb.Sheets.Add(After:=wb.Sheets(wb.Sheets.Count)): lst.Name = "Lists"

    Dim heads As Variant
    heads = Array("Bay", "ShopStatus", "Phase", "Type", "ProjStatus", "Milestone", "PM", "Assigned", "Project")
    Dim c As Long
    For c = 0 To UBound(heads): lst.Cells(1, c + 1).Value = heads(c): Next c

    WriteCol lst, 1, Array("Bay 2 Front", "Bay 2 Back", "Bay 3 Front", "Bay 3 Back", "Bay 4 Front", "Bay 4 Back", "Bay 5 Front", "Bay 5 Back", "Parking Lot", "On Hold/Off-Site", "Next Up", "APL/Holidays")
    WriteCol lst, 2, Array("Active", "Scheduled", "On Hold", "Shipped", "Done", "Leave", "TBD")
    WriteCol lst, 3, Array("Phase 1 - Planning", "Phase 2 - Design & Detail", "Phase 3 - Fabrication", "Phase 4 - Electrical & Technology Integration", "Phase 5 - Graphics, Soft Launch / QS / Handover")
    WriteCol lst, 4, Array("Meeting", "Hard Date", "Design Task", "Materials", "Production Task", "Client")
    WriteCol lst, 5, Array("Not Started", "Upcoming", "In Progress", "Completed", "TBD", "N/A")
    WriteCol lst, 6, Array("Yes", "No")
    WriteCol lst, 7, Array("Megan Fraser", "Al Karloff", "Stephanie Hardie", "Alex Karam", "Luciana Giglio", "Frank Mancina", "Mark St Jean", "Sherri Washington", "Sherrill Buchan", "Cindy Irland", "Mitch Schirr", "Heather Maloney", "TBD")
    WriteCol lst, 8, Array("Megan Fraser", "Al Karloff", "Steve K", "Rich Miller", "Ted O'Malley", "Gino Bitonti", "Sean Payton", "Chris Beyer", "Sarah Williams", "Lindsay Smith", "Kevin R. Sweeney", "Chris Nusbaum", "Luciana Giglio", "MRA Design", "MRA Engineering", "MRA Electrical", "MRA Shop", "MRA Tech", "MRA QA", "MRA Ops", "MRA Procurement", "Art Guild", "Art Guild AV", "W2 Graphics", "Master Wraps", "Logistics", "Fleet", "Vendor", "Client", "All")
    WriteCol lst, 9, Array("Medtronic", "Oakland Schools", "Trumpf", "Cisco", "Washtenaw", "Siemens DI Pedestal", "SWC HI [CMI]", "SMC [Hamilton]", "Thunder Bay MRI Bus", "Siemens 53ft Replacement #1", "Siemens 53ft Replacement #2", "Stryker")

    NameCol wb, lst, 1, "L_Bay"
    NameCol wb, lst, 2, "L_ShopStatus"
    NameCol wb, lst, 3, "L_Phase"
    NameCol wb, lst, 4, "L_Type"
    NameCol wb, lst, 5, "L_ProjStatus"
    NameCol wb, lst, 6, "L_Milestone"
    NameCol wb, lst, 7, "L_PM"
    NameCol wb, lst, 8, "L_Assigned"
    NameCol wb, lst, 9, "L_Project"

    ' --- Input sheet dropdowns (Bay=A, Status=G, PM=K; data from row 4) ---
    On Error Resume Next
    Set ws = wb.Sheets("Input")
    On Error GoTo 0
    If Not ws Is Nothing Then
        ApplyDV ws, "A", 4, "L_Bay"
        ApplyDV ws, "G", 4, "L_ShopStatus"
        ApplyDV ws, "K", 4, "L_PM"
    End If

    ' --- Project Tasks dropdowns + project filter (data from row 2) ---
    Set ws = Nothing
    On Error Resume Next
    Set ws = wb.Sheets("Project Tasks")
    On Error GoTo 0
    If Not ws Is Nothing Then
        ApplyDV ws, "A", 2, "L_Project"
        ApplyDV ws, "B", 2, "L_Phase"
        ApplyDV ws, "C", 2, "L_Type"
        ApplyDV ws, "H", 2, "L_Assigned"
        ApplyDV ws, "I", 2, "L_ProjStatus"
        ApplyDV ws, "J", 2, "L_PM"
        ApplyDV ws, "K", 2, "L_Milestone"
        On Error Resume Next
        ws.AutoFilterMode = False
        ws.Range("A1").AutoFilter
        On Error GoTo 0
    End If

    lst.Visible = xlSheetHidden
    Application.DisplayAlerts = True
    Application.ScreenUpdating = True
    MsgBox "Done!" & vbCrLf & vbCrLf & _
        "- Dropdowns added on Input + Project Tasks" & vbCrLf & _
        "- 'Lists' sheet created (hidden)" & vbCrLf & _
        "- Project filter turned on (click the arrow on the Project header to show one project)" & vbCrLf & vbCrLf & _
        "Now File > Save (keep it as .xlsx). Done.", vbInformation, "MRA Setup"
End Sub

Private Sub WriteCol(lst As Worksheet, col As Long, arr As Variant)
    Dim i As Long
    For i = 0 To UBound(arr): lst.Cells(i + 2, col).Value = arr(i): Next i
End Sub

Private Sub NameCol(wb As Workbook, lst As Worksheet, col As Long, nm As String)
    Dim lastR As Long
    lastR = lst.Cells(lst.Rows.Count, col).End(xlUp).Row
    If lastR < 2 Then lastR = 2
    On Error Resume Next: wb.Names(nm).Delete: On Error GoTo 0
    wb.Names.Add Name:=nm, RefersTo:="='" & lst.Name & "'!" & lst.Range(lst.Cells(2, col), lst.Cells(lastR, col)).Address
End Sub

Private Sub ApplyDV(ws As Worksheet, colLetter As String, startRow As Long, nm As String)
    Dim rng As Range
    Set rng = ws.Range(colLetter & startRow & ":" & colLetter & 1000)
    On Error Resume Next: rng.Validation.Delete: On Error GoTo 0
    rng.Validation.Add Type:=xlValidateList, AlertStyle:=xlValidAlertStop, Operator:=xlBetween, Formula1:="=" & nm
    rng.Validation.IgnoreBlank = True
    rng.Validation.InCellDropdown = True
End Sub
