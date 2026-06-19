# =============================================================================
#  MRA Shop Board - Data Export  (no Excel required)
#  Reads the Input sheet straight from the .xlsx (which is a zip of XML) and
#  writes data.js for the dashboard. Safe to run while the file is open in Excel
#  and lightweight enough to run on a schedule every few minutes.
# =============================================================================

$ErrorActionPreference = 'Stop'

# --- Config -----------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Workbook  = Join-Path (Split-Path -Parent $ScriptDir) 'MRA_Shop_Board_v6_9_7.xlsx'
$OutFile   = Join-Path $ScriptDir 'data.js'
$SheetName = 'Input'

$PhysicalBays = @('Bay 2 Front','Bay 2 Back / Loading Dock','Bay 3 Front','Bay 3 Back',
                  'Bay 4 Front','Bay 4 Back','Bay 5 Front','Bay 5 Back',
                  'Parking Lot','On Hold/Off-Site')

# Input column letters
$COL = @{ Bay='A'; Project='B'; Client='C'; Job='D'; Start='E'; Comp='F';
          Status='G'; Notes='H'; PM='K' }

Add-Type -AssemblyName System.IO.Compression.FileSystem

# --- Helpers ----------------------------------------------------------------
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

function Get-CellDate($c) {
    if ($null -eq $c) { return $null }
    if ($c.t -in @('s','inlineStr','str')) { return $null }
    $v = $c.v
    if ([string]::IsNullOrEmpty($v)) { return $null }
    try { return [DateTime]::FromOADate([double]$v) } catch { return $null }
}

function Parse-Tasks($text) {
    $open = New-Object System.Collections.ArrayList
    $done = New-Object System.Collections.ArrayList
    $doneCount = 0; $salOpen = 0
    if ($null -ne $text -and $text.Trim() -ne '') {
        foreach ($lnRaw in ($text -split "`r?`n")) {
            $ln = $lnRaw.Trim()
            if ($ln -eq '') { continue }
            if ($ln -match '^[xX]\s') {
                $doneCount++
                $dt = ($ln -replace '^[xX]\s+','').Trim()
                if ($dt -ne '') { [void]$done.Add($dt) }
            }
            elseif ($ln -match '^\d+\s*[\.\)\-]') {
                [void]$open.Add($ln)
                if ($ln -match '(?i)\bsal\b') { $salOpen++ }
            }
        }
    }
    return @{ open = @($open); openCount = $open.Count; doneCount = $doneCount; salOpen = $salOpen; done = @($done); tasks = @() }
}

# ---- Structured tasks (Phase B) -------------------------------------------
# Optional 'Shop Tasks' sheet: one row per task, mirroring Project Tasks.
#   A=Job#  B=Bay  C=Task  D=Assigned  E=Opened  F=Closed  G=Status
#   H=Milestone  I=Comments
# If the sheet is absent (or a job has no rows), we fall back to Parse-Tasks on
# the Input Notes cell -> fully backward-compatible, nothing changes until the
# sheet exists.
function Read-ShopTasks($zip, $wbXml, $relsXml, $shared, $nsMain, $nsRel, $nsPkg) {
    # Rows are matched to a job by Project (col A) OR Job# (col B) — case-insensitive —
    # so a small project-name mismatch doesn't silently drop the task. Returns lookup
    # maps plus a flat list (for unmatched-row logging).
    $byProj = @{}; $byJob = @{}; $all = New-Object System.Collections.ArrayList
    $sx = Get-SheetXml $zip $wbXml $relsXml 'Shop Tasks' $nsMain $nsRel $nsPkg
    if (-not $sx) { return [PSCustomObject]@{ byProj = $byProj; byJob = $byJob; all = $all } }
    foreach ($row in $sx.worksheet.sheetData.row) {
        if ([int]$row.r -lt 2) { continue }
        $c = Get-RowCells $row
        $key  = ([string](Resolve-Cell $c['A'] $shared)).Trim()   # Project (match key)
        $jobn = ([string](Resolve-Cell $c['B'] $shared)).Trim()   # Job # (also a match key)
        $task = ([string](Resolve-Cell $c['D'] $shared)).Trim()
        if ($task -eq '') { continue }                            # only a Task is required
        $assigned = ([string](Resolve-Cell $c['E'] $shared)).Trim()
        $od = Get-CellDate $c['F']
        $cl = Get-CellDate $c['G']
        $status = ([string](Resolve-Cell $c['H'] $shared)).Trim()
        $mile   = ([string](Resolve-Cell $c['I'] $shared)).Trim()
        $cmt    = ([string](Resolve-Cell $c['J'] $shared)).Trim()
        $isDone = ($status -match '(?i)done|complete') -or ($null -ne $cl)
        $obj = [PSCustomObject]@{
            task = $task; who = $assigned
            opened = $(if ($od) { $od.ToString('yyyy-MM-dd') } else { $null })
            closed = $(if ($cl) { $cl.ToString('yyyy-MM-dd') } else { $null })
            status = $status; milestone = $mile; comments = $cmt; done = $isDone
            proj = $key; jobNum = $jobn; matched = $false
        }
        [void]$all.Add($obj)
        if ($key -ne '')  { $pk = $key.ToLower();  if (-not $byProj.ContainsKey($pk)) { $byProj[$pk] = New-Object System.Collections.ArrayList }; [void]$byProj[$pk].Add($obj) }
        if ($jobn -ne '') { $jk = $jobn.ToLower(); if (-not $byJob.ContainsKey($jk))  { $byJob[$jk]  = New-Object System.Collections.ArrayList }; [void]$byJob[$jk].Add($obj) }
    }
    return [PSCustomObject]@{ byProj = $byProj; byJob = $byJob; all = $all }
}

# Match the dashboard's pinHash exactly:  h = (h*31 + charCode) >>> 0  (per char).
function Get-PinHash([string]$s) {
    $h = [uint64]0
    foreach ($ch in $s.ToCharArray()) { $h = (($h * 31) + [uint64][int][char]$ch) % 4294967296 }
    return [int64]$h
}

