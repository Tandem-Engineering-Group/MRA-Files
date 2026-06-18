# =============================================================================
#  MRA - Intake auto-import
#  Looks in the "Intake Inbox" folder for completed intake files, reads their
#  "Enter Here" rows straight from the file's XML (the same reliable method
#  Export-Data.ps1 uses), and appends them into the master workbook's
#  "Project Tasks" sheet via Excel (direct cell writes only - so the master's
#  charts / Gantt / tables are preserved). Called by Update-Auto.ps1 BEFORE
#  the export so new rows appear on the dashboard the same cycle.
#
#  Folders (siblings of the master workbook, one level up from this script):
#    Intake Inbox\            <- team members drop completed files here
#    Intake Inbox\Archive\    <- processed files moved here (timestamped)
#    Intake Inbox\Rejected\   <- files with no "Enter Here" sheet
#
#  Notes:
#   * Reading is done from the file XML (no Excel) so it can't be tripped up by
#     COM's .End/.UsedRange quirks. Excel is only launched to write, and only
#     when there are rows to add.
#   * Files are archived ONLY after the master saves successfully.
#   * If the master is open/locked, the run is skipped and files wait.
#   * The write step needs Excel + a logged-in session; if it fails it logs and
#     never blocks the export/push.
# =============================================================================

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Parent    = Split-Path -Parent $ScriptDir
$Master    = Join-Path $Parent 'MRA_Shop_Board_v6_9_7.xlsx'
$Inbox     = Join-Path $Parent 'Intake Inbox'
$Archive   = Join-Path $Inbox  'Archive'
$Rejected  = Join-Path $Inbox  'Rejected'
$Log       = Join-Path $ScriptDir 'import-log.txt'
$SrcSheet  = 'Enter Here'
$DstSheet  = 'Project Tasks'
$NCOLS     = 12                     # columns A:L (Project ... Comments) written 1:1
$SUBCOL    = 15                     # master 'Project Tasks' col O = Sub (subtask flag)
$LINELEN   = 13                     # row buffer: A:L (0..11) + Sub flag (12)

$nsMain = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
$nsRel  = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
$nsPkg  = 'http://schemas.openxmlformats.org/package/2006/relationships'

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Log($m) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Out-File $Log -Append -Encoding utf8
}

# ---- XML readers (same approach as Export-Data.ps1) ------------------------
function Read-Entry($zip, $name) {
    $entry = $zip.Entries | Where-Object { $_.FullName -eq $name }
    if (-not $entry) { return $null }
    $sr = New-Object System.IO.StreamReader($entry.Open(), [Text.Encoding]::UTF8)
    $txt = $sr.ReadToEnd(); $sr.Close()
    return $txt
}
function Resolve-Cell($c, $shared) {
    if ($null -eq $c) { return $null }
    $t = $c.t
    if     ($t -eq 's')         { return [string]$shared[[int]$c.v] }
    elseif ($t -eq 'inlineStr') { return [string]$c.InnerText }
    elseif ($t -eq 'str')       { return [string]$c.v }
    else                        { return [string]$c.v }
}
function Get-SheetXml($zip, $wbXml, $relsXml, $name) {
    $nm = New-Object System.Xml.XmlNamespaceManager($wbXml.NameTable)
    $nm.AddNamespace('d', $nsMain); $nm.AddNamespace('r', $nsRel)
    $sheetNode = $wbXml.SelectSingleNode("//d:sheets/d:sheet[@name='$name']", $nm)
    if (-not $sheetNode) { return $null }
    $rid = $sheetNode.GetAttribute('id', $nsRel)
    $nm2 = New-Object System.Xml.XmlNamespaceManager($relsXml.NameTable)
    $nm2.AddNamespace('p', $nsPkg)
    $relNode = $relsXml.SelectSingleNode("//p:Relationship[@Id='$rid']", $nm2)
    $target = $relNode.GetAttribute('Target') -replace '^/xl/', '' -replace '^/', ''
    if ($target -notmatch '^xl/') { $target = "xl/$target" }
    return [xml](Read-Entry $zip $target)
}
function Get-RowCells($row) {
    $cells = @{}
    foreach ($c in $row.c) {
        if ($null -eq $c.r) { continue }
        $cl = ([regex]::Match([string]$c.r, '^[A-Z]+')).Value
        $cells[$cl] = $c
    }
    return $cells
}
function Coerce-Date($raw) {
    if ($null -eq $raw -or "$raw".Trim() -eq '') { return $null }
    $d = 0.0
    if ([double]::TryParse("$raw", [ref]$d)) { try { return [datetime]::FromOADate($d) } catch { return "$raw" } }
    $dt = [datetime]::MinValue
    if ([datetime]::TryParse("$raw", [ref]$dt)) { return $dt }
    return "$raw"
}

