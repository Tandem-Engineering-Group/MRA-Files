# =============================================================================
#  MRA - Intake auto-import
#  Looks in the "Intake Inbox" folder for completed intake files and appends
#  their rows into the master workbook's "Project Tasks" sheet, then archives
#  the files. Uses Excel itself (COM) so the master's charts / tables / Gantt
#  are preserved exactly. Called by Update-Auto.ps1 BEFORE the data export so
#  newly imported rows appear on the dashboard the same cycle.
#
#  Folders (siblings of the master workbook, one level up from this script):
#    Intake Inbox\            <- team members drop completed files here
#    Intake Inbox\Archive\    <- processed files moved here (timestamped)
#    Intake Inbox\Rejected\   <- files with no "Enter Here" sheet
#
#  Notes:
#   * Most cycles there's nothing to do, so Excel is NOT launched (lightweight).
#   * If the master is open/locked, the run is skipped and files wait for next.
#   * This step needs Excel installed and a logged-in desktop session. If that
#     ever fails, it logs and exits without blocking the export/push.
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
$xlUp      = -4162

function Log($m) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Out-File $Log -Append -Encoding utf8
}

# Ensure the folders exist (first run creates them).
foreach ($d in @($Inbox, $Archive, $Rejected)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# Anything queued? (ignore Excel's ~$ temp lock files.)
$files = @(Get-ChildItem -Path $Inbox -File -Filter *.xlsx -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -notlike '~$*' })
if ($files.Count -eq 0) { return }   # nothing to do - stay lightweight, no Excel

Log "Found $($files.Count) intake file(s) to import."

$xl = $null; $mwb = $null; $closedMaster = $false
try {
    $xl = New-Object -ComObject Excel.Application
    $xl.Visible         = $false
    $xl.DisplayAlerts   = $false
    $xl.AskToUpdateLinks = $false
    $xl.EnableEvents    = $false
    $xl.ScreenUpdating  = $false

    $mwb = $xl.Workbooks.Open($Master)
    if ($mwb.ReadOnly) {
        Log "Master is open/locked (opened read-only) - skipping, will retry next cycle."
        $mwb.Close($false); $mwb = $null; $closedMaster = $true
        return
    }

    $dst = $null
    foreach ($s in $mwb.Worksheets) { if ($s.Name -eq $DstSheet) { $dst = $s; break } }
    if ($null -eq $dst) {
        Log "Master has no '$DstSheet' sheet - aborting (no changes saved)."
        $mwb.Close($false); $mwb = $null; $closedMaster = $true
        return
    }

    # Is Project Tasks an Excel Table? If so, append through it (keeps formatting/dropdowns).
    $tbl = $null
    if ($dst.ListObjects.Count -ge 1) { $tbl = $dst.ListObjects.Item(1) }

    $total = 0
    foreach ($f in $files) {
        $swb = $null
        try {
            $swb = $xl.Workbooks.Open($f.FullName, 0, $true)   # UpdateLinks=0, ReadOnly=true
            $src = $null
            foreach ($s in $swb.Worksheets) { if ($s.Name -eq $SrcSheet) { $src = $s; break } }
            if ($null -eq $src) {
                Log "SKIP '$($f.Name)' - no '$SrcSheet' sheet (not an intake file)."
                $swb.Close($false); $swb = $null
                Move-Item $f.FullName (Join-Path $Rejected $f.Name) -Force
                continue
            }

            $used    = $src.UsedRange
            $lastRow = $used.Row + $used.Rows.Count - 1
            $added   = 0
            for ($r = 2; $r -le $lastRow; $r++) {
                $proj = ([string]$src.Cells.Item($r, 1).Value2).Trim()
                $task = ([string]$src.Cells.Item($r, 4).Value2).Trim()
                if ($proj -eq '' -and $task -eq '') { continue }   # blank row

                if ($null -ne $tbl) {
                    $rng = $tbl.ListRows.Add().Range
                    for ($c = 1; $c -le $NCOLS; $c++) {
                        $rng.Cells.Item(1, $c).Value = $src.Cells.Item($r, $c).Value
                    }
                } else {
                    $dr = $dst.Cells.Item($dst.Rows.Count, 1).End($xlUp).Row + 1
                    for ($c = 1; $c -le $NCOLS; $c++) {
                        $dst.Cells.Item($dr, $c).Value = $src.Cells.Item($r, $c).Value
                    }
                }
                $added++
            }
            $swb.Close($false); $swb = $null
            $total += $added

            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            Move-Item $f.FullName (Join-Path $Archive ("{0}__{1}" -f $stamp, $f.Name)) -Force
            Log "Imported $added row(s) from '$($f.Name)' -> archived."
        }
        catch {
            Log "ERROR on '$($f.Name)': $($_.Exception.Message)  (left in inbox for retry)"
            if ($null -ne $swb) { try { $swb.Close($false) } catch {} ; $swb = $null }
        }
    }

    if ($total -gt 0) { $mwb.Save() }
    $mwb.Close($true); $mwb = $null; $closedMaster = $true
    Log "Done. $total row(s) imported total."
}
catch {
    Log "FATAL: $($_.Exception.Message)"
}
finally {
    if ($null -ne $mwb -and -not $closedMaster) { try { $mwb.Close($false) } catch {} }
    if ($null -ne $xl) { try { $xl.Quit() } catch {} }
    foreach ($o in @($mwb, $xl)) {
        if ($null -ne $o) { try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($o) } catch {} }
    }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}