# Optional 'Users' sheet -> per-person logins.  Columns: A=Name  B=Code  C=Active.
# Emits name + HASHED code (raw codes never leave the workbook). Inactive/blank skipped.
function Read-Users($zip, $wbXml, $relsXml, $shared, $nsMain, $nsRel, $nsPkg) {
    $list = New-Object System.Collections.ArrayList
    $sx = Get-SheetXml $zip $wbXml $relsXml 'Users' $nsMain $nsRel $nsPkg
    if (-not $sx) { return ,@() }
    foreach ($row in $sx.worksheet.sheetData.row) {
        if ([int]$row.r -lt 2) { continue }     # row 1 = headers
        $c = Get-RowCells $row
        $name = ([string](Resolve-Cell $c['A'] $shared)).Trim()
        $code = ([string](Resolve-Cell $c['B'] $shared)).Trim()
        $act  = ([string](Resolve-Cell $c['C'] $shared)).Trim()
        if ($name -eq '' -or $code -eq '') { continue }
        if ($act -match '(?i)^(no|n|inactive|0|false)$') { continue }
        if ($code -match '^\d+\.0+$') { $code = $code -replace '\.0+$','' }   # numeric cell safety
        [void]$list.Add([PSCustomObject]@{ name = $name; h = (Get-PinHash $code) })
    }
    return ,@($list)
}

# Turn structured task rows into the same shape Parse-Tasks emits (so the
# dashboard renders them with zero changes), plus a structured 'tasks' array.
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
            if ($r.closed) { $p = $r.closed.Split('-'); $cdisp = "  (closed " + [int]$p[1] + "/" + [int]$p[2] + "/" + $p[0].Substring(2) + ")" }
            [void]$done.Add($label + $cdisp)
        } else {
            $n++
            [void]$open.Add("$n. $label")
            if ($label -match '(?i)\bsal\b') { $salOpen++ }
        }
        [void]$tasks.Add([PSCustomObject]@{ t = [string]$r.task; who = $who; op = $r.opened; cl = $r.closed; st = [string]$r.status; done = [bool]$r.done; ml = [string]$r.milestone; cm = [string]$r.comments })
    }
    return @{ open = @($open); openCount = $open.Count; doneCount = $doneCount; salOpen = $salOpen; done = @($done); tasks = @($tasks) }
}