# Grid helpers: resolved cell text by "A10" key (built once per file).
function GVal($grid, $col, $rw) {
    $v = $grid["$col$rw"]
    if ($null -eq $v) { return '' }
    return ([string]$v).Trim()
}
function GRaw($grid, $col, $rw) {
    $v = $grid["$col$rw"]
    if ($null -eq $v) { return $null }
    return $v
}
# First real value to the right of a label cell, stopping at the next label.
function Next-Val($grid, $rw, $startCol) {
    $cols = @('A','B','C','D','E','F','G','H','I','J','K','L')
    $idx = [array]::IndexOf($cols, $startCol)
    for ($i = $idx + 1; $i -lt $cols.Count; $i++) {
        $v = $grid["$($cols[$i])$rw"]
        if ($null -eq $v) { continue }
        $s = ([string]$v).Trim()
        if ($s -eq '') { continue }
        if ($s.EndsWith(':')) { break }   # ran into the next label
        return $s
    }
    return ''
}

# Open a workbook's XML via a temp copy (safe even if open in Excel).
function Open-Zip($path) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("mra_imp_" + [IO.Path]::GetFileName($path))
    try { [IO.File]::Copy($path, $tmp, $true) } catch { $tmp = $path }
    return @{ zip = [System.IO.Compression.ZipFile]::OpenRead($tmp); tmp = $tmp; isCopy = ($tmp -ne $path) }
}
function Close-Zip($z) {
    if ($z.zip) { $z.zip.Dispose() }
    if ($z.isCopy -and (Test-Path $z.tmp)) { Remove-Item $z.tmp -Force -ErrorAction SilentlyContinue }
}

