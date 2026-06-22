<#
  Export-FromLists.ps1   (STEP 3 - read path, STAGED / not yet wired to deploy)

  Builds the dashboard's data.js from the 4 SharePoint Lists instead of the .xlsx,
  using Microsoft Graph app-only auth (the "MRA Dashboard Lists Reader" app).

  Fleet (Fleetio/Samsara) and the logistics "Coming Back to MRA" calendars are NOT
  in the Lists - they were never in Excel either. So this script PASSES THOSE
  THROUGH unchanged from an existing data.js (default ./data.js). That way a diff
  against the current Excel-built data.js focuses only on the List-sourced sections
  (jobs / projects / teamTasks / users / holidays).

  PREREQS (Part A by IT, Part B by Rich already done): these env vars are set:
    SP_TENANT_ID, SP_CLIENT_ID, SP_CLIENT_SECRET
  Optional env:
    MRA_SITE_URL     (default = the MRA Site Project site)
    MRA_BASE_DATAJS  (existing data.js to inherit fleet/logistics/physicalBays from)

  RUN (validation, writes a CANDIDATE file - does NOT touch the live data.js):
    ./Export-FromLists.ps1 -OutFile data.fromlists.js
    ./Compare-DataJs.ps1 data.js data.fromlists.js     # see what differs

  KNOWN GAPS to resolve during validation (see notes at bottom):
    - Jobs list as migrated lacks PM / Start date / Notes (added to Provision now;
      needs a one-time backfill before the numbers match the Excel build exactly).
    - Shop Tasks list lacks Opened/Closed dates, so a done task's "(closed m/d/yy)"
      tag won't render. Cosmetic; add Opened/Closed columns if we want parity.
#>
param(
  [string]$SiteUrl      = $(if ($env:MRA_SITE_URL) { $env:MRA_SITE_URL } else { 'https://snptechnical.sharepoint.com/sites/MRASiteProject' }),
  [string]$OutFile      = 'data.fromlists.js',
  [string]$BaseDataJs   = $(if ($env:MRA_BASE_DATAJS) { $env:MRA_BASE_DATAJS } else { 'data.js' }),
  [string]$TenantId     = $env:SP_TENANT_ID,
  [string]$ClientId     = $env:SP_CLIENT_ID,
  [string]$ClientSecret = $env:SP_CLIENT_SECRET
)

$ErrorActionPreference = 'Stop'

if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
  throw "Missing SP_TENANT_ID / SP_CLIENT_ID / SP_CLIENT_SECRET. Set them (GitHub secrets / env) before running."
}

$PhysicalBays = @('Bay 2 Front','Bay 2 Back / Loading Dock','Bay 3 Front','Bay 3 Back',
                  'Bay 4 Front','Bay 4 Back','Bay 5 Front','Bay 5 Back',
                  'Parking Lot','On Hold/Off-Site')

