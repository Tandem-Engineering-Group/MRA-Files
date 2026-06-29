# =============================================================================
#  MRA - Merge-Schedule.ps1   (ONE-TIME Smartsheet -> Input reconcile)
#
#  Updates the master workbook's "Input" sheet from the Smartsheet snapshot
#  (transcribed below). Rules:
#    * UPDATE Bay / PM / Start / Finish on rows that already exist, ONLY when
#      the new value is concrete (blank / TBD / N/A are ignored -> never wipes).
#    * Pod 86 Job# is set to "J1558 / J1014" (both kept for you to reconcile).
#    * ADD the genuinely-new rows (Tractor 7220, WFCU).
#    * NEVER deletes a row, NEVER touches Status (G) or your task notes (H),
#      NEVER changes the Project/task-name text (B) on existing rows.
#
#  SAFE BY DEFAULT: running it just PREVIEWS (writes nothing). Add -Apply to
#  actually write. -Apply makes a timestamped backup of the workbook first.
#
#  Reading is done from the file XML (works even if open in Excel); writing
#  uses Excel COM with the same date trick as Import-Intake.ps1.
# =============================================================================
param([switch]$Apply)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Master    = Join-Path (Split-Path -Parent $ScriptDir) 'MRA_Shop_Board_v6_9_7.xlsx'
$Sheet     = 'Input'
$nsMain='http://schemas.openxmlformats.org/spreadsheetml/2006/main'
$nsRel ='http://schemas.openxmlformats.org/officeDocument/2006/relationships'
$nsPkg ='http://schemas.openxmlformats.org/package/2006/relationships'
Add-Type -AssemblyName System.IO.Compression.FileSystem

# ---- XML readers (same approach as Import-Intake.ps1) ----------------------
function Read-Entry($zip,$name){ $e=$zip.Entries|?{$_.FullName -eq $name}; if(-not $e){return $null}
    $sr=New-Object IO.StreamReader($e.Open(),[Text.Encoding]::UTF8); $t=$sr.ReadToEnd(); $sr.Close(); return $t }
function Resolve-Cell($c,$sh){ if($null -eq $c){return $null}
    switch($c.t){ 's'{[string]$sh[[int]$c.v]} 'inlineStr'{[string]$c.InnerText} 'str'{[string]$c.v} default{[string]$c.v} } }
function Get-SheetXml($zip,$wb,$rels,$name){
    $nm=New-Object Xml.XmlNamespaceManager($wb.NameTable); $nm.AddNamespace('d',$nsMain); $nm.AddNamespace('r',$nsRel)
    $sn=$wb.SelectSingleNode("//d:sheets/d:sheet[@name='$name']",$nm); if(-not $sn){return $null}
    $rid=$sn.GetAttribute('id',$nsRel)
    $n2=New-Object Xml.XmlNamespaceManager($rels.NameTable); $n2.AddNamespace('p',$nsPkg)
    $rel=$rels.SelectSingleNode("//p:Relationship[@Id='$rid']",$n2)
    $tg=$rel.GetAttribute('Target') -replace '^/xl/','' -replace '^/',''; if($tg -notmatch '^xl/'){$tg="xl/$tg"}
    return [xml](Read-Entry $zip $tg) }
function Get-RowCells($row){ $h=@{}; foreach($c in $row.c){ if($null -eq $c.r){continue}
    $h[([regex]::Match([string]$c.r,'^[A-Z]+')).Value]=$c }; return $h }
function Coerce-Date($raw){ if($null -eq $raw -or "$raw".Trim() -eq ''){return $null}
    $d=0.0; if([double]::TryParse("$raw",[ref]$d)){ try{return [datetime]::FromOADate($d)}catch{return $null} }
    $dt=[datetime]::MinValue; if([datetime]::TryParse("$raw",[ref]$dt)){return $dt}; return $null }
function Open-Zip($p){ $tmp=Join-Path ([IO.Path]::GetTempPath()) ("mra_mrg_"+[IO.Path]::GetFileName($p))
    try{[IO.File]::Copy($p,$tmp,$true)}catch{$tmp=$p}
    return @{zip=[IO.Compression.ZipFile]::OpenRead($tmp); tmp=$tmp; isCopy=($tmp -ne $p)} }
function Close-Zip($z){ if($z.zip){$z.zip.Dispose()}; if($z.isCopy -and (Test-Path $z.tmp)){Remove-Item $z.tmp -Force -EA SilentlyContinue} }

