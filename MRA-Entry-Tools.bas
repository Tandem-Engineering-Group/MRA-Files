Option Explicit
' =====================================================================
'  MRA - Project Intake Tools  (put this in its own workbook)
'
'  Buttons it creates:
'   * Create Intake File  -> makes a clean, offline Excel for a team
'     member: Project Tasks columns + dropdowns + a Phase 1-5 skeleton.
'   * Import Completed File -> appends their filled rows into the MASTER
'     workbook's "Project Tasks" sheet (values only; master stays .xlsx).
'
'  ONE-TIME SETUP:
'   1) Open Excel, create a NEW blank workbook.
'   2) Press Alt+F11 (or right-click a sheet tab > View Code).
'   3) In the VBA editor: File > Import File... > pick MRA-Entry-Tools.bas
'      (or Insert > Module and paste this whole file in).
'   4) Press F5 and run  SetupTools  -> a "Home" sheet with 2 buttons appears.
'   5) Save the workbook as  MRA Entry Tools.xlsm  (Excel Macro-Enabled Workbook)
'      somewhere handy. Done - use the buttons from now on.
' =====================================================================

Sub SetupTools()
    Dim wb As Workbook: Set wb = ThisWorkbook
    Dim ws As Worksheet
    On Error Resume Next: Set ws = wb.Sheets("Home"): On Error GoTo 0
    If ws Is Nothing Then Set ws = wb.Sheets.Add(Before:=wb.Sheets(1)): ws.Name = "Home"
    Dim shp As Shape
    For Each shp In ws.Shapes: shp.Delete: Next shp
    ws.Cells.Clear
    With ws.Range("B2"): .Value = "MRA - Project Intake Tools": .Font.Size = 16: .Font.Bold = True: End With
    ws.Range("B4").Value = "1) Create Intake File  - makes a file to send a team member (they fill it offline)."
    ws.Range("B5").Value = "2) Import Completed File - pulls their finished file into the master workbook."
    AddBtn ws, "Create Intake File", "CreateIntakeFile", 24, 120
    AddBtn ws, "Import Completed File", "ImportCompletedFile", 210, 120
    ws.Activate
    MsgBox "Tools ready - see the two buttons on the Home sheet." & vbCrLf & vbCrLf & _
           "Now save this workbook as 'MRA Entry Tools.xlsm'.", vbInformation
End Sub

Private Sub AddBtn(ws As Worksheet, cap As String, macro As String, x As Single, y As Single)
    Dim b As Shape
    Set b = ws.Shapes.AddShape(msoShapeRoundedRectangle, x, y, 175, 44)
    b.Fill.ForeColor.RGB = RGB(226, 78, 38)
    b.Line.Visible = msoFalse
    With b.TextFrame2.TextRange
        .Text = cap: .Font.Size = 12: .Font.Bold = msoTrue
        .Font.Fill.ForeColor.RGB = RGB(255, 255, 255)
    End With
    b.OnAction = macro
End Sub

Private Sub WriteCol(ws As Worksheet, col As Long, arr As Variant)
    Dim i As Long
    For i = 0 To UBound(arr): ws.Cells(i + 2, col).Value = arr(i): Next i
End Sub