# Read the 'Enter Here' sheet -> array of object[12] (Project..Comments);
# $null if the sheet is missing. Handles three layouts:
#   LEGACY  : header "Project" in A1, data A:L straight down from row 2.
#   MIRROR  : current template — letterhead + info block, then a task table whose
#             header is A="Project" .. L="Comments" (1:1 with the master sheet).
#   BRANDED : older template — info block + a task table A="Phase" .. J="Comments";
#             Project & PM are taken from the info block.
function Read-IntakeRows($path) {
    $z = Open-Zip $path
    try {
        $shared = New-Object System.Collections.ArrayList
        $ssXml = Read-Entry $z.zip 'xl/sharedStrings.xml'
        if ($ssXml) { [xml]$ss = $ssXml; foreach ($si in $ss.sst.si) { [void]$shared.Add([string]$si.InnerText) } }
        [xml]$wbXml   = Read-Entry $z.zip 'xl/workbook.xml'
        [xml]$relsXml = Read-Entry $z.zip 'xl/_rels/workbook.xml.rels'
        $sx = Get-SheetXml $z.zip $wbXml $relsXml $SrcSheet
        if (-not $sx) { return $null }

        # Build a resolved cell grid: $grid["A10"] = text/serial.
        $grid = @{}; $maxRow = 1
        foreach ($row in $sx.worksheet.sheetData.row) {
            $rn = [int]$row.r
            if ($rn -gt $maxRow) { $maxRow = $rn }
            foreach ($c in $row.c) {
                if ($null -eq $c.r) { continue }
                $cl = ([regex]::Match([string]$c.r, '^[A-Z]+')).Value
                $grid["$cl$rn"] = (Resolve-Cell $c $shared)
            }
        }

        $rows = New-Object System.Collections.ArrayList

        # ----- LEGACY layout ------------------------------------------------
        if ((GVal $grid 'A' 1) -eq 'Project') {
            for ($r = 2; $r -le $maxRow; $r++) {
                $A = GVal $grid 'A' $r
                $D = GVal $grid 'D' $r
                if ($A -eq '' -and $D -eq '') { continue }
                $line = New-Object 'object[]' $LINELEN
                $line[0]=$A
                $line[1]=GVal $grid 'B' $r
                $line[2]=GVal $grid 'C' $r
                $line[3]=$D
                $line[4]=Coerce-Date (GRaw $grid 'E' $r)
                $line[5]=Coerce-Date (GRaw $grid 'F' $r)
                $line[6]=GRaw $grid 'G' $r
                $line[7]=GVal $grid 'H' $r
                $line[8]=GVal $grid 'I' $r
                $line[9]=GVal $grid 'J' $r
                $line[10]=GVal $grid 'K' $r
                $line[11]=GRaw $grid 'L' $r
                $line[12]=''                    # LEGACY layout has no Sub column
                [void]$rows.Add($line)
            }
            return $rows
        }

        # ----- read the one-time info block (Project / Job # / PM) ----------
        # Used as a fallback by both the MIRROR and the older BRANDED layouts.
        # NOTE: match 'project / client' (the real label) NOT a bare 'project',
        # so the MIRROR task header cell A="Project" can't be mistaken for it.
        $proj = ''; $pm = ''; $job = ''
        for ($r = 1; $r -le $maxRow; $r++) {
            foreach ($col in @('A','B','C','D','E','F','G','H','I','J')) {
                $t = GVal $grid $col $r
                if ($t -eq '') { continue }
                $key = ($t -replace '[:\s]+$','').ToLower()
                if     ($key -in @('project / client','project/client','project / client name')) { $proj = Next-Val $grid $r $col }
                elseif ($key -eq 'project manager') { $pm = Next-Val $grid $r $col }
                elseif ($key -in @('mra job #','mra job#','job #','job#')) { $job = Next-Val $grid $r $col }
            }
        }

        # ----- find the task header row & decide the layout -----------------
        #   MIRROR  (current template): A="Project" .. L="Comments", 1:1 with the
        #           master 'Project Tasks' sheet (a paste lands straight across).
        #   BRANDED (older template):   A="Phase" .. J="Comments"; Project & PM
        #           come from the info block above.
        $hdr = -1; $layout = ''
        for ($r = 1; $r -le $maxRow; $r++) {
            $hA = GVal $grid 'A' $r
            if ($hA -eq 'Project' -and (GVal $grid 'D' $r) -eq 'Task') { $hdr = $r; $layout = 'mirror'; break }
            if ($hA -eq 'Phase'   -and (GVal $grid 'C' $r) -eq 'Task') { $hdr = $r; $layout = 'branded'; break }
        }
        if ($hdr -lt 1) {
            Log "SKIP '$([IO.Path]::GetFileName($path))' - 'Enter Here' present but no task header (Project/Task or Phase/Task) found."
            return $null
        }

        $projOut = $proj
        if ($job -ne '' -and $job.ToUpper() -ne 'NEW' -and $projOut -notmatch [regex]::Escape($job)) {
            $projOut = if ($projOut -ne '') { "$projOut ($job)" } else { $job }
        }

        # ----- MIRROR layout: columns are 1:1 with the master ----------------
        # Project (A) and PM (J) auto-fill from the info block via formula; if a
        # cell is blank (formula not yet cached by Excel), fall back to the
        # info-block value so the import is always populated.
        if ($layout -eq 'mirror') {
            for ($r = $hdr + 1; $r -le $maxRow; $r++) {
                $task = GVal $grid 'D' $r
                if ($task -eq '') { continue }
                $aProj = GVal $grid 'A' $r
                $jPm   = GVal $grid 'J' $r
                # If Excel hasn't cached the autofill (cell still holds the raw
                # =IF(...) formula text), treat it as blank and use the info block.
                if ($aProj -like '=*') { $aProj = '' }
                if ($jPm   -like '=*') { $jPm   = '' }
                $sub = GVal $grid 'O' $r                                          # Sub flag
                if ($sub -like '=*') { $sub = '' }
                $line = New-Object 'object[]' $LINELEN
                $line[0]  = $(if ($aProj -ne '') { $aProj } else { $projOut })   # Project
                $line[1]  = GVal $grid 'B' $r                                     # Phase
                $line[2]  = GVal $grid 'C' $r                                     # Type
                $line[3]  = $task                                                # Task
                $line[4]  = Coerce-Date (GRaw $grid 'E' $r)                       # Start
                $line[5]  = Coerce-Date (GRaw $grid 'F' $r)                       # Finish
                $line[6]  = GRaw $grid 'G' $r                                     # Duration
                $line[7]  = GVal $grid 'H' $r                                     # Assigned To
                $line[8]  = GVal $grid 'I' $r                                     # Status
                $line[9]  = $(if ($jPm -ne '') { $jPm } else { $pm })            # PM
                $line[10] = GVal $grid 'K' $r                                    # Milestone
                $line[11] = GRaw $grid 'L' $r                                    # Comments
                $line[12] = $(if ($sub -match '^[xX]') { 'x' } else { '' })      # Sub (col O)
                [void]$rows.Add($line)
            }
            return $rows
        }

        # ----- BRANDED layout (older template) -------------------------------
        for ($r = $hdr + 1; $r -le $maxRow; $r++) {
            $task = GVal $grid 'C' $r
            if ($task -eq '') { continue }            # skip skeleton phase rows w/ no task
            $line = New-Object 'object[]' $LINELEN
            $line[0]  = $projOut                       # Project (info block)
            $line[1]  = GVal $grid 'A' $r              # Phase
            $line[2]  = GVal $grid 'B' $r              # Type
            $line[3]  = $task                          # Task
            $line[4]  = Coerce-Date (GRaw $grid 'D' $r) # Start
            $line[5]  = Coerce-Date (GRaw $grid 'E' $r) # Finish
            $line[6]  = GRaw $grid 'F' $r              # Duration
            $line[7]  = GVal $grid 'G' $r              # Assigned To
            $line[8]  = GVal $grid 'H' $r              # Status
            $line[9]  = $pm                            # PM (info block)
            $line[10] = GVal $grid 'I' $r             # Milestone
            $line[11] = GRaw $grid 'J' $r             # Comments
            $line[12] = ''                            # BRANDED layout has no Sub column
            [void]$rows.Add($line)
        }
        return $rows
    } finally { Close-Zip $z }
}