# Resolve a worksheet's XML by its display name (returns [xml] or $null)
function Get-SheetXml($zip, $wbXml, $relsXml, $name, $nsMain, $nsRel, $nsPkg) {
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

# Index a row's <c> cells by column letter (A, B, ...)
function Get-RowCells($row) {
    $cells = @{}
    foreach ($c in $row.c) {
        if ($null -eq $c.r) { continue }
        $cl = ([regex]::Match([string]$c.r, '^[A-Z]+')).Value
        $cells[$cl] = $c
    }
    return $cells
}

# Process one Project-Tasks-style row (cols A..L) into the project map + team
# tasks. Used for BOTH the master 'Project Tasks' sheet and 'Enter Here' rows
# from intake files dropped in the Intake Inbox (identical column layout).
function Add-TaskRow($pc, $shared, $pmap, $teamTasks) {
    $name = ([string](Resolve-Cell $pc['A'] $shared)).Trim()
    if ($name -eq '') { return }

    $pPhase    = ([string](Resolve-Cell $pc['B'] $shared)).Trim()
    $pType     = ([string](Resolve-Cell $pc['C'] $shared)).Trim()
    $pStatus   = ([string](Resolve-Cell $pc['I'] $shared)).Trim()
    $pPM       = ([string](Resolve-Cell $pc['J'] $shared)).Trim()
    $pMile     = ([string](Resolve-Cell $pc['K'] $shared)).Trim()
    $pTask     = ([string](Resolve-Cell $pc['D'] $shared)).Trim()
    $pAssigned = ([string](Resolve-Cell $pc['H'] $shared)).Trim()
    $pComments = ([string](Resolve-Cell $pc['L'] $shared)).Trim()
    $pDur      = ([string](Resolve-Cell $pc['G'] $shared)).Trim()
    $pTaskId   = ([string](Resolve-Cell $pc['M'] $shared)).Trim()   # Task ID  (col M)
    $pPred     = ([string](Resolve-Cell $pc['N'] $shared)).Trim()   # Predecessor (col N)
    $pSub      = ([string](Resolve-Cell $pc['O'] $shared)).Trim()   # Sub (col O) — 'x' = subtask of the task above
    $pSubRes   = ([string](Resolve-Cell $pc['P'] $shared)).Trim()   # Sub-Resource (col P) — person within the Assigned-To group
    if ($pTaskId -match '^\d+\.0+$')  { $pTaskId  = $pTaskId  -replace '\.0+$','' }   # numeric cell safety
    if ($pDur -match '^\d+\.0+$') { $pDur = $pDur -replace '\.0+$','' }
    $psd = Get-CellDate $pc['E']
    $pfd = Get-CellDate $pc['F']

    if (-not $pmap.Contains($name)) {
        $pmap[$name] = [PSCustomObject]@{
            name = $name; pm = ''; minStart = $null; maxFinish = $null
            taskCount = 0; doneCount = 0; pctSum = 0
            milestones = (New-Object System.Collections.ArrayList)
            tasks      = (New-Object System.Collections.ArrayList)
        }
    }
    $o = $pmap[$name]
    $o.taskCount++
    if ($pStatus -eq 'Completed') { $o.doneCount++ }
    # Per-task % toward the project rollup: Completed = 100, an embedded "NN%" (e.g. "In Progress 25%") = NN, else 0.
    $tp = 0
    if ($pStatus -eq 'Completed') { $tp = 100 }
    elseif ($pStatus -match '(\d{1,3})\s*%') { $tp = [int]$matches[1]; if ($tp -gt 100) { $tp = 100 } elseif ($tp -lt 0) { $tp = 0 } }
    $o.pctSum += $tp
    if ($pPM -ne '' -and $o.pm -eq '') { $o.pm = $pPM }
    if ($psd -and ($null -eq $o.minStart -or $psd -lt $o.minStart)) { $o.minStart = $psd }
    if ($pfd -and ($null -eq $o.maxFinish -or $pfd -gt $o.maxFinish)) { $o.maxFinish = $pfd }
    if ($pMile -eq 'Yes') {
        $md = if ($pfd) { $pfd } elseif ($psd) { $psd } else { $null }
        if ($md) { [void]$o.milestones.Add([PSCustomObject]@{
            name = $pTask; dateISO = $md.ToString('yyyy-MM-dd')
            owner = $pAssigned; status = $pStatus; phase = $pPhase
            done = ($pStatus -eq 'Completed') }) }
    }
    if ($pAssigned -ne '' -and $pStatus -ne 'Completed') {
        $dueISO = if ($pfd) { $pfd.ToString('yyyy-MM-dd') }
                  elseif ($psd) { $psd.ToString('yyyy-MM-dd') } else { $null }
        [void]$teamTasks.Add([PSCustomObject]@{
            assignee = $pAssigned; project = $name; task = $pTask
            dueISO = $dueISO; status = $pStatus
        })
    }

    # Full task list for the dashboard's Projects editor (every row, not just milestones).
    [void]$o.tasks.Add([PSCustomObject]@{
        id    = $pTaskId
        t     = $pTask
        phase = $pPhase
        type  = $pType
        who   = $pAssigned
        startISO = $(if ($psd) { $psd.ToString('yyyy-MM-dd') } else { $null })
        finISO   = $(if ($pfd) { $pfd.ToString('yyyy-MM-dd') } else { $null })
        dur   = $pDur
        st    = $pStatus
        ml    = $pMile
        cm    = $pComments
        pred  = $pPred
        sub   = ($pSub -match '^[xX]')
        subRes = $pSubRes
        done  = ($pStatus -eq 'Completed')
    })
}

# --- Copy workbook to temp (avoids any file lock) and open as zip ------------
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("mra_" + [System.IO.Path]::GetFileName($Workbook))
try { [System.IO.File]::Copy($Workbook, $tmp, $true) }
catch { $tmp = $Workbook }   # fall back to reading in place

$zip = [System.IO.Compression.ZipFile]::OpenRead($tmp)
$jobs = New-Object System.Collections.ArrayList
$projects = New-Object System.Collections.ArrayList
$teamTasks = New-Object System.Collections.ArrayList
$users = @()
try {
    $nsMain = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
    $nsRel  = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    $nsPkg  = 'http://schemas.openxmlformats.org/package/2006/relationships'

    # Shared strings
    $shared = New-Object System.Collections.ArrayList
    $ssXml = Read-Entry $zip 'xl/sharedStrings.xml'
    if ($ssXml) {
        [xml]$ss = $ssXml
        foreach ($si in $ss.sst.si) { [void]$shared.Add([string]$si.InnerText) }
    }

    # Workbook + relationships (used to resolve each sheet by name)
    [xml]$wbXml   = Read-Entry $zip 'xl/workbook.xml'
    [xml]$relsXml = Read-Entry $zip 'xl/_rels/workbook.xml.rels'

    # ===== Input sheet -> bay / pipeline / leave jobs =======================
    $sheetXml = Get-SheetXml $zip $wbXml $relsXml $SheetName $nsMain $nsRel $nsPkg
    if (-not $sheetXml) { throw "Sheet '$SheetName' not found" }

    # Structured shop tasks (optional 'Shop Tasks' sheet). Empty => use Notes cell.
    $shopTasks = Read-ShopTasks $zip $wbXml $relsXml $shared $nsMain $nsRel $nsPkg

    # Per-person logins (optional 'Users' sheet): name + hashed code for the dashboard.
    $users = Read-Users $zip $wbXml $relsXml $shared $nsMain $nsRel $nsPkg

    foreach ($row in $sheetXml.worksheet.sheetData.row) {
        $rowNum = [int]$row.r
        if ($rowNum -lt 4) { continue }

        $cells = Get-RowCells $row

        $proj = ([string](Resolve-Cell $cells[$COL.Project] $shared)).Trim()
        if ($proj -eq '') { continue }

        $bay    = ([string](Resolve-Cell $cells[$COL.Bay] $shared)).Trim()
        $client = ([string](Resolve-Cell $cells[$COL.Client] $shared)).Trim()
        $job    = ([string](Resolve-Cell $cells[$COL.Job] $shared)).Trim()
        $status = ([string](Resolve-Cell $cells[$COL.Status] $shared)).Trim()
        $notes  = [string](Resolve-Cell $cells[$COL.Notes] $shared)
        $pm     = ([string](Resolve-Cell $cells[$COL.PM] $shared)).Trim()

        $sd = Get-CellDate $cells[$COL.Start]
        $cd = Get-CellDate $cells[$COL.Comp]
        $startISO = if ($sd) { $sd.ToString('yyyy-MM-dd') } else { $null }
        $compISO  = if ($cd) { $cd.ToString('yyyy-MM-dd') } else { $null }
        $startTxt = if ($sd) { $sd.ToString('MM/dd/yy') } else { '' }
        $compTxt  = if ($cd) { $cd.ToString('MM/dd/yy') } else { '' }

        # Prefer structured 'Shop Tasks' rows for this job — match by Project name,
        # then fall back to Job# (so a project-name typo/prefix doesn't drop the task);
        # else parse the Notes cell.
        $stRows = $null
        $pk = $proj.ToLower(); $jk = $job.ToLower()
        if ($proj -ne '' -and $shopTasks.byProj.ContainsKey($pk)) { $stRows = $shopTasks.byProj[$pk] }
        elseif ($job -ne '' -and $shopTasks.byJob.ContainsKey($jk)) { $stRows = $shopTasks.byJob[$jk] }
        if ($stRows -and $stRows.Count -gt 0) {
            foreach ($r in $stRows) { $r.matched = $true }
            $t = Build-TasksFromRows $stRows
        } else {
            $t = Parse-Tasks $notes
        }

        $category = 'bay'
        if ($status -eq 'Leave' -or $bay -eq 'APL/Holidays') { $category = 'leave' }
        elseif ($bay -notin $PhysicalBays) { $category = 'pipeline' }

        [void]$jobs.Add([PSCustomObject]@{
            row = $rowNum; bay = $bay; project = $proj; client = $client; jobNum = $job
            status = $status; pm = $pm; startISO = $startISO; completionISO = $compISO
            startText = $startTxt; completionText = $compTxt; category = $category
            notesRaw = $notes
            openTasks = $t.open; openCount = $t.openCount; doneCount = $t.doneCount; salOpen = $t.salOpen; doneTasks = $t.done; tasks = $t.tasks
        })
    }

    # Surface any 'Shop Tasks' rows that matched NO job — so a mismatch is never silent.
    $stOrphans = @($shopTasks.all | Where-Object { -not $_.matched })
    $stLog = Join-Path $ScriptDir 'shoptasks-unmatched.txt'
    if ($stOrphans.Count -gt 0) {
        $stMsg = @("=== Shop Tasks rows with NO matching job  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===",
                   "These did NOT appear on the dashboard. Fix col A (Project) or col B (Job#) to match an Input job, then re-export.","")
        $stMsg += $stOrphans | ForEach-Object { "  Project='$($_.proj)'   Job#='$($_.jobNum)'   Task='$($_.task)'" }
        $stMsg | Out-File $stLog -Encoding utf8
        Write-Output "  -> WARNING: $($stOrphans.Count) Shop Tasks row(s) matched no job - see shoptasks-unmatched.txt"
    } elseif (Test-Path $stLog) {
        Remove-Item $stLog -ErrorAction SilentlyContinue
    }

    # ===== Project Tasks sheet -> long-term project portfolio ===============
    # Columns: A=Project B=Phase C=Type D=Task E=Start F=Finish G=Duration
    #          H=Assigned I=Status J=PM K=Milestone L=Comments
    $pmap = [ordered]@{}
    $projXml = Get-SheetXml $zip $wbXml $relsXml 'Project Tasks' $nsMain $nsRel $nsPkg
    if ($projXml) {
        foreach ($row in $projXml.worksheet.sheetData.row) {
            if ([int]$row.r -lt 2) { continue }
            Add-TaskRow (Get-RowCells $row) $shared $pmap $teamTasks
        }
    }

    # ===== Intake Inbox -> merge dropped project files (no Excel needed) =====
    # Team members drop a filled intake file (sheet 'Enter Here', cols A..L) in
    # the Intake Inbox; we read it straight from XML and fold it in, same as a
    # master row. Re-dropping a same-named file replaces it (overwrites on disk).
    $InboxDir = Join-Path (Split-Path -Parent $ScriptDir) 'Intake Inbox'
    if (Test-Path $InboxDir) {
        $intakeFiles = @(Get-ChildItem -Path $InboxDir -File -Filter *.xlsx -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -notlike '~$*' })
        $merged = 0
        foreach ($f in $intakeFiles) {
            try {
                $itmp = Join-Path ([System.IO.Path]::GetTempPath()) ("mra_ix_" + $f.Name)
                try { [System.IO.File]::Copy($f.FullName, $itmp, $true) } catch { $itmp = $f.FullName }
                $izip = [System.IO.Compression.ZipFile]::OpenRead($itmp)
                try {
                    $ishared = New-Object System.Collections.ArrayList
                    $iss = Read-Entry $izip 'xl/sharedStrings.xml'
                    if ($iss) { [xml]$ix = $iss; foreach ($si in $ix.sst.si) { [void]$ishared.Add([string]$si.InnerText) } }
                    [xml]$iwb  = Read-Entry $izip 'xl/workbook.xml'
                    [xml]$irel = Read-Entry $izip 'xl/_rels/workbook.xml.rels'
                    $isx = Get-SheetXml $izip $iwb $irel 'Enter Here' $nsMain $nsRel $nsPkg
                    if ($isx) {
                        foreach ($row in $isx.worksheet.sheetData.row) {
                            if ([int]$row.r -lt 2) { continue }
                            Add-TaskRow (Get-RowCells $row) $ishared $pmap $teamTasks
                        }
                        $merged++
                    }
                } finally {
                    $izip.Dispose()
                    if ($itmp -ne $f.FullName) { Remove-Item $itmp -Force -ErrorAction SilentlyContinue }
                }
            } catch {
                Write-Output "  -> intake merge skipped '$($f.Name)': $($_.Exception.Message)"
            }
        }
        if ($merged -gt 0) { Write-Output "  -> Merged $merged intake file(s) from Intake Inbox" }
    }

    foreach ($o in $pmap.Values) {
        # Overall % is the AVERAGE of each task's own % (Completed=100, partials count, rest=0) — not just done/total.
        $pct = if ($o.taskCount -gt 0) { [math]::Round($o.pctSum / $o.taskCount) } else { 0 }
        [void]$projects.Add([PSCustomObject]@{
            name      = $o.name
            pm        = $o.pm
            startISO  = if ($o.minStart)  { $o.minStart.ToString('yyyy-MM-dd') }  else { $null }
            finishISO = if ($o.maxFinish) { $o.maxFinish.ToString('yyyy-MM-dd') } else { $null }
            taskCount = $o.taskCount
            doneCount = $o.doneCount
            pct       = $pct
            milestones = @($o.milestones)
            tasks      = @($o.tasks)
        })
    }
} finally {
    $zip.Dispose()
    if ($tmp -ne $Workbook) { try { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } catch {} }
}

