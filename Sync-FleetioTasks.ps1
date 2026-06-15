# =============================================================================
#  MRA - Fleetio -> Shop Tasks sync
#  Copies each bay job's OPEN Fleetio issues into the workbook's "Shop Tasks"
#  sheet as editable rows, so they can be assigned (Sal/Doug) and tracked on the
#  dashboard + History. Fleetio keeps its own history; this just mirrors the
#  open issues into the board as tasks.
#
#  Rules:
#   * Deduped by Fleetio issue # (stored as "#NNN - ..." at the start of Task).
#     A # already on the board is never added again.
#   * When a Fleetio issue is no longer open (resolved), its row's Status -> Done
#     (unless it's already Done from a manual close). Manual closes are never
#     re-opened.
#   * Matches issues to a bay job by Job# (so MOTT J1428 gets the trailer's AND
#     the tractor's open issues, labeled by unit in Comments).
#
#  Data source = data.js (written by Export-Data.ps1, next to this script) -> it
#  already holds the open Fleetio issues and the bay jobs. Workbook writes use
#  Excel COM (same approach as Import-Intake.ps1) so charts/formatting survive.
#
#  Cycle order:  Import-Intake.ps1  ->  Sync-FleetioTasks.ps1  ->  Export-Data.ps1
#
#  PREVIEW by default (writes nothing). Add -Apply to actually update the sheet.
#     powershell -ExecutionPolicy Bypass -File .\Sync-FleetioTasks.ps1           (preview)
#     powershell -ExecutionPolicy Bypass -File .\Sync-FleetioTasks.ps1 -Apply    (write)
# =============================================================================
param([switch]$Apply)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Master    = Join-Path (Split-Path -Parent $ScriptDir) 'MRA_Shop_Board_v6_9_7.xlsx'
$DataJs    = Join-Path $ScriptDir 'data.js'
$Sheet     = 'Shop Tasks'
$Log       = Join-Path $ScriptDir 'fleetio-sync-log.txt'
$IC        = [Globalization.CultureInfo]::InvariantCulture
function Log($m){ $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m"; Write-Output $line; $line | Out-File $Log -Append -Encoding utf8 }

if (-not (Test-Path $DataJs)) { Log "data.js not found at $DataJs (run Export-Data first)."; return }

# ---- load data.js -> object -------------------------------------------------
$raw  = Get-Content $DataJs -Raw
$a = $raw.IndexOf('{'); $b = $raw.LastIndexOf('}')
if ($a -lt 0 -or $b -le $a) { Log "data.js doesn't parse."; return }
$data = $raw.Substring($a, $b - $a + 1) | ConvertFrom-Json

$bayJobs = @($data.jobs | Where-Object { $_.category -eq 'bay' })
$issues  = @($data.fleetio.issues)
Log ("Loaded {0} bay job(s), {1} open Fleetio issue(s)." -f $bayJobs.Count, $issues.Count)

function Digits($s){ if ($s -and ("$s" -match '(\d{3,})')) { return $matches[1] } return '' }
function ShortAsset($s){ $s = "$s".Trim(); if ($s -match '^(.*?)(?:19|20)\d\d') { $s = $matches[1] }; return $s.Trim() }

# ---- Fleetio tasks already on the board (from data.js): num -> isDone --------
$existing = @{}
foreach ($j in $data.jobs) {
  foreach ($t in @($j.tasks)) {
    if ($t.t -match '^#(\d+)') { $existing["$($matches[1])"] = [bool]$t.done }
  }
}
# ---- currently-open Fleetio issue numbers -----------------------------------
$openNums = @{}
foreach ($it in $issues) { if ($it.num) { $openNums["$($it.num)"] = $true } }

# ---- ADDs: an open issue matched to a bay job that isn't on the board yet ----
$adds = New-Object System.Collections.ArrayList
$seen = @{}
foreach ($j in $bayJobs) {
  $jd = @(); if ($j.jobNum) { $jd = @([regex]::Matches("$($j.jobNum)", '\d{3,}') | ForEach-Object { $_.Value }) }
  foreach ($it in $issues) {
    $idn = Digits $it.jobNum
    if ($idn -eq '' -or ($jd -notcontains $idn)) { continue }
    $num = "$($it.num)"
    if ($seen.ContainsKey($num)) { continue }
    $seen[$num] = $true
    if ($existing.ContainsKey($num)) { continue }   # already on the board
    $opened = $null
    if ($it.openedISO) { try { $opened = [datetime]$it.openedISO } catch { $opened = $null } }
    $cmt = "Fleetio " + (ShortAsset $it.asset)
    if ($it.detail) { $cmt += " - " + (("$($it.detail)") -replace '\s+',' ').Trim() }
    if ($cmt.Length -gt 250) { $cmt = $cmt.Substring(0,250) }
    [void]$adds.Add([PSCustomObject]@{
      project=$j.project; job=$j.jobNum; bay=$j.bay
      task=("#$num - " + ("$($it.summary)").Trim()); opened=$opened; comments=$cmt
    })
  }
}
# ---- DONEs: board Fleetio rows whose issue is no longer open (not already done)
$doneNums = New-Object System.Collections.ArrayList
foreach ($num in $existing.Keys) {
  if (-not $openNums.ContainsKey($num) -and -not $existing[$num]) { [void]$doneNums.Add($num) }
}

Log ("Plan: add {0} new Fleetio task(s); mark {1} resolved -> Done." -f $adds.Count, $doneNums.Count)
foreach ($x in $adds)     { Log ("  ADD  [{0}] {1}  ->  {2}" -f $x.bay, $x.project, $x.task) }
foreach ($n in $doneNums) { Log ("  DONE #{0} (resolved in Fleetio)" -f $n) }

if (-not $Apply) { Log "PREVIEW only - nothing written. Re-run with -Apply to update '$Sheet'."; return }
if ($adds.Count -eq 0 -and $doneNums.Count -eq 0) { Log "Nothing to do."; return }

# ---- APPLY via Excel COM (strings only on .Value; dates as OADate serial) ----
$xl=$null; $wb=$null; $saved=$false
try {
  $xl = New-Object -ComObject Excel.Application
  $xl.Visible=$false; $xl.DisplayAlerts=$false; $xl.AskToUpdateLinks=$false; $xl.EnableEvents=$false
  try { $xl.AutomationSecurity = 1 } catch {}
  $wb = $xl.Workbooks.Open($Master)
  if ($wb.ReadOnly) { Log "Master is open/locked - skipping, will retry next cycle."; return }
  $ws=$null; foreach($s in $wb.Worksheets){ if($s.Name -eq $Sheet){ $ws=$s; break } }
  if (-not $ws) { Log "No '$Sheet' sheet - aborting (no changes)."; return }

  $last = [int]$ws.Cells.Item($ws.Rows.Count, 1).End(-4162).Row    # xlUp
  if ($last -lt 1) { $last = 1 }

  # mark resolved -> Done (scan Task col D for "#NNN")
  if ($doneNums.Count) {
    for ($r=2; $r -le $last; $r++) {
      $d = "$($ws.Cells.Item($r,4).Value)"
      if ($d -match '^#(\d+)' -and ($doneNums -contains $matches[1])) {
        $ws.Cells.Item($r,8).Value = 'Done'                       # H Status
        $g = "$($ws.Cells.Item($r,7).Value)"
        if ($g -eq '') { $ws.Cells.Item($r,7).Value = (Get-Date).ToOADate().ToString($IC); $ws.Cells.Item($r,7).NumberFormat='m/d/yyyy' }  # G Closed
      }
    }
  }
  # append new Fleetio rows  (A Project B Job# C Bay D Task E Assigned F Opened G Closed H Status I Milestone J Comments)
  $row = $last
  foreach ($x in $adds) {
    $row++
    $ws.Cells.Item($row,1).Value = "$($x.project)"
    $ws.Cells.Item($row,2).Value = "$($x.job)"
    $ws.Cells.Item($row,3).Value = "$($x.bay)"
    $ws.Cells.Item($row,4).Value = "$($x.task)"
    if ($x.opened -is [datetime]) { $ws.Cells.Item($row,6).Value = $x.opened.ToOADate().ToString($IC); $ws.Cells.Item($row,6).NumberFormat='m/d/yyyy' }
    $ws.Cells.Item($row,8).Value  = 'Open'
    $ws.Cells.Item($row,10).Value = "$($x.comments)"
  }
  $wb.Save(); $saved=$true; $wb.Close($true); $wb=$null
  Log ("Applied: added {0}, marked {1} done. Saved." -f $adds.Count, $doneNums.Count)
}
catch { Log "ERROR: $($_.Exception.Message)" }
finally {
  if ($wb){ try{ $wb.Close($false) }catch{} }
  if ($xl){ try{ $xl.Quit() }catch{} }
  foreach($o in @($wb,$xl)){ if($o){ try{ [void][Runtime.InteropServices.Marshal]::ReleaseComObject($o) }catch{} } }
  [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}