# --- Graph auth + helpers ---------------------------------------------------
function Get-GraphToken {
  $body = @{
    client_id     = $ClientId
    scope         = 'https://graph.microsoft.com/.default'
    client_secret = $ClientSecret
    grant_type    = 'client_credentials'
  }
  $resp = Invoke-RestMethod -Method Post -ContentType 'application/x-www-form-urlencoded' `
    -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Body $body
  return $resp.access_token
}

$script:Token = Get-GraphToken

function Graph-Get([string]$url) {
  return Invoke-RestMethod -Method Get -Uri $url -Headers @{ Authorization = "Bearer $script:Token" }
}

# GET with @odata.nextLink paging -> flat array of .value items
function Graph-GetAll([string]$url) {
  $items = New-Object System.Collections.ArrayList
  while ($url) {
    $r = Graph-Get $url
    if ($r.value) { foreach ($v in $r.value) { [void]$items.Add($v) } }
    $url = $r.'@odata.nextLink'
  }
  return $items
}

# --- field readers (tolerant of however the columns got named on import) -----
function FF($fields, [string[]]$names) {
  foreach ($n in $names) {
    if ($fields.PSObject.Properties.Name -contains $n) {
      $v = $fields.$n
      if ($null -ne $v -and "$v" -ne '') { return "$v" }
    }
  }
  return ''
}
function FFBool($fields, [string[]]$names) {
  foreach ($n in $names) {
    if ($fields.PSObject.Properties.Name -contains $n) {
      $v = $fields.$n
      if ($v -is [bool]) { return $v }
      if ($null -ne $v)  { return ("$v" -match '(?i)^(1|true|yes|y)$') }
    }
  }
  return $false
}
function AsNum($v) { $d = 0.0; if ([double]::TryParse("$v", [ref]$d)) { return $d } return $null }
function NumStr($v) {
  $d = AsNum $v
  if ($null -eq $d) { return '' }
  if ([math]::Floor($d) -eq $d) { return ([int64]$d).ToString() }
  return "$d"
}
function Get-PinHash([string]$s) {
  $h = [uint64]0
  foreach ($ch in $s.ToCharArray()) { $h = (($h * 31) + [uint64][int][char]$ch) % 4294967296 }
  return [int64]$h
}
function NormGen([string]$s) { return ((($s) -replace '[^\w ]','').Trim().ToLower()) }

# --- resolve the site + the lists -------------------------------------------
$u = [Uri]$SiteUrl
$siteRef = "$($u.Host):$($u.AbsolutePath)"
$site = Graph-Get "https://graph.microsoft.com/v1.0/sites/$siteRef"
$siteId = $site.id
Write-Host "Site: $($site.displayName)  ($siteId)"

$lists = Graph-GetAll ("https://graph.microsoft.com/v1.0/sites/$siteId/lists?" + '$select=id,displayName,name&$top=200')
function List-Id([string]$display) {
  $l = $lists | Where-Object { $_.displayName -eq $display -or $_.name -eq $display } | Select-Object -First 1
  if (-not $l) { throw "List not found: '$display'. Found: " + (($lists | ForEach-Object { $_.displayName }) -join ', ') }
  return $l.id
}
function Items([string]$display) {
  $id = List-Id $display
  return Graph-GetAll ("https://graph.microsoft.com/v1.0/sites/$siteId/lists/$id/items?" + '$expand=fields&$top=2000')
}

# --- Shop Tasks (grouped by project, normalized) -----------------------------
$shopByProj = @{}
foreach ($it in (Items 'MRA Shop Tasks')) {
  $f = $it.fields
  $task = FF $f @('Title')
  if ($task -eq '') { continue }
  $proj = FF $f @('Project','Project0')
  $op = FF $f @('Opened')
  $cl = FF $f @('Closed')
  $rec = [PSCustomObject]@{
    task = $task
    who  = (FF $f @('Assigned','AssignedTo','Assigned_x0020_To'))
    st   = (FF $f @('Status'))
    ml   = $(if (FFBool $f @('Milestone')) { 'Yes' } else { '' })
    cm   = (FF $f @('Comments'))
    op   = $(if ($op -ne '') { $op } else { $null })
    cl   = $(if ($cl -ne '') { $cl } else { $null })
  }
  $rec | Add-Member done ([bool](($rec.st -match '(?i)done|complete') -or ($null -ne $rec.cl)))
  $key = NormGen $proj
  if (-not $shopByProj.ContainsKey($key)) { $shopByProj[$key] = New-Object System.Collections.ArrayList }
  [void]$shopByProj[$key].Add($rec)
}

# Mirror Build-TasksFromRows from Export-Data.ps1 (same on-screen shape)
function Build-TasksFromRows($rows) {
  $open = New-Object System.Collections.ArrayList
  $done = New-Object System.Collections.ArrayList
  $tasks = New-Object System.Collections.ArrayList
  $doneCount = 0; $salOpen = 0; $n = 0
  foreach ($r in $rows) {
    $who = [string]$r.who
    $label = if ($who -ne '') { "$who - $($r.task)" } else { [string]$r.task }
    if ($r.done) {
      $doneCount++
      $cdisp = ''
      if ($r.cl) { $p = ([string]$r.cl).Split('-'); if ($p.Count -eq 3) { $cdisp = "  (closed " + [int]$p[1] + "/" + [int]$p[2] + "/" + $p[0].Substring(2) + ")" } }
      [void]$done.Add($label + $cdisp)
    } else {
      $n++
      [void]$open.Add("$n. $label")
      if ($label -match '(?i)\bsal\b') { $salOpen++ }
    }
    [void]$tasks.Add([PSCustomObject]@{ t = [string]$r.task; who = $who; op = $r.op; cl = $r.cl; st = [string]$r.st; done = [bool]$r.done; ml = [string]$r.ml; cm = [string]$r.cm })
  }
  return @{ open = @($open); openCount = $open.Count; doneCount = $doneCount; salOpen = $salOpen; done = @($done); tasks = @($tasks) }
}

# --- Jobs -------------------------------------------------------------------
$jobs = New-Object System.Collections.ArrayList
$genJob = $null
$usedKeys = @{}
foreach ($it in (Items 'MRA Jobs')) {
  $f = $it.fields
  $proj = FF $f @('Title')
  if ($proj -eq '') { continue }

  $bay    = FF $f @('Bay')
  $client = FF $f @('Client')
  $job    = FF $f @('JobNum','Job_x0020_Num','JobNumber')
  $status = FF $f @('JobStatus','Status')
  $pm     = FF $f @('PM')                  # gap: not on migrated list yet
  $notes  = FF $f @('Notes','Notes0')      # gap: not on migrated list yet
  $startISO = FF $f @('StartISO')          # gap: not on migrated list yet
  $compISO  = FF $f @('ShipISO','CompletionISO')
  $rowNum   = NumStr (FF $f @('SortOrder'))

  $nkey = NormGen $proj
  $stRows = $null
  if ($shopByProj.ContainsKey($nkey)) { $stRows = $shopByProj[$nkey]; $usedKeys[$nkey] = $true }
  $t = if ($stRows -and $stRows.Count -gt 0) { Build-TasksFromRows $stRows } else { @{ open=@(); openCount=0; doneCount=0; salOpen=0; done=@(); tasks=@() } }

  $isGeneral = ($nkey -eq 'general')
  $category = 'bay'
  if ($isGeneral) { $category = 'general' }
  elseif ($status -eq 'Leave' -or $bay -eq 'APL/Holidays') { $category = 'leave' }
  elseif ($bay -notin $PhysicalBays) { $category = 'pipeline' }

  $startTxt = ''; $compTxt = ''
  if ($startISO -match '^\d{4}-\d{2}-\d{2}$') { $p = $startISO.Split('-'); $startTxt = "$([int]$p[1])/$([int]$p[2])/$($p[0].Substring(2))" }
  if ($compISO  -match '^\d{4}-\d{2}-\d{2}$') { $p = $compISO.Split('-');  $compTxt  = "$([int]$p[1])/$([int]$p[2])/$($p[0].Substring(2))" }

  $rec = [PSCustomObject]@{
    row = $(if ($isGeneral) { 'general' } elseif ($rowNum -ne '') { [int]$rowNum } else { $rowNum })
    bay = $bay; project = $proj; client = $client; jobNum = $job
    status = $status; pm = $pm
    startISO = $(if ($startISO -ne '') { $startISO } else { $null })
    completionISO = $(if ($compISO -ne '') { $compISO } else { $null })
    startText = $startTxt; completionText = $compTxt; category = $category
    notesRaw = $notes
    openTasks = $t.open; openCount = $t.openCount; doneCount = $t.doneCount; salOpen = $t.salOpen; doneTasks = $t.done; tasks = $t.tasks
  }
  if ($isGeneral) { $genJob = $rec } else { [void]$jobs.Add($rec) }
}

# any general shop tasks whose job row wasn't in the Jobs list -> synth the lane
if (-not $genJob -and $shopByProj.ContainsKey('general')) {
  $gt = Build-TasksFromRows $shopByProj['general']
  $genJob = [PSCustomObject]@{
    row='general'; bay='General'; project=("$([char]0xD83D)$([char]0xDEE0) General"); client=''; jobNum=''
    status=''; pm=''; startISO=$null; completionISO=$null; startText=''; completionText=''; category='general'; notesRaw=''
    openTasks=$gt.open; openCount=$gt.openCount; doneCount=$gt.doneCount; salOpen=$gt.salOpen; doneTasks=$gt.done; tasks=$gt.tasks
  }
}

# order jobs by their original Input row, general lane last (matches Export-Data)
$jobsSorted = @($jobs | Sort-Object { if ($_.row -is [int]) { $_.row } else { 999999 } })
$jobsOut = New-Object System.Collections.ArrayList
foreach ($j in $jobsSorted) { [void]$jobsOut.Add($j) }
if ($genJob) { [void]$jobsOut.Add($genJob) }

# --- Project Tasks -> projects + teamTasks (mirror Add-TaskRow) --------------
$pmap = [ordered]@{}
$teamTasks = New-Object System.Collections.ArrayList
foreach ($it in (Items 'MRA Project Tasks')) {
  $f = $it.fields
  $name = FF $f @('Project','Project0')
  if ($name -eq '') { continue }

  $pTask   = FF $f @('Title')
  $pPhase  = FF $f @('Phase')
  $pType   = FF $f @('Type')
  $pStatus = FF $f @('Status')
  $pPM     = FF $f @('PM')
  $pAssigned = FF $f @('Assigned','AssignedTo','Assigned_x0020_To')
  $pComments = FF $f @('Comments')
  $pDur    = FF $f @('Duration')
  $pTaskId = NumStr (FF $f @('TaskID','Task_x0020_ID'))
  $pPred   = FF $f @('Predecessor')
  $pSubRes = FF $f @('SubRes')
  $startISO = FF $f @('StartISO')
  $finISO   = FF $f @('FinishISO')
  $pMile   = $(if (FFBool $f @('Milestone')) { 'Yes' } else { '' })
  $pSub    = (FFBool $f @('Sub'))
  $pParent = NumStr (FF $f @('ParentID','Parent_x0020_ID'))
  $pOrder  = AsNum (FF $f @('SortOrder'))
  $pEstDays  = AsNum (FF $f @('EstDays'))
  $pEstHours = AsNum (FF $f @('EstHours'))
  $pBudget   = AsNum (FF $f @('Budget'))

  $sISO = $(if ($startISO -match '^\d{4}-\d{2}-\d{2}$') { $startISO } else { $null })
  $fISO = $(if ($finISO   -match '^\d{4}-\d{2}-\d{2}$') { $finISO   } else { $null })

  if (-not $pmap.Contains($name)) {
    $pmap[$name] = [PSCustomObject]@{
      name = $name; pm = ''; minStart = $null; maxFinish = $null
      taskCount = 0; doneCount = 0; pctSum = 0
      estDays = 0.0; estHours = 0.0; budget = 0.0
      milestones = (New-Object System.Collections.ArrayList)
      tasks      = (New-Object System.Collections.ArrayList)
    }
  }
  $o = $pmap[$name]
  $o.taskCount++
  if ($pStatus -eq 'Completed') { $o.doneCount++ }
  $tp = 0
  if ($pStatus -eq 'Completed') { $tp = 100 }
  elseif ($pStatus -match '(\d{1,3})\s*%') { $tp = [int]$matches[1]; if ($tp -gt 100) { $tp = 100 } elseif ($tp -lt 0) { $tp = 0 } }
  $o.pctSum += $tp
  if ($null -ne $pEstDays)  { $o.estDays  += $pEstDays }
  if ($null -ne $pEstHours) { $o.estHours += $pEstHours }
  if ($null -ne $pBudget)   { $o.budget   += $pBudget }
  if ($pPM -ne '' -and $o.pm -eq '') { $o.pm = $pPM }
  # ISO strings sort lexically, so min/max without DateTime parsing
  if ($sISO -and ($null -eq $o.minStart  -or $sISO -lt $o.minStart))  { $o.minStart  = $sISO }
  if ($fISO -and ($null -eq $o.maxFinish -or $fISO -gt $o.maxFinish)) { $o.maxFinish = $fISO }
  if ($pMile -eq 'Yes') {
    $md = if ($fISO) { $fISO } elseif ($sISO) { $sISO } else { $null }
    if ($md) { [void]$o.milestones.Add([PSCustomObject]@{
      name = $pTask; dateISO = $md; owner = $pAssigned; status = $pStatus; phase = $pPhase
      done = ($pStatus -eq 'Completed') }) }
  }
  if ($pAssigned -ne '' -and $pStatus -ne 'Completed') {
    $dueISO = if ($fISO) { $fISO } elseif ($sISO) { $sISO } else { $null }
    [void]$teamTasks.Add([PSCustomObject]@{ assignee = $pAssigned; project = $name; task = $pTask; dueISO = $dueISO; status = $pStatus })
  }
  [void]$o.tasks.Add([PSCustomObject]@{
    id = $pTaskId; t = $pTask; phase = $pPhase; type = $pType; who = $pAssigned
    startISO = $sISO; finISO = $fISO; dur = $pDur; st = $pStatus; ml = $pMile; cm = $pComments
    pred = $pPred; sub = $pSub; parent = $pParent; subRes = $pSubRes
    ord = $pOrder; eD = $pEstDays; eH = $pEstHours; bud = $pBudget
    done = ($pStatus -eq 'Completed')
  })
}

$projects = New-Object System.Collections.ArrayList
foreach ($o in $pmap.Values) {
  $pct = if ($o.taskCount -gt 0) { [math]::Round($o.pctSum / $o.taskCount) } else { 0 }
  [void]$projects.Add([PSCustomObject]@{
    name = $o.name; pm = $o.pm
    startISO  = $o.minStart
    finishISO = $o.maxFinish
    taskCount = $o.taskCount; doneCount = $o.doneCount; pct = $pct
    estDays = $o.estDays; estHours = $o.estHours; budget = $o.budget
    milestones = @($o.milestones); tasks = @($o.tasks)
  })
}

# --- Users (hash the plaintext Code from the list; skip inactive/blank) ------
$users = New-Object System.Collections.ArrayList
foreach ($it in (Items 'MRA Users')) {
  $f = $it.fields
  $name = FF $f @('Title')
  $code = FF $f @('Code')
  if ($name -eq '' -or $code -eq '') { continue }
  $activeProp = $f.PSObject.Properties.Name -contains 'Active'
  if ($activeProp -and -not (FFBool $f @('Active'))) { continue }
  [void]$users.Add([PSCustomObject]@{ name = $name; h = (Get-PinHash $code) })
}

# --- Holidays ---------------------------------------------------------------
$holidays = New-Object System.Collections.ArrayList
$hasHol = ($lists | Where-Object { $_.displayName -eq 'MRA Holidays' })
if ($hasHol) {
  foreach ($it in (Items 'MRA Holidays')) {
    $f = $it.fields
    $name = FF $f @('Title')
    $d    = FF $f @('DateISO','Date')
    $ctry = (FF $f @('Country')).ToUpper()
    if ($name -eq '' -or $d -notmatch '^\d{4}-\d{2}-\d{2}$') { continue }
    if ($ctry -notin @('US','CA','BOTH')) { $ctry = 'US' }
    [void]$holidays.Add([PSCustomObject]@{ name = $name; dateISO = $d; country = $ctry })
  }
}

# --- inherit fleet + logistics + physicalBays from the existing data.js ------
$fleetio = $null; $mraStatus = @(); $physOut = $PhysicalBays
if (Test-Path $BaseDataJs) {
  try {
    $raw = Get-Content -Raw $BaseDataJs
    $jsonTxt = $raw.Substring($raw.IndexOf('{'))
    $jsonTxt = $jsonTxt.Substring(0, $jsonTxt.LastIndexOf('}') + 1)
    $base = $jsonTxt | ConvertFrom-Json
    if ($base.fleetio)      { $fleetio = $base.fleetio }
    if ($base.mraStatus)    { $mraStatus = $base.mraStatus }
    if ($base.physicalBays) { $physOut = $base.physicalBays }
  } catch { Write-Host "  (couldn't inherit fleet/logistics from $BaseDataJs : $($_.Exception.Message))" }
}

# --- write candidate data.js ------------------------------------------------
$now = Get-Date
$payload = [PSCustomObject]@{
  generatedAt   = $now.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  generatedText = $now.ToString('ddd MMM d, yyyy  h:mm tt')
  todayISO      = $now.ToString('yyyy-MM-dd')
  physicalBays  = $physOut
  jobs          = @($jobsOut)
  projects      = @($projects)
  teamTasks     = @($teamTasks)
  fleetio       = $fleetio
  mraStatus     = @($mraStatus)
  users         = @($users)
  holidays      = @($holidays)
  source        = 'lists'
}
$json = $payload | ConvertTo-Json -Depth 8
$content = "// Auto-generated by Export-FromLists.ps1 - do not edit by hand`r`nwindow.MRA_DATA = $json;"
Set-Content -Path $OutFile -Value $content -Encoding UTF8

Write-Host ""
Write-Host "Wrote $OutFile from SharePoint Lists:"
Write-Host ("  jobs={0}  projects={1}  teamTasks={2}  users={3}  holidays={4}" -f $jobsOut.Count, $projects.Count, $teamTasks.Count, $users.Count, $holidays.Count)
$orphan = @($shopByProj.Keys | Where-Object { -not $usedKeys.ContainsKey($_) -and $_ -ne 'general' })
if ($orphan.Count -gt 0) { Write-Host ("  NOTE: shop tasks for {0} project(s) matched no job: {1}" -f $orphan.Count, ($orphan -join ', ')) }
Write-Host "Next: ./Compare-DataJs.ps1 data.js $OutFile"