# --- Write payload ----------------------------------------------------------
$now = Get-Date

# --- Shared: vehicle location map (filled by Samsara below) + fleet#/place helpers ---
$fLoc = @{}
function NormFleet($s){ $t = ((([string]$s).Trim()) -split '\s+')[0]; $t = $t.Trim()
    if ($t -match '^(\d+)G$') { return ([int64]$matches[1]).ToString() }   # genset "1546G" -> base unit "1546"
    if ($t -match '^\d+$') { return ([int64]$t).ToString() }
    return $t.ToUpper() }
# Reduce a full address to "City, ST" — handles US ("…, MA, 01505") and Canada ("…, ON N8Y 1L6").
function PlaceFromAddr($addr){
    $addr = ([string]$addr).Trim(); if ($addr -eq '') { return '' }
    $parts = $addr -split ','
    for ($k=0; $k -lt $parts.Count; $k++){
        if ($parts[$k].Trim() -match '^([A-Z]{2})(?:\s+[0-9A-Za-z][0-9A-Za-z\s-]*)?$') {
            $st = $matches[1]
            $city = if ($k-1 -ge 0) { $parts[$k-1].Trim() } else { '' }
            if ($city) { return "$city, $st" } else { return $st }
        }
    }
    if ($addr.Length -gt 40) { return $addr.Substring(0,40) } else { return $addr }
}

