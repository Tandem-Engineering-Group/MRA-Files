<#
  Compare-DataJs.ps1   (STEP 3 - validation helper)

  Diffs the Excel-built data.js against the Lists-built candidate so we can prove
  the SharePoint read path produces the same board before flipping export.yml.

  It compares only the sections that come from the workbook/Lists -
  jobs / projects / users / holidays - and IGNORES fleet (Fleetio/Samsara),
  mraStatus (logistics) and generatedAt, which are time-varying / passed through.

  RUN:
    ./Compare-DataJs.ps1 data.js data.fromlists.js
#>
param(
  [Parameter(Mandatory = $true)] [string] $A,   # baseline (Excel-built) data.js
  [Parameter(Mandatory = $true)] [string] $B    # candidate (Lists-built) data.js
)
$ErrorActionPreference = 'Stop'

function Load-DataJs([string]$path) {
  if (-not (Test-Path $path)) { throw "Not found: $path" }
  $raw = Get-Content -Raw $path
  $txt = $raw.Substring($raw.IndexOf('{'))
  $txt = $txt.Substring(0, $txt.LastIndexOf('}') + 1)
  return $txt | ConvertFrom-Json
}

$da = Load-DataJs $A
$db = Load-DataJs $B
$issues = 0
function Note($msg) { $script:issues++; Write-Host ("  DIFF  " + $msg) -ForegroundColor Yellow }

Write-Host "Comparing:" -ForegroundColor Cyan
Write-Host ("  A (baseline):  {0}" -f $A)
Write-Host ("  B (candidate): {0}" -f $B)
Write-Host ""

# ---- counts ----
Write-Host "Counts (A vs B):"
foreach ($sec in 'jobs','projects','teamTasks','users','holidays') {
  $ca = @($da.$sec).Count; $cb = @($db.$sec).Count
  $flag = if ($ca -ne $cb) { '  <-- differ' } else { '' }
  Write-Host ("  {0,-10} {1,5}  vs {2,5}{3}" -f $sec, $ca, $cb, $flag)
  if ($ca -ne $cb) { $script:issues++ }
}
Write-Host ""

# ---- jobs (key = project) ----
function Job-Map($d) {
  $m = @{}
  foreach ($j in @($d.jobs)) {
    $m["$($j.project)"] = [PSCustomObject]@{
      bay = "$($j.bay)"; status = "$($j.status)"; jobNum = "$($j.jobNum)"; pm = "$($j.pm)"
      startISO = "$($j.startISO)"; shipISO = "$($j.completionISO)"
      open = [int]$j.openCount; done = [int]$j.doneCount
    }
  }
  return $m
}
$ja = Job-Map $da; $jb = Job-Map $db
Write-Host "Jobs:"
foreach ($k in ($ja.Keys | Sort-Object)) {
  if (-not $jb.ContainsKey($k)) { Note "job only in A: '$k'"; continue }
  $x = $ja[$k]; $y = $jb[$k]
  foreach ($p in 'bay','status','jobNum','pm','startISO','shipISO','open','done') {
    if ("$($x.$p)" -ne "$($y.$p)") { Note ("job '{0}'  {1}: A='{2}' B='{3}'" -f $k, $p, $x.$p, $y.$p) }
  }
}
foreach ($k in ($jb.Keys | Sort-Object)) { if (-not $ja.ContainsKey($k)) { Note "job only in B: '$k'" } }

# ---- projects (key = name) ----
function Proj-Map($d) {
  $m = @{}
  foreach ($p in @($d.projects)) {
    $m["$($p.name)"] = [PSCustomObject]@{
      pm = "$($p.pm)"; tasks = [int]$p.taskCount; done = [int]$p.doneCount; pct = [int]$p.pct
      startISO = "$($p.startISO)"; finishISO = "$($p.finishISO)"
    }
  }
  return $m
}
$pa = Proj-Map $da; $pb = Proj-Map $db
Write-Host "Projects:"
foreach ($k in ($pa.Keys | Sort-Object)) {
  if (-not $pb.ContainsKey($k)) { Note "project only in A: '$k'"; continue }
  $x = $pa[$k]; $y = $pb[$k]
  foreach ($p in 'pm','tasks','done','pct','startISO','finishISO') {
    if ("$($x.$p)" -ne "$($y.$p)") { Note ("project '{0}'  {1}: A='{2}' B='{3}'" -f $k, $p, $x.$p, $y.$p) }
  }
}
foreach ($k in ($pb.Keys | Sort-Object)) { if (-not $pa.ContainsKey($k)) { Note "project only in B: '$k'" } }

# ---- users + holidays (by name) ----
$ua = @($da.users | ForEach-Object { "$($_.name)" }) | Sort-Object
$ub = @($db.users | ForEach-Object { "$($_.name)" }) | Sort-Object
foreach ($n in ($ua | Where-Object { $_ -notin $ub })) { Note "user only in A: '$n'" }
foreach ($n in ($ub | Where-Object { $_ -notin $ua })) { Note "user only in B: '$n'" }

$ha = @($da.holidays | ForEach-Object { "$($_.name)|$($_.dateISO)" }) | Sort-Object
$hb = @($db.holidays | ForEach-Object { "$($_.name)|$($_.dateISO)" }) | Sort-Object
foreach ($n in ($ha | Where-Object { $_ -notin $hb })) { Note "holiday only in A: '$n'" }
foreach ($n in ($hb | Where-Object { $_ -notin $ha })) { Note "holiday only in B: '$n'" }

Write-Host ""
if ($issues -eq 0) { Write-Host "MATCH - no differences in jobs/projects/users/holidays. Safe to wire the read path." -ForegroundColor Green }
else { Write-Host ("$issues difference(s) found - resolve these before flipping export.yml.") -ForegroundColor Yellow }