# Last 'Project Tasks' row that has a value in column A (so we append after it).
function Get-MasterLastRow($path) {
    $z = Open-Zip $path
    try {
        $shared = New-Object System.Collections.ArrayList
        $ssXml = Read-Entry $z.zip 'xl/sharedStrings.xml'
        if ($ssXml) { [xml]$ss = $ssXml; foreach ($si in $ss.sst.si) { [void]$shared.Add([string]$si.InnerText) } }
        [xml]$wbXml   = Read-Entry $z.zip 'xl/workbook.xml'
        [xml]$relsXml = Read-Entry $z.zip 'xl/_rels/workbook.xml.rels'
        $sx = Get-SheetXml $z.zip $wbXml $relsXml $DstSheet
        if (-not $sx) { return -1 }
        $max = 1
        foreach ($row in $sx.worksheet.sheetData.row) {
            $rn = [int]$row.r
            if ($rn -le $max) { continue }
            $pc = Get-RowCells $row
            $a = ([string](Resolve-Cell $pc['A'] $shared)).Trim()
            if ($a -ne '') { $max = $rn }
        }
        return $max
    } finally { Close-Zip $z }
}

# ---- main ------------------------------------------------------------------
foreach ($d in @($Inbox, $Archive, $Rejected)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

$files = @(Get-ChildItem -Path $Inbox -File -Filter *.xlsx -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -notlike '~$*' })
if ($files.Count -eq 0) { return }

Log "Found $($files.Count) intake file(s) to import."

# 1) Read every file (XML). Collect rows; reject non-intake files.
$batch = New-Object System.Collections.ArrayList   # items: @{ file; rows }
foreach ($f in $files) {
    try {
        $rows = Read-IntakeRows $f.FullName
        if ($null -eq $rows) {
            Log "SKIP '$($f.Name)' - no '$SrcSheet' sheet (not an intake file)."
            Move-Item $f.FullName (Join-Path $Rejected $f.Name) -Force
            continue
        }
        Log "Read $($rows.Count) data row(s) from '$($f.Name)'."
        [void]$batch.Add(@{ file = $f; rows = $rows })
    } catch {
        Log "READ ERROR on '$($f.Name)': $($_.Exception.Message)  (left in inbox for retry)"
    }
}