# Normalize for matching: fold all unicode dashes to '-', collapse spaces, lower.
function Norm($s){ if($null -eq $s){return ''}; $t=([string]$s) -replace '[\u2010-\u2015\u2212]','-'; $t=$t -replace '\s+',' '; return $t.Trim().ToLowerInvariant() }
function Concrete($v){ $t=("$v").Trim(); return -not ($t -eq '' -or $t -eq 'TBD' -or $t -eq 'N/A' -or $t -eq 'NA' -or $t -eq '-') }
function ToDate($iso){ if(("$iso").Trim() -eq ''){return $null}; return [datetime]::ParseExact($iso,'yyyy-MM-dd',$null) }

# ===== Smartsheet snapshot (transcribed 2026-06-12) ==========================
#  key  = existing Input "Project" text to match (hyphens; en-dashes folded by Norm)
#  job  = Smartsheet Job# (fallback match + flags # differences)
#  bay/pm/s/f = desired values ('' or TBD/N/A => leave existing alone)
#  setjob = force a Job# value (Pod 86 only, to keep both numbers)
$PLAN = @(
 @{t='Post ADLM Inventory Storage'; key='Post ADLM Inventory Storage'; job='J1391'; bay='Bay 2 Front'; pm='Cindy Irland'; s='2026-06-22'; f='2026-07-17'}
 @{t='Pre ADLM Inventory Storage';  key='Pre ADLM Inventory Storage';  job='J1391'; bay='Bay 2 Front'; pm='Cindy Irland'; s='2026-08-05'; f='2026-08-21'}
 @{t='Tractor 7220 - Wrap Removal'; new=$true; bay='Bay 3 Front'; client='MRA Internal'; job='J1014'; pm=''; s='2026-06-15'; f='2026-06-19'}
 @{t='Washtenaw County';            key='Washtenaw County';            job='J1543'; bay='Bay 3 Back'; pm='Megan Fraser'; s='2026-02-24'; f='2026-06-15'}
 @{t='Medtronic - Buildout';        key='Medtronic - Buildout';        job='J1553'; bay='Bay 3 Back'; pm='Megan Fraser'; s='2026-06-15'; f='2026-11-13'}
 @{t='Pod 86 - Door Swap (Cisco)';  key='Pod 86 - (Cisco)';            job='J1014'; bay='Bay 4 Front'; pm='Steve Calus'; setjob='J1558 / J1014'; s='2026-06-02'; f='2026-06-12'}
 @{t='Oakland Schools - Revamp';    key='Oakland Schools - Revamp';    job='J1420'; bay='Bay 4 Back'; pm='TBD'; s='2026-06-22'; f='2026-08-21'}
 @{t='Tim McGraw - Trailer Relaunch';key='Tim McGraw - Trailer Relaunch';job='J1421'; bay='Bay 4 Back'; pm='Luciana Giglio'; s='2026-05-11'; f='2026-08-21'}
 @{t='Medtronic - Vendor Setup';    key='Medtronic - Vendor Setup';    job='J1553'; bay='Bay 4 Back'; pm='Megan Fraser'; s='2026-08-31'; f='2026-10-02'}
 @{t='Siemens DI - Pedestals/Maintenance'; key='Siemens DI - Pedestals/Maint.'; job='J1524'; bay='Bay 5 Front'; pm='Cindy Irland'; s='2026-07-06'; f='2026-07-10'}
 @{t='MOTT - Roof Repairs';         key='MOTT - Roof Repairs';         job='J1428'; bay='Bay 5 Front'; pm='Heather Maloney'; s='2026-06-15'; f='2026-06-26'}
 @{t='Travis Mathew - Maintenance Items'; key='Travis Mathew - Maint. Items'; job='J1387'; bay='Bay 5 Back'; pm='Frank Mancina'; s='2026-06-05'; f='2026-06-12'}
 @{t='Generator Painting & Mount - 6821 Tractor'; key='Generator Painting & Mount - 6821'; job='J1420'; bay='Bay 5 Back'; pm='Luciana Giglio'; s=''; f=''}
 @{t='Medtronic';                   key='Medtronic';                   job='J1553'; bay='Parking Lot'; pm='Megan Fraser'; s='2026-06-02'; f='2026-06-12'}
 @{t='SWC FL1 (1545) - Maintenance';key='SWC FL1 (1545) - Maintenance';job='J1514'; bay='Parking Lot'; pm='Stephanie Hardie'; s='2026-06-03'; f='2026-06-25'}
 @{t='Callaway Parking - Issue #961';key='Callaway Parking - Issue #961';job='1484'; bay='Parking Lot'; pm='Frank Mancina / Mark St. Jean'; s='2026-06-10'; f='2026-06-19'}
 @{t='Boston Scientific DX - Trailer Leak'; key='6160 Kentucky Expandable Trailer 2022'; job='J1507'; bay='Parking Lot'; pm='Alex Karam'; s='2026-06-08'; f='2026-06-12'}
 @{t='SENO Medical - Indoor Space Required'; key='SENO Medical - Indoor Space Req.'; job='J1541'; bay='Parking Lot'; pm='Alex Karam'; s='2026-04-07'; f='2026-06-12'}
 @{t='SMC Corporation - Return for QC'; key='SMC Corporation - Return for QC'; job='1542'; bay='On Hold/Off-Site'; pm='Al Karloff'; s=''; f=''}
 @{t='Siemens Big Betty - Maintenance/Prep'; key='Siemens Big Betty - Maint./Prep'; job='J1014'; bay='On Hold/Off-Site'; pm='TBD'; s=''; f=''}
 @{t='Stryker - Rewrap';            key='Stryker - Rewrap';            job='J1412'; bay='TBD'; pm='Megan Fraser'; s='2026-10-12'; f='2026-10-30'}
 @{t='AWS Revamp';                  key='AWS Revamp';                  job='J1217'; bay='TBD'; pm='TBD'; s='2026-07-31'; f='2026-09-08'}
 @{t='County of Essex - Generator Swap'; key='County of Essex - Generator Swap'; job='J1467'; bay='TBD'; pm='Sherrill Buchan'; s='2026-07-13'; f='2026-07-17'}
 @{t='Mammo Mandy - Maintenance Week'; key='Mammo Mandy - Maintenance Week'; job='J1424'; bay='TBD'; pm='Mitch Schirr'; s='2026-08-31'; f='2026-09-11'}
 @{t='SWC HI - Final Finishes';     key='SWC HI - Final Finishes';     job='J1512'; bay='TBD'; pm='TBD'; s='2026-08-31'; f='2026-09-17'}
 @{t='SWC IL - Maintenance Updates';key='SWC IL - Maintenance Updates';job='J1422'; bay='N/A'; pm='TBD'; s='2026-06-27'; f='2026-07-10'}
 @{t='AZ250/Trumpf - Analysis';     key='AZ250/Trumpf - Analysis';     job='J1554'; bay='TBD'; pm='Al Karloff'; s='2026-08-13'; f=''}
 @{t='ABB - Maintenance & Pre-Launch Prep'; key='ABB - Maintenance Items'; job='J1407'; bay='TBD'; pm='Brandon Kosal'; s='2026-07-06'; f='2026-08-21'}
 @{t='WFCU - Pre-Launch Assessment';new=$true; bay=''; client='WFCU'; job='J1479'; pm='Megan Fraser'; s='2026-06-18'; f='2026-06-26'}
 @{t='Ferguson BizBox - Graphic Updates'; key='Ferguson BizBox - Graphic Updates'; job='J1557'; bay=''; pm='Luciana Giglio'; s=''; f='2026-07-09'}
 @{t='ABB DX - Electrical Swap';    key='ABB DX - Electrical Swap';    job='J1014'; bay=''; pm='N/A'; s=''; f=''}
)

