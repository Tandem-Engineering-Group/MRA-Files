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
$NCOLS     = 12                     # columns A:L (Project ... Comments)

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

# Read 'Enter Here' rows (A:L) -> array of object[12]; $null returned if no sheet.
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
        $rows = New-Object System.Collections.ArrayList
        foreach ($row in $sx.worksheet.sheetData.row) {
            if ([int]$row.r -lt 2) { continue }
            $pc = Get-RowCells $row
            $A = ([string](Resolve-Cell $pc['A'] $shared)).Trim()
            $D = ([string](Resolve-Cell $pc['D'] $shared)).Trim()
            if ($A -eq '' -and $D -eq '') { continue }
            $line = New-Object 'object[]' $NCOLS
            $line[0]  = $A
            $line[1]  = ([string](Resolve-Cell $pc['B'] $shared)).Trim()
            $line[2]  = ([string](Resolve-Cell $pc['C'] $shared)).Trim()
            $line[3]  = $D
            $line[4]  = Coerce-Date (Resolve-Cell $pc['E'] $shared)
            $line[5]  = Coerce-Date (Resolve-Cell $pc['F'] $shared)
            $line[6]  = Resolve-Cell $pc['G'] $shared
            $line[7]  = ([string](Resolve-Cell $pc['H'] $shared)).Trim()
            $line[8]  = ([string](Resolve-Cell $pc['I'] $shared)).Trim()
            $line[9]  = ([string](Resolve-Cell $pc['J'] $shared)).Trim()
            $line[10] = ([string](Resolve-Cell $pc['K'] $shared)).Trim()
            $line[11] = Resolve-Cell $pc['L'] $shared
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
                if ($null -ne $val -and "$val" -ne '') {
                    $phase = "write row $row col $c"
                    $dst.Cells.Item($row, $c).Value = $val
                }
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