$totalRows = 0
foreach ($b in $batch) { $totalRows += $b.rows.Count }
if ($totalRows -eq 0) {
    # nothing to write, but archive any empty intake files so they don't re-process
    foreach ($b in $batch) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Move-Item $b.file.FullName (Join-Path $Archive ("{0}__{1}" -f $stamp, $b.file.Name)) -Force
        Log "Archived '$($b.file.Name)' (0 data rows)."
    }
    Log "Done. 0 row(s) imported."
    return
}

# 2) Write to the master via Excel (direct cell writes only).
$startAfter = Get-MasterLastRow $Master
if ($startAfter -lt 1) { Log "Master has no '$DstSheet' sheet - aborting (no changes)."; return }

$xl = $null; $mwb = $null; $saved = $false; $phase = 'launch Excel'
try {
    $xl = New-Object -ComObject Excel.Application
    $xl.Visible = $false; $xl.DisplayAlerts = $false
    $xl.AskToUpdateLinks = $false; $xl.EnableEvents = $false; $xl.ScreenUpdating = $false
    try { $xl.AutomationSecurity = 1 } catch {}

    $phase = 'open master'
    $mwb = $xl.Workbooks.Open($Master)
    if ($mwb.ReadOnly) {
        Log "Master is open/locked (read-only) - skipping, will retry next cycle."
        return
    }
    $phase = 'find Project Tasks'
    $dst = $null
    foreach ($s in $mwb.Worksheets) { if ($s.Name -eq $DstSheet) { $dst = $s; break } }
    if ($null -eq $dst) { Log "Master has no '$DstSheet' sheet - aborting."; return }
    try { if ($dst.ProtectContents) { $dst.Unprotect() } }
    catch { Log "NOTE: '$DstSheet' is protected and couldn't be unprotected - writes may fail." }

    $row = $startAfter
    foreach ($b in $batch) {
        foreach ($line in $b.rows) {
            $row++
            for ($c = 1; $c -le $NCOLS; $c++) {
                $val = $line[$c - 1]
                if ($null -eq $val -or "$val" -eq '') { continue }
                $phase = "write row $row col $c"
                $cell = $dst.Cells.Item($row, $c)
                # This Excel's COM binder only accepts strings on .Value, so write
                # everything as text and let Excel coerce it (same as typing).
                if ($val -is [datetime]) {
                    # Write the date serial as a string -> Excel makes it a number,
                    # then a date format displays it as a date. (Dashboard reads the serial.)
                    $cell.Value = $val.ToOADate().ToString([Globalization.CultureInfo]::InvariantCulture)
                    $cell.NumberFormat = 'm/d/yyyy'
                } else {
                    $cell.Value = "$val"
                }
            }
            # Sub flag -> master col O (only when set; keeps non-subtask rows clean).
            $sub = $line[12]
            if ($null -ne $sub -and "$sub" -ne '') {
                $phase = "write row $row Sub (col $SUBCOL)"
                $dst.Cells.Item($row, $SUBCOL).Value = 'x'
            }
        }
    }

    $phase = 'save master'
    $mwb.Save(); $saved = $true
    $mwb.Close($true); $mwb = $null
    Log "Imported $totalRows row(s) into '$DstSheet' (rows $($startAfter+1)..$row). Master saved."
}
catch {
    Log "WRITE ERROR [phase: $phase, line $($_.InvocationInfo.ScriptLineNumber)]: $($_.Exception.Message)"
}
finally {
    if ($null -ne $mwb) { try { $mwb.Close($false) } catch {} }
    if ($null -ne $xl)  { try { $xl.Quit() } catch {} }
    foreach ($o in @($mwb, $xl)) {
        if ($null -ne $o) { try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($o) } catch {} }
    }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}

# 3) Archive the files we actually imported (only after a successful save).
if ($saved) {
    foreach ($b in $batch) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        try { Move-Item $b.file.FullName (Join-Path $Archive ("{0}__{1}" -f $stamp, $b.file.Name)) -Force }
        catch { Log "NOTE: imported but couldn't archive '$($b.file.Name)': $($_.Exception.Message)" }
    }
    Log "Done. $totalRows row(s) imported total."
} else {
    Log "Not saved - files left in inbox for retry."
}