# --- Fleetio (optional) — reads fleetio.txt: line1 = API key, line2 = Account Token ---
$fleetio = $null
$FleetioTokenFile = Join-Path $ScriptDir 'fleetio.txt'
if (Test-Path $FleetioTokenFile) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $fcfg  = Get-Content $FleetioTokenFile
        $fhead = @{ 'Authorization' = "Token $($fcfg[0].Trim())"; 'Account-Token' = $fcfg[1].Trim(); 'Accept' = 'application/json' }

        function Get-FleetioAll($path, $headers) {
            $all = New-Object System.Collections.ArrayList
            $page = 1; $totalPages = 1
            do {
                $sep = if ($path -match '\?') { '&' } else { '?' }
                $url = "https://secure.fleetio.com/api/v1/$path$sep" + "per_page=100&page=$page"
                $resp = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -Method GET -TimeoutSec 30
                $tp = $resp.Headers['X-Pagination-Total-Pages']; if ($tp -is [array]) { $tp = $tp[0] }
                if ($tp) { $totalPages = [int]$tp }
                foreach ($x in ($resp.Content | ConvertFrom-Json)) { [void]$all.Add($x) }
                $page++
            } while ($page -le $totalPages -and $page -le 25)
            return $all
        }
        function Get-FleetJob($name) { if ($name -and ([string]$name -match '\bJ\d+[A-Za-z]?\b')) { return $matches[0] } else { return '' } }
        function FleetD10($s) { if ($s) { return ([string]$s).Substring(0,10) } else { return $null } }
        # Pull the assignee name(s) off an issue/work order, whatever field Fleetio uses.
        function Get-FleetAssignees($obj) {
            $out = New-Object System.Collections.ArrayList
            foreach ($prop in @('assigned_contacts','watcher_contacts','contacts','assignees')) {
                $val = $obj.$prop
                if ($val) {
                    foreach ($c in @($val)) {
                        $nm = ''
                        if     ($c -is [string]) { $nm = $c }
                        elseif ($c.name)         { $nm = [string]$c.name }
                        elseif ($c.full_name)    { $nm = [string]$c.full_name }
                        elseif ($c.first_name -or $c.last_name) { $nm = (('{0} {1}' -f [string]$c.first_name, [string]$c.last_name)).Trim() }
                        elseif ($c.contact_name) { $nm = [string]$c.contact_name }
                        $nm = ([string]$nm).Trim()
                        if ($nm -ne '' -and -not $out.Contains($nm)) { [void]$out.Add($nm) }
                    }
                }
            }
            foreach ($prop in @('assigned_contact','contact')) {
                $c = $obj.$prop
                if ($c -and $c.name) { $nm = [string]$c.name; if (-not $out.Contains($nm)) { [void]$out.Add($nm) } }
            }
            return ,@($out)
        }
        # The person who opened the issue / issued the WO ("Reported By").
        function Get-FleetReporter($obj) {
            foreach ($p in @('reported_by_name','issued_by_name','created_by_name')) { if ($obj.$p) { return ([string]$obj.$p).Trim() } }
            foreach ($p in @('reported_by','issued_by','created_by')) { $c = $obj.$p; if ($c -and $c.name) { return ([string]$c.name).Trim() } }
            return ''
        }

        $fIssues = New-Object System.Collections.ArrayList
        foreach ($i in (Get-FleetioAll 'issues?q%5Bstate_eq%5D=open' $fhead)) {
            $pr = ''
            if ($i.labels) { try { $pr = (@($i.labels | ForEach-Object { if ($_ -is [string]) { $_ } elseif ($_.name) { $_.name } }) -join ', ') } catch {} }
            $det = ''
            if ($i.description) { $det = ([string]$i.description).Trim(); if ($det.Length -gt 600) { $det = $det.Substring(0,600) + '…' } }
            [void]$fIssues.Add([PSCustomObject]@{
                id = $i.id; num = (([string]$i.number) -replace '^#',''); summary = $(if ($i.summary) { $i.summary } else { $i.name })
                asset = $i.vehicle_name; jobNum = (Get-FleetJob $i.vehicle_name)
                priority = $pr; openedISO = (FleetD10 $i.reported_at); overdue = [bool]$i.overdue
                detail = $det; reporter = (Get-FleetReporter $i); assignees = (Get-FleetAssignees $i)
            })
        }
        $fWos = New-Object System.Collections.ArrayList
        foreach ($w in (Get-FleetioAll 'work_orders?q%5Bstate_eq%5D=active' $fhead)) {
            $woLines = ''
            if ($w.work_order_line_items) { $woLines = (@($w.work_order_line_items | ForEach-Object { $_.item_name }) | Where-Object { $_ }) -join ', ' }
            $sum = $w.description
            if (-not $sum) { $sum = $woLines }
            if (-not $sum) { $sum = "Work Order $($w.number)" }
            $woDet = $(if ($woLines -and $woLines -ne $sum) { $woLines } else { '' })
            $op = $w.issued_at; if (-not $op) { $op = $w.scheduled_at }; if (-not $op) { $op = $w.created_at }
            [void]$fWos.Add([PSCustomObject]@{
                id = $w.id; num = (([string]$w.number) -replace '^#',''); summary = $sum; asset = $w.vehicle_name
                jobNum = (Get-FleetJob $w.vehicle_name); status = $w.work_order_status_name; openedISO = (FleetD10 $op)
                detail = $woDet; reporter = (Get-FleetReporter $w); assignees = (Get-FleetAssignees $w)
            })
        }
        $fSvc = New-Object System.Collections.ArrayList
        foreach ($s in (Get-FleetioAll 'service_reminders' $fhead)) {
            $st = [string]$s.service_reminder_status_name
            if ($st -ne 'overdue' -and $st -ne 'due_soon') { continue }
            [void]$fSvc.Add([PSCustomObject]@{
                id = $s.id; service = $s.service_task_name; asset = $s.vehicle_name; jobNum = (Get-FleetJob $s.vehicle_name)
                dueISO = (FleetD10 $s.next_due_at); meterDue = $s.next_due_meter_value; status = $st
            })
        }

        # --- Fleetio vehicles roster + compliance (renewal reminders) probe ---
        # Location now comes from Samsara (below). This pulls the cursor-paginated vehicle
        # roster + the renewal reminders so we can see what compliance data Fleetio holds
        # (DOT/Reg/Ins/IFTA) for the FLEET-tab rebuild. Writes fleetio-debug.txt.
        $FleetDbg = Join-Path $ScriptDir 'fleetio-debug.txt'
        function Get-FleetioCursor($path, $headers) {
            $all = New-Object System.Collections.ArrayList; $cursor = $null; $guard = 0
            do { $guard++
                $sep = if ($path -match '\?') { '&' } else { '?' }
                $url = "https://secure.fleetio.com/api/v1/$path$sep" + "per_page=100"
                if ($cursor) { $url += "&start_cursor=$([uri]::EscapeDataString([string]$cursor))" }
                $resp = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -Method GET -TimeoutSec 30
                $obj = $resp.Content | ConvertFrom-Json
                if ($null -ne $obj.records) { foreach ($x in $obj.records) { [void]$all.Add($x) }; $cursor = $obj.next_cursor }
                else { foreach ($x in @($obj)) { [void]$all.Add($x) }; $cursor = $null }   # tolerate a bare array
            } while ($cursor -and $guard -lt 25)
            return $all
        }
        $fleetRoster = @()
        try {
            "=== Fleetio roster/compliance probe  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File $FleetDbg -Encoding utf8
            $veh = @(Get-FleetioCursor 'vehicles' $fhead)
            "vehicles fetched: $($veh.Count)" | Out-File $FleetDbg -Append -Encoding utf8
            "with renewal reminders: $((@($veh | Where-Object { $_.vehicle_renewal_reminders_count -gt 0 })).Count)" | Out-File $FleetDbg -Append -Encoding utf8

            # Renewal TYPE id -> name, so each reminder can be labeled (DOT / Reg / Ins / IFTA / ...).
            $rtName = @{}
            try { foreach ($rt in @(Get-FleetioCursor 'vehicle_renewal_types' $fhead)) { if ($null -ne $rt.id) { $rtName[[string]$rt.id] = [string]$rt.name } } } catch {}
            "renewal types: $((@($rtName.Values | Sort-Object -Unique)) -join ' | ')" | Out-File $FleetDbg -Append -Encoding utf8

            # All renewal reminders -> grouped by vehicle id as [{ ty, due, s }].
            $remByVeh = @{}; $typeCount = @{}
            foreach ($ep in @('vehicle_renewal_reminders','renewal_reminders')) {
                try {
                    $rr = @(Get-FleetioCursor $ep $fhead)
                    if ($rr.Count -gt 0) {
                        "[$ep] fetched: $($rr.Count)" | Out-File $FleetDbg -Append -Encoding utf8
                        foreach ($r in $rr) {
                            $vid = [string]$r.vehicle_id; if ($vid -eq '') { continue }
                            $tn  = $rtName[[string]$r.vehicle_renewal_type_id]; if (-not $tn) { $tn = "type $($r.vehicle_renewal_type_id)" }
                            if (-not $remByVeh.ContainsKey($vid)) { $remByVeh[$vid] = New-Object System.Collections.ArrayList }
                            [void]$remByVeh[$vid].Add([PSCustomObject]@{ ty = $tn; due = (FleetD10 $r.next_due_at); s = [string]$r.vehicle_renewal_reminder_status })
                            if ($typeCount.ContainsKey($tn)) { $typeCount[$tn]++ } else { $typeCount[$tn] = 1 }
                        }
                        break
                    }
                } catch { "[$ep] error: $($_.Exception.Message)" | Out-File $FleetDbg -Append -Encoding utf8 }
            }
            ("reminders by type: " + ((@($typeCount.GetEnumerator() | Sort-Object Name | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value })) -join ' | ')) | Out-File $FleetDbg -Append -Encoding utf8

            # Build the roster: one entry per Fleetio vehicle (tour = Fleetio group; the dashboard
            # falls back to its built-in list when this is blank). Keyed by fleet # via NormFleet.
            foreach ($v in $veh) {
                $key = NormFleet $v.name; if ($key -eq '') { continue }
                $comp = @(); if ($remByVeh.ContainsKey([string]$v.id)) { $comp = @($remByVeh[[string]$v.id]) }
                $fleetRoster += [PSCustomObject]@{
                    f = $key; nm = [string]$v.name; t = [string]$v.vehicle_type_name
                    y = $(if ($v.year) { [string]$v.year } else { '' })
                    mk = (('{0} {1}' -f [string]$v.make, [string]$v.model)).Trim()
                    tour = [string]$v.group_name; stat = [string]$v.vehicle_status_name
                    mi = $(if ($null -ne $v.primary_meter_value) { [string]$v.primary_meter_value } else { '' }); mu = [string]$v.primary_meter_unit
                    oi = [int]$v.issues_count; ow = [int]$v.work_orders_count; os = [int]$v.service_reminders_count
                    plate = [string]$v.license_plate; rs = [string]$v.registration_state; vin = [string]$v.vin
                    comp = $comp
                }
            }
            "roster built: $($fleetRoster.Count)" | Out-File $FleetDbg -Append -Encoding utf8
            ($veh | Select-Object -First 1 -Property id,name,vehicle_type_name,vehicle_status_name,year,make,model,license_plate,registration_state,vin,primary_meter_value,primary_meter_unit,group_name,issues_count,work_orders_count,service_reminders_count,vehicle_renewal_reminders_count | ConvertTo-Json -Depth 4) | Out-File $FleetDbg -Append -Encoding utf8
            Write-Output "  -> Fleetio: $($veh.Count) vehicles; roster built ($($fleetRoster.Count)) -> fleetio-debug.txt"
        } catch { "FATAL: $($_.Exception.Message)" | Out-File $FleetDbg -Append -Encoding utf8; Write-Output "  -> Fleetio roster build failed: $($_.Exception.Message)" }

        $fleetio = [PSCustomObject]@{
            generatedText = $now.ToString('ddd MMM d, yyyy  h:mm tt')
            issues = @($fIssues); workOrders = @($fWos); service = @($fSvc); locations = $fLoc; fleet = @($fleetRoster)
        }
        $issAssigned = (@($fIssues | Where-Object { @($_.assignees).Count -gt 0 })).Count
        Write-Output "  -> Fleetio: $($fIssues.Count) issues ($issAssigned with assignees), $($fWos.Count) work orders, $($fSvc.Count) service due/overdue"
    } catch {
        Write-Output "  -> Fleetio fetch failed: $($_.Exception.Message)"
    }
}

