<#
  Migrate-Data-To-Lists.ps1
  STEP 3 (2 of 4): fill the SharePoint Lists from the current board data.

  It reads data.js (the already-parsed board snapshot) instead of the raw .xlsx,
  so it reuses the export's parsing and can't disagree with what's on the board.

  PREREQS:
    Install-Module PnP.PowerShell -Scope CurrentUser   # one time
    Run Provision-MRA-Lists.ps1 first.
    Be a SITE OWNER of the MRA Site Project site.

  RUN (from the folder that has data.js):
    ./Migrate-Data-To-Lists.ps1 -SiteUrl "https://snptechnical.sharepoint.com/sites/MRASiteProject"
    # add  -Fresh  to wipe the 3 task lists first (use when re-running, to avoid dupes)

  NOTE on Users: data.js stores only a HASH of each login code (by design - codes
  are never published). So this script does NOT migrate Users. There are only a
  couple; add them by hand in the "MRA Users" list (Name / Code / Active / Role),
  or pass -UsersCsv pointing at a CSV with columns: Name,Code,Active,Role.
#>
param(
  [Parameter(Mandatory = $true)] [string] $SiteUrl,
  [string] $DataJs = "./data.js",
  [string] $UsersCsv = "",
  [switch] $Fresh
)

$ErrorActionPreference = 'Stop'
Connect-PnPOnline -Url $SiteUrl -Interactive

# ---- load data.js -> object --------------------------------------------------
if (-not (Test-Path $DataJs)) { throw "data.js not found at $DataJs" }
$raw  = Get-Content -Raw $DataJs
$json = $raw -replace '(?s)^.*?window\.MRA_DATA\s*=\s*', ''   # drop the JS prefix
$json = $json.Trim().TrimEnd(';')
$D    = $json | ConvertFrom-Json

# ---- helpers -----------------------------------------------------------------
function AsNum($v) { $d = 0.0; if ([double]::TryParse("$v", [ref]$d)) { return $d } return $null }
function IsYes($v) { return [bool]("$v" -match '^(yes|y|true|1)$') }
# build a Values hashtable, dropping null/empty so Choice/Number fields don't choke
function NV([hashtable]$h) {
  $o = @{}
  foreach ($k in $h.Keys) { $v = $h[$k]; if ($null -ne $v -and "$v" -ne '') { $o[$k] = $v } }
  return $o
}
function Clear-List([string]$title) {
  Write-Host "Clearing '$title'..." -ForegroundColor Yellow
  $items = Get-PnPListItem -List $title -PageSize 500 -Fields 'ID'
  foreach ($it in $items) { Remove-PnPListItem -List $title -Identity $it.Id -Force | Out-Null }
}

if ($Fresh) { 'MRA Jobs', 'MRA Shop Tasks', 'MRA Project Tasks' | ForEach-Object { Clear-List $_ } }

# ---- Jobs + Shop Tasks -------------------------------------------------------
$nJ = 0; $nST = 0
foreach ($j in $D.jobs) {
  if (-not $j.project) { continue }
  Add-PnPListItem -List 'MRA Jobs' -Values (NV @{
      Title       = $j.project
      Bay         = $j.bay
      Client      = $j.client
      JobNum      = $j.jobNum
      JobStatus   = $j.status
      Category    = $j.category
      ShipISO     = $j.completionISO
      SortOrder   = (AsNum $j.row)
      PhysicalBay = $false
    }) | Out-Null
  $nJ++
  foreach ($t in $j.tasks) {
    if (-not $t.t) { continue }
    $st = if ($t.st) { $t.st } elseif ($t.done) { 'Done' } else { 'Open' }
    Add-PnPListItem -List 'MRA Shop Tasks' -Values (NV @{
        Title     = $t.t
        Project   = $j.project
        Assigned  = $t.who
        Status    = $st
        Milestone = (IsYes $t.ml)
        Comments  = $t.cm
      }) | Out-Null
    $nST++
  }
}

# ---- Project Tasks -----------------------------------------------------------
$nPT = 0
foreach ($p in $D.projects) {
  if (-not $p.name) { continue }
  foreach ($t in $p.tasks) {
    if (-not $t.t) { continue }
    Add-PnPListItem -List 'MRA Project Tasks' -Values (NV @{
        Title       = $t.t
        Project     = $p.name
        TaskID      = (AsNum $t.id)
        Phase       = $t.phase
        Type        = $t.type
        Assigned    = $t.who
        StartISO    = $t.startISO
        FinishISO   = $t.finISO
        Duration    = $t.dur
        Status      = $t.st
        PM          = $p.pm
        Milestone   = (IsYes $t.ml)
        Comments    = $t.cm
        Predecessor = $t.pred
        Sub         = (IsYes $t.sub)
        ParentID    = (AsNum $t.parent)
        SubRes      = $t.subRes
        EstDays     = (AsNum $t.eD)
        EstHours    = (AsNum $t.eH)
        Budget      = (AsNum $t.bud)
        SortOrder   = (AsNum $t.ord)
      }) | Out-Null
    $nPT++
  }
}

# ---- Users (optional, from a CSV - codes are not in data.js) ------------------
$nU = 0
if ($UsersCsv -and (Test-Path $UsersCsv)) {
  foreach ($row in (Import-Csv $UsersCsv)) {
    if (-not $row.Name) { continue }
    Add-PnPListItem -List 'MRA Users' -Values (NV @{
        Title  = $row.Name
        Code   = $row.Code
        Active = (IsYes $row.Active)
        Role   = $row.Role
      }) | Out-Null
    $nU++
  }
}

Write-Host "`nMigrated: $nJ jobs, $nST shop tasks, $nPT project tasks, $nU users." -ForegroundColor Cyan
if ($nU -eq 0) { Write-Host "Users: add them by hand in 'MRA Users' (Name/Code/Active/Role), or re-run with -UsersCsv." -ForegroundColor Yellow }
Write-Host "Next: spot-check a project + a trailer against the board, then we wire the read path (Export-FromLists)." -ForegroundColor Yellow