Private Sub BuildLists(lst As Worksheet)
    lst.Range("C1").Value = "Phase": lst.Range("D1").Value = "Type": lst.Range("E1").Value = "ProjStatus"
    lst.Range("F1").Value = "Milestone": lst.Range("G1").Value = "PM": lst.Range("H1").Value = "Assigned": lst.Range("I1").Value = "Project"
    WriteCol lst, 3, Array("Phase 1 - Planning", "Phase 2 - Design & Detail", "Phase 3 - Fabrication", "Phase 4 - Electrical & Technology Integration", "Phase 5 - Graphics, Soft Launch / QS / Handover")
    WriteCol lst, 4, Array("Meeting", "Hard Date", "Design Task", "Materials", "Production Task", "Client")
    WriteCol lst, 5, Array("Not Started", "Upcoming", "In Progress", "Completed", "TBD", "N/A")
    WriteCol lst, 6, Array("Yes", "No")
    WriteCol lst, 7, Array("Megan Fraser", "Al Karloff", "Stephanie Hardie", "Alex Karam", "Luciana Giglio", "Frank Mancina", "Mark St Jean", "Sherri Washington", "Sherrill Buchan", "Cindy Irland", "Mitch Schirr", "Heather Maloney", "TBD")
    WriteCol lst, 8, Array("Megan Fraser", "Al Karloff", "Steve K", "Rich Miller", "Ted O'Malley", "Gino Bitonti", "Sean Payton", "Chris Beyer", "Sarah Williams", "Lindsay Smith", "Kevin R. Sweeney", "Chris Nusbaum", "Luciana Giglio", "MRA Design", "MRA Engineering", "MRA Electrical", "MRA Shop", "MRA Tech", "MRA QA", "MRA Ops", "MRA Procurement", "Art Guild", "Art Guild AV", "W2 Graphics", "Master Wraps", "Logistics", "Fleet", "Vendor", "Client", "All")
    WriteCol lst, 9, Array("Medtronic", "Oakland Schools", "Trumpf", "Cisco", "Washtenaw", "Siemens DI Pedestal", "SWC HI [CMI]", "SMC [Hamilton]", "Thunder Bay MRI Bus", "Siemens 53ft Replacement #1", "Siemens 53ft Replacement #2", "Stryker")
End Sub

Private Sub DV(ws As Worksheet, colLetter As String, src As String)
    Dim rng As Range: Set rng = ws.Range(colLetter & "2:" & colLetter & "300")
    On Error Resume Next: rng.Validation.Delete: On Error GoTo 0
    rng.Validation.Add Type:=xlValidateList, AlertStyle:=xlValidAlertStop, Formula1:=src
    rng.Validation.IgnoreBlank = True: rng.Validation.InCellDropdown = True
End Sub

Private Function CleanName(s As String) As String
    Dim i As Long, ch As String, o As String
    For i = 1 To Len(s)
        ch = Mid(s, i, 1)
        If ch Like "[A-Za-z0-9 _-]" Then o = o & ch
    Next i
    CleanName = Trim(o)
End Function

Sub CreateIntakeFile()
    Dim projName As String
    projName = Trim(InputBox("Project name for this intake file:", "Create Intake File"))
    If projName = "" Then Exit Sub

    Application.ScreenUpdating = False
    Dim nb As Workbook: Set nb = Workbooks.Add
    Application.DisplayAlerts = False
    Do While nb.Sheets.Count > 1: nb.Sheets(nb.Sheets.Count).Delete: Loop
    Application.DisplayAlerts = True

    Dim ws As Worksheet: Set ws = nb.Sheets(1): ws.Name = "Enter Here"
    Dim lst As Worksheet: Set lst = nb.Sheets.Add(After:=ws): lst.Name = "Lists"
    BuildLists lst
    lst.Visible = xlSheetVeryHidden

    Dim heads As Variant
    heads = Array("Project", "Phase", "Type", "Task", "Start", "Finish", "Duration", "Assigned To", "Status", "PM", "Milestone", "Comments")
    Dim c As Long
    For c = 0 To UBound(heads): ws.Cells(1, c + 1).Value = heads(c): Next c
    With ws.Range("A1:L1"): .Font.Bold = True: .Interior.Color = RGB(226, 78, 38): .Font.Color = RGB(255, 255, 255): End With

    Dim phases As Variant
    phases = Array("Phase 1 - Planning", "Phase 2 - Design & Detail", "Phase 3 - Fabrication", "Phase 4 - Electrical & Technology Integration", "Phase 5 - Graphics, Soft Launch / QS / Handover")
    Dim r As Long, i As Long: r = 2
    For i = 0 To UBound(phases)
        ws.Cells(r, 1).Value = projName
        ws.Cells(r, 2).Value = phases(i)
        ws.Cells(r, 9).Value = "Not Started"
        ws.Cells(r, 11).Value = "No"
        r = r + 1
    Next i

    DV ws, "A", "=Lists!$I$2:$I$13"
    DV ws, "B", "=Lists!$C$2:$C$6"
    DV ws, "C", "=Lists!$D$2:$D$7"
    DV ws, "H", "=Lists!$H$2:$H$31"
    DV ws, "I", "=Lists!$E$2:$E$7"
    DV ws, "J", "=Lists!$G$2:$G$14"
    DV ws, "K", "=Lists!$F$2:$F$3"

    ws.Range("A1").AutoFilter
    ws.Columns("A:L").ColumnWidth = 16
    ws.Columns("D").ColumnWidth = 40
    ws.Rows(1).RowHeight = 22
    ws.Range("N2").Value = "Tip: fill in Task, dates and Assigned for each phase. Delete any rows you don't need, then save and send back."
    ws.Range("N2").Font.Italic = True
    ws.Range("D2").Select

    Dim fn As Variant
    fn = Application.GetSaveAsFilename(InitialFileName:="MRA Intake - " & CleanName(projName), FileFilter:="Excel Workbook (*.xlsx), *.xlsx")
    Application.ScreenUpdating = True
    If fn = False Then Exit Sub
    nb.SaveAs Filename:=fn, FileFormat:=xlOpenXMLWorkbook
    MsgBox "Intake file saved:" & vbCrLf & fn & vbCrLf & vbCrLf & _
           "Send it to your team member. When they return it, click 'Import Completed File'.", vbInformation