# --- Samsara (optional) — LIVE GPS location, reads samsara.txt: line1 = API token ---
# Samsara is the upstream GPS source (Fleetio only mirrors it nightly). One paginated call
# gets every tracked vehicle AND trailer's current location + a reverse-geocoded address. Fills
# the shared $fLoc (keyed by fleet #), which $fleetio.locations references. Matches by the leading
# token of the Samsara name; keeps the freshest fix per unit. Writes samsara-debug.txt.
$SamsaraTokenFile = Join-Path $ScriptDir 'samsara.txt'
if (Test-Path $SamsaraTokenFile) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $stoken = (Get-Content $SamsaraTokenFile | Select-Object -First 1).Trim()
        $shead  = @{ 'Authorization' = "Bearer $stoken"; 'Accept' = 'application/json' }
        $SamDbg = Join-Path $ScriptDir 'samsara-debug.txt'
        "=== Samsara GPS  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File $SamDbg -Encoding utf8
        # Pull BOTH vehicles (trucks/tractors) AND trailers — Samsara tracks trailers on a
        # separate endpoint, so trailers (e.g. #54) were getting no location before.
        $samV = 0; $samT = 0
        foreach ($ep in @('vehicles','trailers')) {
            $cursor = $null; $guard = 0; $dumped = $false; $hasNext = $false; $n = 0
            do {
                $guard++
                $url = "https://api.samsara.com/fleet/$ep/stats?types=gps"
                if ($cursor) { $url += "&after=$([uri]::EscapeDataString([string]$cursor))" }
                $resp = Invoke-WebRequest -Uri $url -Headers $shead -UseBasicParsing -Method GET -TimeoutSec 30
                $obj  = $resp.Content | ConvertFrom-Json
                if (-not $dumped) { $dumped = $true; "--- $ep (first 3) ---" | Out-File $SamDbg -Append -Encoding utf8; ($obj.data | Select-Object -First 3 | ConvertTo-Json -Depth 6) | Out-File $SamDbg -Append -Encoding utf8 }
                foreach ($v in @($obj.data)) {
                    $key = NormFleet $v.name; if ($key -eq '') { continue }
                    $g = $v.gps; if (-not $g) { continue }
                    $addr = ''
                    if ($g.reverseGeo -and $g.reverseGeo.formattedLocation) { $addr = [string]$g.reverseGeo.formattedLocation }
                    $place = PlaceFromAddr $addr
                    if ($place -eq '' -and $g.latitude -and $g.longitude) { $place = ("{0:N3}, {1:N3}" -f [double]$g.latitude, [double]$g.longitude) }
                    if ($place -eq '') { continue }
                    $atISO = if ($g.time) { [string]$g.time } else { $null }
                    $yard = ''; if ($g.address -and $g.address.name) { $yard = [string]$g.address.name }
                    # Some names appear more than once (and a few report stale fixes) — keep the FRESHEST.
                    $ex = $fLoc[$key]
                    if ($ex -and $ex.atISO -and $atISO -and ([string]$atISO -lt [string]$ex.atISO)) { continue }
                    $lat = $null; $lng = $null
                    if ($null -ne $g.latitude -and $null -ne $g.longitude) { $lat = [math]::Round([double]$g.latitude,5); $lng = [math]::Round([double]$g.longitude,5) }
                    $fLoc[$key] = [PSCustomObject]@{ place = $place; full = $addr; atISO = $atISO; yard = $yard; lat = $lat; lng = $lng }
                    $n++
                }
                $cursor  = $obj.pagination.endCursor
                $hasNext = [bool]$obj.pagination.hasNextPage
            } while ($hasNext -and $guard -lt 20)
            if ($ep -eq 'vehicles') { $samV = $n } else { $samT = $n }
            "samsara $ep set: $n" | Out-File $SamDbg -Append -Encoding utf8
        }
        $samN = $fLoc.Count
        "samsara TOTAL located keys: $samN  (vehicles $samV, trailers $samT)" | Out-File $SamDbg -Append -Encoding utf8
        Write-Output "  -> Samsara: located $samN unit(s) [veh $samV, trl $samT]; debug -> samsara-debug.txt"
        if ($null -eq $fleetio) { $fleetio = [PSCustomObject]@{ generatedText = $now.ToString('ddd MMM d, yyyy  h:mm tt'); issues=@(); workOrders=@(); service=@(); locations=$fLoc; fleet=@() } }
    } catch { Write-Output "  -> Samsara fetch failed: $($_.Exception.Message)" }
}

