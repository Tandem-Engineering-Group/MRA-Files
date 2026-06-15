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

$PhysicalBays = @('Bay 2 Front','Bay 2 Back','Bay 3 Front','Bay 3 Back',
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
    $map = @{}
    $sx = Get-SheetXml $zip $wbXml $relsXml 'Shop Tasks' $nsMain $nsRel $nsPkg
    if (-not $sx) { return $map }
    foreach ($row in $sx.worksheet.sheetData.row) {
        if ([int]$row.r -lt 2) { continue }
        $c = Get-RowCells $row
        $key  = ([string](Resolve-Cell $c['A'] $shared)).Trim()   # Project (match key)
        $job  = ([string](Resolve-Cell $c['B'] $shared)).Trim()   # Job # (info only)
        $task = ([string](Resolve-Cell $c['D'] $shared)).Trim()
        if ($key -eq '' -or $task -eq '') { continue }
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
        }
        if (-not $map.ContainsKey($key)) { $map[$key] = New-Object System.Collections.ArrayList }
        [void]$map[$key].Add($obj)
    }
    return $map
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
        [void]$tasks.Add([PSCustomObject]@{ t = [string]$r.task; who = $who; op = $r.opened; cl = $r.closed; st = [string]$r.status; done = [bool]$r.done })
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
    $pStatus   = ([string](Resolve-Cell $pc['I'] $shared)).Trim()
    $pPM       = ([string](Resolve-Cell $pc['J'] $shared)).Trim()
    $pMile     = ([string](Resolve-Cell $pc['K'] $shared)).Trim()
    $pTask     = ([string](Resolve-Cell $pc['D'] $shared)).Trim()
    $pAssigned = ([string](Resolve-Cell $pc['H'] $shared)).Trim()
    $psd = Get-CellDate $pc['E']
    $pfd = Get-CellDate $pc['F']

    if (-not $pmap.Contains($name)) {
        $pmap[$name] = [PSCustomObject]@{
            name = $name; pm = ''; minStart = $null; maxFinish = $null
            taskCount = 0; doneCount = 0
            milestones = (New-Object System.Collections.ArrayList)
        }
    }
    $o = $pmap[$name]
    $o.taskCount++
    if ($pStatus -eq 'Completed') { $o.doneCount++ }
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
}

# --- Copy workbook to temp (avoids any file lock) and open as zip ------------
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("mra_" + [System.IO.Path]::GetFileName($Workbook))
try { [System.IO.File]::Copy($Workbook, $tmp, $true) }
catch { $tmp = $Workbook }   # fall back to reading in place

$zip = [System.IO.Compression.ZipFile]::OpenRead($tmp)
$jobs = New-Object System.Collections.ArrayList
$projects = New-Object System.Collections.ArrayList
$teamTasks = New-Object System.Collections.ArrayList
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

        # Prefer structured 'Shop Tasks' rows for this job (matched by Project,
        # since Job#s aren't unique); else parse the Notes cell.
        if ($proj -ne '' -and $shopTasks.ContainsKey($proj) -and $shopTasks[$proj].Count -gt 0) {
            $t = Build-TasksFromRows $shopTasks[$proj]
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
        $pct = if ($o.taskCount -gt 0) { [math]::Round($o.doneCount * 100.0 / $o.taskCount) } else { 0 }
        [void]$projects.Add([PSCustomObject]@{
            name      = $o.name
            pm        = $o.pm
            startISO  = if ($o.minStart)  { $o.minStart.ToString('yyyy-MM-dd') }  else { $null }
            finishISO = if ($o.maxFinish) { $o.maxFinish.ToString('yyyy-MM-dd') } else { $null }
            taskCount = $o.taskCount
            doneCount = $o.doneCount
            pct       = $pct
            milestones = @($o.milestones)
        })
    }
} finally {
    $zip.Dispose()
    if ($tmp -ne $Workbook) { try { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } catch {} }
}

# --- Write payload ----------------------------------------------------------
$now = Get-Date

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
                num = (([string]$i.number) -replace '^#',''); summary = $(if ($i.summary) { $i.summary } else { $i.name })
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
                num = (([string]$w.number) -replace '^#',''); summary = $sum; asset = $w.vehicle_name
                jobNum = (Get-FleetJob $w.vehicle_name); status = $w.work_order_status_name; openedISO = (FleetD10 $op)
                detail = $woDet; reporter = (Get-FleetReporter $w); assignees = (Get-FleetAssignees $w)
            })
        }
        $fSvc = New-Object System.Collections.ArrayList
        foreach ($s in (Get-FleetioAll 'service_reminders' $fhead)) {
            $st = [string]$s.service_reminder_status_name
            if ($st -ne 'overdue' -and $st -ne 'due_soon') { continue }
            [void]$fSvc.Add([PSCustomObject]@{
                service = $s.service_task_name; asset = $s.vehicle_name; jobNum = (Get-FleetJob $s.vehicle_name)
                dueISO = (FleetD10 $s.next_due_at); meterDue = $s.next_due_meter_value; status = $st
            })
        }
        $fleetio = [PSCustomObject]@{
            generatedText = $now.ToString('ddd MMM d, yyyy  h:mm tt')
            issues = @($fIssues); workOrders = @($fWos); service = @($fSvc)
        }
        $issAssigned = (@($fIssues | Where-Object { @($_.assignees).Count -gt 0 })).Count
        Write-Output "  -> Fleetio: $($fIssues.Count) issues ($issAssigned with assignees), $($fWos.Count) work orders, $($fSvc.Count) service due/overdue"
    } catch {
        Write-Output "  -> Fleetio fetch failed: $($_.Exception.Message)"
    }
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
    generatedAt   = $now.ToString('yyyy-MM-ddTHH:mm:ss')
    generatedText = $now.ToString('ddd MMM d, yyyy  h:mm tt')
    todayISO      = $now.ToString('yyyy-MM-dd')
    physicalBays  = $PhysicalBays
    jobs          = @($jobs)
    projects      = @($projects)
    teamTasks     = @($teamTasks)
    fleetio       = $fleetio
    mraStatus     = @($mraStatus)
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
