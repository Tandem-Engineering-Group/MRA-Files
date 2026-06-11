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
    $doneCount = 0; $salOpen = 0
    if ($null -ne $text -and $text.Trim() -ne '') {
        foreach ($lnRaw in ($text -split "`r?`n")) {
            $ln = $lnRaw.Trim()
            if ($ln -eq '') { continue }
            if ($ln -match '^[xX]\s') { $doneCount++ }
            elseif ($ln -match '^\d+\s*[\.\)\-]') {
                [void]$open.Add($ln)
                if ($ln -match '(?i)\bsal\b') { $salOpen++ }
            }
        }
    }
    return @{ open = @($open); openCount = $open.Count; doneCount = $doneCount; salOpen = $salOpen }
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

        $t = Parse-Tasks $notes

        $category = 'bay'
        if ($status -eq 'Leave' -or $bay -eq 'APL/Holidays') { $category = 'leave' }
        elseif ($bay -notin $PhysicalBays) { $category = 'pipeline' }

        [void]$jobs.Add([PSCustomObject]@{
            row = $rowNum; bay = $bay; project = $proj; client = $client; jobNum = $job
            status = $status; pm = $pm; startISO = $startISO; completionISO = $compISO
            startText = $startTxt; completionText = $compTxt; category = $category
            openTasks = $t.open; openCount = $t.openCount; doneCount = $t.doneCount; salOpen = $t.salOpen
        })
    }

    # ===== Project Tasks sheet -> long-term project portfolio ===============
    # Columns: A=Project B=Phase C=Type D=Task E=Start F=Finish G=Duration
    #          H=Assigned I=Status J=PM K=Milestone L=Comments
    $projXml = Get-SheetXml $zip $wbXml $relsXml 'Project Tasks' $nsMain $nsRel $nsPkg
    if ($projXml) {
        $pmap = [ordered]@{}
        foreach ($row in $projXml.worksheet.sheetData.row) {
            if ([int]$row.r -lt 2) { continue }
            $pc = Get-RowCells $row
            $name = ([string](Resolve-Cell $pc['A'] $shared)).Trim()
            if ($name -eq '') { continue }

            $pStatus = ([string](Resolve-Cell $pc['I'] $shared)).Trim()
            $pPM     = ([string](Resolve-Cell $pc['J'] $shared)).Trim()
            $pMile   = ([string](Resolve-Cell $pc['K'] $shared)).Trim()
            $pTask   = ([string](Resolve-Cell $pc['D'] $shared)).Trim()
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
                    name = $pTask; dateISO = $md.ToString('yyyy-MM-dd') }) }
            }

            # Per-person open task -> Team Capacity panel (assignee in col H)
            if ($pAssigned -ne '' -and $pStatus -ne 'Completed') {
                $dueISO = if ($pfd) { $pfd.ToString('yyyy-MM-dd') }
                          elseif ($psd) { $psd.ToString('yyyy-MM-dd') } else { $null }
                [void]$teamTasks.Add([PSCustomObject]@{
                    assignee = $pAssigned; project = $name; task = $pTask
                    dueISO = $dueISO; status = $pStatus
                })
            }
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
    }
} finally {
    $zip.Dispose()
    if ($tmp -ne $Workbook) { try { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } catch {} }
}

# --- Write payload ----------------------------------------------------------
$now = Get-Date
$payload = [PSCustomObject]@{
    generatedAt   = $now.ToString('yyyy-MM-ddTHH:mm:ss')
    generatedText = $now.ToString('ddd MMM d, yyyy  h:mm tt')
    todayISO      = $now.ToString('yyyy-MM-dd')
    physicalBays  = $PhysicalBays
    jobs          = @($jobs)
    projects      = @($projects)
    teamTasks     = @($teamTasks)
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