# --- Logistics calendars -> MRA trailer logistics ---------------------------
# For each of this year's logistics calendars (OneDrive-synced), build a clean
# timeline by reading each month from ITS OWN tab (the tabs disagree, so the
# union is noisy). The date for a cell is the date cell directly ABOVE it.
#   * OUT now + a future MRA/Madison Heights date  -> "arriving" (KEY for bay
#     planning) - reported with that arrival date and where it is now.
#   * AT MRA now  -> "at" - reported with arrival date + next move out.
function Get-MraStatus($dir, $today, $nsMain, $nsRel, $nsPkg) {
    $out = New-Object System.Collections.ArrayList
    if (-not (Test-Path $dir)) { Write-Output "  -> MRA at-base: folder not found ($dir)"; return @() }
    $monthTabs = @('JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC')
    $isMra = { param($t) $t -match '(?i)\bMRA\b|madison heights' }
    $files = @(Get-ChildItem -Path $dir -File -Filter *.xlsx -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -notlike '~$*' -and $_.Name -notmatch '(?i)blank' })
    $nFiles = 0
    foreach ($f in $files) {
        $job = $f.BaseName
        if ($f.BaseName -match '^\s*\d{4}\s+(.*?)\s+Logistics\s+Calendar') { $job = $matches[1].Trim() }
        if ([string]::IsNullOrWhiteSpace($job)) { $job = $f.BaseName }   # never blank
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('mra_cal_' + $f.Name)
        $zip = $null; $usedTmp = $false
        try {
            try { [IO.File]::Copy($f.FullName, $tmp, $true); $path = $tmp; $usedTmp = $true } catch { $path = $f.FullName }
            $zip = [System.IO.Compression.ZipFile]::OpenRead($path)
            $shared = New-Object System.Collections.ArrayList
            $ssTxt = Read-Entry $zip 'xl/sharedStrings.xml'
            if ($ssTxt) { [xml]$ss = $ssTxt; foreach ($si in $ss.sst.si) { [void]$shared.Add([string]$si.InnerText) } }
            [xml]$wbXml   = Read-Entry $zip 'xl/workbook.xml'
            [xml]$relsXml = Read-Entry $zip 'xl/_rels/workbook.xml.rels'
            $tl = @{}   # DateTime -> location text  (clean, per-month-authoritative)
            for ($i = 0; $i -lt 12; $i++) {
                $sx = Get-SheetXml $zip $wbXml $relsXml $monthTabs[$i] $nsMain $nsRel $nsPkg
                if (-not $sx) { continue }
                $monthNum = $i + 1
                $map = @{}
                foreach ($row in $sx.worksheet.sheetData.row) {
                    foreach ($c in $row.c) { if ($c.r) { $map[[string]$c.r] = $c } }
                }
                foreach ($ref in @($map.Keys)) {
                    $c = $map[$ref]
                    if ($c.t -notin @('s','inlineStr','str')) { continue }
                    $txt = (([string](Resolve-Cell $c $shared)) -replace '\s+', ' ').Trim()
                    if ($txt -eq '') { continue }
                    if ($txt -match '(?i)^\s*[\d,]+\s*miles?\b' -or $txt -match '(?i)load-?(out|in) window' -or
                        $txt -eq 'Notes:' -or $txt -match '(?i)^\s*\d{1,2}(:\d\d)?\s*(am|pm)?\s*-\s*\d') { continue }
                    $mm = [regex]::Match($ref, '^([A-Z]+)(\d+)$'); if (-not $mm.Success) { continue }
                    $rn = [int]$mm.Groups[2].Value; if ($rn -le 1) { continue }
                    $d = Get-CellDate $map[($mm.Groups[1].Value + ($rn - 1))]
                    if (-not $d -or $d.Year -ne $today.Year -or $d.Month -ne $monthNum) { continue }
                    if (-not $tl.ContainsKey($d) -or $txt.Length -gt $tl[$d].Length) { $tl[$d] = $txt }
                }
            }
            if ($tl.Count -gt 0) {
                $dates = @($tl.Keys | Sort-Object)
                $cur = $null
                foreach ($d in $dates) { if ($d.Date -le $today.Date) { $cur = $d } }
                if ($cur -and (& $isMra $tl[$cur])) {
                    # parked at MRA now -> arrival run start + next departure
                    $idx = [array]::IndexOf($dates, $cur); $arr = $cur
                    while ($idx - 1 -ge 0 -and (& $isMra $tl[$dates[$idx-1]])) { $idx--; $arr = $dates[$idx] }
                    $nxt = $null
                    foreach ($d in $dates) { if ($d.Date -gt $today.Date) { $nxt = $d; break } }
                    [void]$out.Add([PSCustomObject]@{
                        job = $job; type = 'at'
                        sinceISO = $arr.ToString('yyyy-MM-dd')
                        nextISO  = $(if ($nxt) { $nxt.ToString('yyyy-MM-dd') } else { $null })
                        nextText = $(if ($nxt) { $tl[$nxt] } else { '' })
                    })
                } else {
                    # currently out -> soonest FUTURE arrival back at MRA (bay planning)
                    $arrive = $null
                    foreach ($d in $dates) { if ($d.Date -gt $today.Date -and (& $isMra $tl[$d])) { $arrive = $d; break } }
                    if ($arrive) {
                        [void]$out.Add([PSCustomObject]@{
                            job = $job; type = 'arriving'
                            arrivingISO = $arrive.ToString('yyyy-MM-dd')
                            curText = $(if ($cur) { $tl[$cur] } else { '' })
                        })
                    }
                }
            }
            $nFiles++
        } catch {
            Write-Output "  -> MRA at-base: skip '$($f.Name)': $($_.Exception.Message)"
        } finally {
            if ($zip) { $zip.Dispose() }
            if ($usedTmp -and (Test-Path $tmp)) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
        }
    }
    $sorted = @($out | Sort-Object @{e={ if ($_.arrivingISO) { $_.arrivingISO } elseif ($_.nextISO) { $_.nextISO } else { '9999-99-99' } }}, job)
    $nArr = (@($sorted | Where-Object { $_.type -eq 'arriving' })).Count
    $nAt  = (@($sorted | Where-Object { $_.type -eq 'at' })).Count
    Write-Output "  -> MRA logistics: scanned $nFiles calendars, $nArr arriving back, $nAt at MRA now."
    foreach ($r in $sorted) {
        if ($r.type -eq 'arriving') { Write-Output "       arriving $($r.arrivingISO): $($r.job)" }
        else                        { Write-Output "       at MRA since $($r.sinceISO): $($r.job)" }
    }
    return ,$sorted
}