End Sub

Sub ImportCompletedFile()
    Dim fn As Variant, mf As Variant
    fn = Application.GetOpenFilename("Excel files (*.xlsx;*.xlsm),*.xlsx;*.xlsm", , "Pick the COMPLETED intake file")
    If fn = False Then Exit Sub
    mf = Application.GetOpenFilename("Excel files (*.xlsx;*.xlsm),*.xlsx;*.xlsm", , "Pick the MASTER workbook (MRA_Shop_Board...)")
    If mf = False Then Exit Sub

    Application.ScreenUpdating = False
    On Error GoTo Fail
    Dim src As Workbook, mst As Workbook, sws As Worksheet, mws As Worksheet
    Set src = Workbooks.Open(fn, ReadOnly:=True)
    On Error Resume Next: Set sws = src.Sheets("Enter Here"): On Error GoTo 0
    If sws Is Nothing Then
        src.Close False: Application.ScreenUpdating = True
        MsgBox "That file has no 'Enter Here' sheet - is it an intake file?", vbExclamation: Exit Sub
    End If
    Set mst = Workbooks.Open(mf)
    On Error Resume Next: Set mws = mst.Sheets("Project Tasks"): On Error GoTo 0
    If mws Is Nothing Then
        src.Close False: Application.ScreenUpdating = True
        MsgBox "That master has no 'Project Tasks' sheet - did you pick the right file?", vbExclamation: Exit Sub
    End If

    Dim lastSrc As Long, lastMst As Long, i As Long, cnt As Long
    lastSrc = sws.Cells(sws.Rows.Count, 1).End(xlUp).Row
    lastMst = mws.Cells(mws.Rows.Count, 1).End(xlUp).Row
    For i = 2 To lastSrc
        If Trim(CStr(sws.Cells(i, 1).Value) & CStr(sws.Cells(i, 4).Value)) <> "" Then
            lastMst = lastMst + 1
            sws.Range(sws.Cells(i, 1), sws.Cells(i, 12)).Copy
            mws.Cells(lastMst, 1).PasteSpecial Paste:=xlPasteValues
            cnt = cnt + 1
        End If
    Next i
    Application.CutCopyMode = False
    src.Close SaveChanges:=False
    mst.Save
    Application.ScreenUpdating = True
    MsgBox cnt & " row(s) imported into 'Project Tasks' and the master was saved." & vbCrLf & _
           "The dashboard will pick it up on its next update.", vbInformation
    Exit Sub
Fail:
    Application.ScreenUpdating = True
    MsgBox "Import error: " & Err.Description, vbCritical
End Sub