# ---- save everything below to a Desktop log (so it's easy to read / paste) --
$Transcript = Join-Path ([Environment]::GetFolderPath('Desktop')) ('merge-' + $(if($Apply){'APPLIED'}else{'preview'}) + '.txt')
Start-Transcript -Path $Transcript -Force | Out-Null
try {

# ---- read current Input rows ------------------------------------------------
$z = Open-Zip $Master
try {
    $shared = New-Object Collections.ArrayList
    $ssx = Read-Entry $z.zip 'xl/sharedStrings.xml'
    if($ssx){ [xml]$ss=$ssx; foreach($si in $ss.sst.si){[void]$shared.Add([string]$si.InnerText)} }
    [xml]$wb   = Read-Entry $z.zip 'xl/workbook.xml'
    [xml]$rels = Read-Entry $z.zip 'xl/_rels/workbook.xml.rels'
    $sx = Get-SheetXml $z.zip $wb $rels $Sheet
    if(-not $sx){ throw "Sheet '$Sheet' not found in $Master" }
    $cur = New-Object Collections.ArrayList
    $maxRow = 1
    foreach($row in $sx.worksheet.sheetData.row){
        $rn=[int]$row.r; $pc=Get-RowCells $row
        $anyVal=$false; foreach($col in 'A','B','C','D','E','F','G','H','I','J','K'){ if((("$(Resolve-Cell $pc[$col] $shared)").Trim()) -ne ''){ $anyVal=$true; break } }
        if($anyVal -and $rn -gt $maxRow){ $maxRow=$rn }
        if($rn -lt 4){ continue }
        $proj=("$(Resolve-Cell $pc['B'] $shared)").Trim(); if($proj -eq ''){ continue }
        [void]$cur.Add([pscustomobject]@{ row=$rn
            bay=("$(Resolve-Cell $pc['A'] $shared)").Trim(); project=$proj
            client=("$(Resolve-Cell $pc['C'] $shared)").Trim(); job=("$(Resolve-Cell $pc['D'] $shared)").Trim()
            start=(Coerce-Date (Resolve-Cell $pc['E'] $shared)); finish=(Coerce-Date (Resolve-Cell $pc['F'] $shared))
            pm=("$(Resolve-Cell $pc['K'] $shared)").Trim() }) }
} finally { Close-Zip $z }

# ---- compute the plan -------------------------------------------------------
$ops    = New-Object Collections.ArrayList
$warn   = New-Object Collections.ArrayList
$appendAt = $maxRow + 1
$addLines = New-Object Collections.ArrayList
$updRows=0; $addRows=0

function Find-Match($e){
    $k=Norm $e.key
    if($k -ne ''){ $m=@($cur|?{(Norm $_.project) -eq $k}); if($m.Count -ge 1){return $m[0]} }
    if($e.job){ $jm=@($cur|?{(Norm $_.job) -eq (Norm $e.job)}); if($jm.Count -eq 1){return $jm[0]} }
    return $null
}

foreach($e in $PLAN){
    if($e.new){
        $addRows++; $r=$appendAt; $appendAt++
        [void]$addLines.Add("ADD row $r : $($e.t)  [$($e.client) $($e.job)]  bay='$($e.bay)' pm='$($e.pm)' start='$($e.s)' finish='$($e.f)'")
        if(Concrete $e.bay){ [void]$ops.Add(@{row=$r;col=1;val=$e.bay;date=$false}) }
        [void]$ops.Add(@{row=$r;col=2;val=$e.t;date=$false})
        if(("$($e.client)").Trim() -ne ''){ [void]$ops.Add(@{row=$r;col=3;val=$e.client;date=$false}) }
        if(("$($e.job)").Trim() -ne ''){ [void]$ops.Add(@{row=$r;col=4;val=$e.job;date=$false}) }
        if(Concrete $e.pm){ [void]$ops.Add(@{row=$r;col=11;val=$e.pm;date=$false}) }
        if(("$($e.s)").Trim() -ne ''){ [void]$ops.Add(@{row=$r;col=5;val=(ToDate $e.s);date=$true}) }
        if(("$($e.f)").Trim() -ne ''){ [void]$ops.Add(@{row=$r;col=6;val=(ToDate $e.f);date=$true}) }
        continue
    }
    $m=Find-Match $e
    if($null -eq $m){ [void]$warn.Add("NO MATCH: '$($e.t)' (key '$($e.key)', job $($e.job)) - NOT changed. Tell me and I'll fix the match."); continue }
    $chg=New-Object Collections.ArrayList
    if((Concrete $e.bay) -and (Norm $e.bay) -ne (Norm $m.bay)){ [void]$ops.Add(@{row=$m.row;col=1;val=$e.bay;date=$false}); [void]$chg.Add("Bay '$($m.bay)'->'$($e.bay)'") }
    if((Concrete $e.pm)  -and ("$($e.pm)").Trim() -ne $m.pm){ [void]$ops.Add(@{row=$m.row;col=11;val=$e.pm;date=$false}); [void]$chg.Add("PM '$($m.pm)'->'$($e.pm)'") }
    if($e.setjob -and $m.job -ne $e.setjob){ [void]$ops.Add(@{row=$m.row;col=4;val=$e.setjob;date=$false}); [void]$chg.Add("Job# '$($m.job)'->'$($e.setjob)'") }
    elseif(-not $e.setjob -and $e.job -and (Norm $e.job) -ne (Norm $m.job)){ [void]$warn.Add("Job# differs on '$($m.project)': workbook '$($m.job)' vs Smartsheet '$($e.job)' - left unchanged (review).") }
    $ns=ToDate $e.s; if($ns -and (($null -eq $m.start) -or ($m.start.Date -ne $ns.Date))){ [void]$ops.Add(@{row=$m.row;col=5;val=$ns;date=$true}); [void]$chg.Add("Start '$(if($m.start){$m.start.ToString('MM/dd/yy')}else{'-'})'->'$($ns.ToString('MM/dd/yy'))'") }
    $nf=ToDate $e.f; if($nf -and (($null -eq $m.finish) -or ($m.finish.Date -ne $nf.Date))){ [void]$ops.Add(@{row=$m.row;col=6;val=$nf;date=$true}); [void]$chg.Add("Finish '$(if($m.finish){$m.finish.ToString('MM/dd/yy')}else{'-'})'->'$($nf.ToString('MM/dd/yy'))'") }
    if($chg.Count){ $updRows++; Write-Host ("UPDATE row {0,-3} {1,-42} {2}" -f $m.row, $m.project, ($chg -join '; ')) -ForegroundColor Yellow }
}

Write-Host ""
foreach($l in $addLines){ Write-Host $l -ForegroundColor Green }
if($warn.Count){ Write-Host ""; foreach($w in $warn){ Write-Host "!! $w" -ForegroundColor Magenta } }
Write-Host ""
Write-Host ("SUMMARY: {0} existing row(s) to update, {1} new row(s) to add, {2} flag(s)." -f $updRows,$addRows,$warn.Count) -ForegroundColor Cyan

if(-not $Apply){
    Write-Host "`nPREVIEW ONLY - nothing written. Re-run with  -Apply  to make these changes." -ForegroundColor White
    return
}
if($ops.Count -eq 0){ Write-Host "Nothing to write."; return }

# ---- APPLY: backup, then write via Excel COM --------------------------------
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = $Master -replace '\.xlsx$', "_PREMERGE_$stamp.xlsx"
Copy-Item $Master $backup -Force
Write-Host "Backup saved: $backup" -ForegroundColor DarkGray

$xl=$null; $mwb=$null; $phase='launch Excel'
try {
    $xl=New-Object -ComObject Excel.Application
    $xl.Visible=$false; $xl.DisplayAlerts=$false; $xl.AskToUpdateLinks=$false; $xl.EnableEvents=$false; $xl.ScreenUpdating=$false
    try{$xl.AutomationSecurity=1}catch{}
    $phase='open master'; $mwb=$xl.Workbooks.Open($Master)
    if($mwb.ReadOnly){ Write-Host "Master is open/locked - close it and re-run." -ForegroundColor Red; return }
    $phase='find Input'; $ws=$null; foreach($s in $mwb.Worksheets){ if($s.Name -eq $Sheet){$ws=$s;break} }
    if($null -eq $ws){ throw "Input sheet not found" }
    try{ if($ws.ProtectContents){$ws.Unprotect()} }catch{ Write-Host "NOTE: Input is protected and couldn't be unprotected - writes may fail." -ForegroundColor Yellow }
    foreach($op in $ops){
        $phase="write r$($op.row) c$($op.col)"
        $cell=$ws.Cells.Item($op.row,$op.col)
        if($op.date){ $cell.Value=([datetime]$op.val).ToOADate().ToString([Globalization.CultureInfo]::InvariantCulture); $cell.NumberFormat='m/d/yyyy' }
        else        { $cell.Value="$($op.val)" }
    }
    $phase='save'; $mwb.Save(); $mwb.Close($true); $mwb=$null
    Write-Host "`nDONE - wrote $($ops.Count) cell(s): $updRows row(s) updated, $addRows row(s) added. Master saved." -ForegroundColor Green
    Write-Host "Run Update-Auto.ps1 (or wait for the next cycle) to refresh the dashboard." -ForegroundColor Green
}
catch { Write-Host "WRITE ERROR [phase: $phase]: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "No partial save committed; your backup is at $backup" -ForegroundColor Yellow }
finally {
    if($null -ne $mwb){ try{$mwb.Close($false)}catch{} }
    if($null -ne $xl){ try{$xl.Quit()}catch{} }
    foreach($o in @($mwb,$xl)){ if($null -ne $o){ try{[void][Runtime.InteropServices.Marshal]::ReleaseComObject($o)}catch{} } }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}

}  # end outer try
finally {
    try { Stop-Transcript | Out-Null } catch {}
    Write-Host "`n(Full output saved to: $Transcript  - open it and paste it to me.)"
}