$CalendarsDir = Join-Path $env:USERPROFILE ("OneDrive - MRA\MRA Files's files - nobackup\{0} Logistics Calendars" -f $now.Year)
$mraStatus = @()
try { $mraStatus = Get-MraStatus $CalendarsDir $now $nsMain $nsRel $nsPkg } catch { Write-Output "  -> MRA logistics failed: $($_.Exception.Message)" }

$payload = [PSCustomObject]@{
    generatedAt   = $now.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')   # UTC; the dashboard renders it in each viewer's local timezone
    generatedText = $now.ToString('ddd MMM d, yyyy  h:mm tt')
    todayISO      = $now.ToString('yyyy-MM-dd')
    physicalBays  = $PhysicalBays
    jobs          = @($jobs)
    projects      = @($projects)
    teamTasks     = @($teamTasks)
    fleetio       = $fleetio
    mraStatus     = @($mraStatus)
    users         = @($users)
}
$json = $payload | ConvertTo-Json -Depth 8
$content = "// Auto-generated by Export-Data.ps1 - do not edit by hand`r`nwindow.MRA_DATA = $json;"
Set-Content -Path $OutFile -Value $content -Encoding UTF8

Write-Output "Wrote $($jobs.Count) jobs and $($projects.Count) projects to data.js at $($now.ToString('h:mm:ss tt'))"

# --- Push to Azure Static Site -----------------------------------------------
$AzureStorageAccount = 'mrashopdash'
# Locate az: prefer the known install path, otherwise fall back to whatever
# 'az' is on PATH (handles installs under Program Files (x86) or elsewhere).
$azExe = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
if (-not (Test-Path $azExe)) {
    $azCmd = Get-Command az -ErrorAction SilentlyContinue
    if ($azCmd) { $azExe = $azCmd.Source }
}
if (Test-Path $azExe) {
    $env:AZURE_CORE_NO_COLOR = 'true'
    $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & $azExe storage blob upload `
        --account-name $AzureStorageAccount `
        --container-name '$web' `
        --name 'data.js' `
        --file $OutFile `
        --content-type 'application/javascript' `
        --overwrite `
        --auth-mode key `
        --only-show-errors 2>$null | Out-Null
    $code = $LASTEXITCODE
    # Employee-of-the-Month photo: push eotm.png / eotm.jpg if present in this folder
    # (wall-view feature). Swap monthly — drop a new eotm.png here and re-export.
    foreach ($img in @(@{f='eotm.png'; ct='image/png'}, @{f='eotm.jpg'; ct='image/jpeg'})) {
        $imgPath = Join-Path $ScriptDir $img.f
        if (Test-Path $imgPath) {
            & $azExe storage blob upload `
                --account-name $AzureStorageAccount --container-name '$web' `
                --name $img.f --file $imgPath --content-type $img.ct `
                --overwrite --auth-mode key --only-show-errors 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Output "  -> Pushed $($img.f) to Azure" }
        }
    }
    $ErrorActionPreference = $saved
    if ($code -eq 0) {
        Write-Output "  -> Pushed data.js to Azure ($AzureStorageAccount)"
    } else {
        Write-Output "  -> Azure push failed (exit code $code)"
    }
    Remove-Item Env:\AZURE_CORE_NO_COLOR -ErrorAction SilentlyContinue
} else {
    Write-Output "  -> Azure push skipped (az CLI not found)"
}
