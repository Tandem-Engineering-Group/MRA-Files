# Fix-ProjectTasksXlsx.ps1
# Reads the Project Tasks sheet from MRA_Shop_Board and writes a new xlsx
# where EVERY cell is a plain text string — no date/number type detection by SharePoint.
# Run from any PowerShell window. No Excel install needed.
#
# Usage:
#   .\Fix-ProjectTasksXlsx.ps1
#   (optional) .\Fix-ProjectTasksXlsx.ps1 -WorkbookPath "C:\path\to\MRA_Shop_Board_v6_9_7.xlsx"

param(
    [string]$WorkbookPath = '',
    [string]$OutPath      = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

# ---- Locate workbook -------------------------------------------------------
if ($WorkbookPath -eq '') {
    $candidates = @(
        (Join-Path $env:USERPROFILE 'OneDrive - MRA\MRA Files''s files - nobackup\MRA_Shop_Board_v6_9_7.xlsx'),
        (Join-Path $env:USERPROFILE 'OneDrive\MRA Files''s files - nobackup\MRA_Shop_Board_v6_9_7.xlsx'),
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'MRA_Shop_Board_v6_9_7.xlsx')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { $WorkbookPath = $c; break } }
}
if ($WorkbookPath -eq '' -or -not (Test-Path $WorkbookPath)) {
    $WorkbookPath = Read-Host "Enter full path to MRA_Shop_Board_v6_9_7.xlsx"
}
if (-not (Test-Path $WorkbookPath)) { throw "Workbook not found: $WorkbookPath" }

if ($OutPath -eq '') { $OutPath = Join-Path (Split-Path $WorkbookPath) 'MRA_ProjectTasks_fixed.xlsx' }

Write-Host "Reading: $WorkbookPath"

# ---- Helpers ---------------------------------------------------------------
function Read-Entry($zip, $name) {
    $e = $zip.Entries | Where-Object { $_.FullName -eq $name }
    if (-not $e) { return $null }
    $sr = New-Object System.IO.StreamReader($e.Open(), [Text.Encoding]::UTF8)
    $txt = $sr.ReadToEnd(); $sr.Close(); return $txt
}
function Resolve-Cell($c, $shared) {
    if ($null -eq $c) { return '' }
    $t = $c.t
    if ($t -eq 's')         { return [string]$shared[[int]$c.v] }
    elseif ($t -eq 'inlineStr') { return [string]$c.InnerText }
    elseif ($t -eq 'str')   { return [string]$c.v }
    else                    { return [string]$c.v }
}
function CellDate($c) {
    if ($null -eq $c) { return $null }
    if ($c.t -in @('s','inlineStr','str')) { return $null }
    $v = $c.v; if ([string]::IsNullOrEmpty($v)) { return $null }
    try { return [DateTime]::FromOADate([double]$v) } catch { return $null }
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

# ---- Read source -----------------------------------------------------------
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("mra_fix_" + [System.IO.Path]::GetFileName($WorkbookPath))
[System.IO.File]::Copy($WorkbookPath, $tmp, $true)
$zip = [System.IO.Compression.ZipFile]::OpenRead($tmp)

$nsMain = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
$nsRel  = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
$nsPkg  = 'http://schemas.openxmlformats.org/package/2006/relationships'

$shared = New-Object System.Collections.ArrayList
$ssXml  = Read-Entry $zip 'xl/sharedStrings.xml'
if ($ssXml) { [xml]$ss = $ssXml; foreach ($si in $ss.sst.si) { [void]$shared.Add([string]$si.InnerText) } }

[xml]$wbXml   = Read-Entry $zip 'xl/workbook.xml'
[xml]$relsXml = Read-Entry $zip 'xl/_rels/workbook.xml.rels'

$projXml = Get-SheetXml $zip $wbXml $relsXml 'Project Tasks' $nsMain $nsRel $nsPkg
if (-not $projXml) { $zip.Dispose(); throw "Sheet 'Project Tasks' not found in workbook." }

# Columns A-T (20 columns). Col E and F are dates -> format as MM/dd/yy text.
$COLS = 'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T'
$DATE_COLS = @('E','F')

$rows = New-Object System.Collections.ArrayList
foreach ($row in $projXml.worksheet.sheetData.row) {
    $rn = [int]$row.r
    $pc = Get-RowCells $row
    $r  = New-Object System.Collections.ArrayList
    foreach ($col in $COLS) {
        $c = $pc[$col]
        if ($col -in $DATE_COLS) {
            $d = CellDate $c
            if ($d) { [void]$r.Add($d.ToString('MM/dd/yy')) }
            else    { [void]$r.Add([string](Resolve-Cell $c $shared)) }
        } else {
            [void]$r.Add([string](Resolve-Cell $c $shared))
        }
    }
    [void]$rows.Add(@{ rn = $rn; vals = @($r) })
}
$zip.Dispose()
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

Write-Host "Read $($rows.Count) rows (including header)"

# ---- Write xlsx (minimal Open XML, all cells as inlineStr) -----------------
# We write a bare-bones xlsx: workbook + single worksheet + no shared strings
# (every cell uses inlineStr so SharePoint CANNOT misdetect the type).
function Xml-Escape([string]$s) {
    $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' -replace "'", '&apos;'
}

$OXNS = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'

$sheetRows = New-Object System.Text.StringBuilder
foreach ($row in $rows) {
    $rn   = $row.rn
    $vals = $row.vals
    $colIdx = 0
    $cells = New-Object System.Text.StringBuilder
    foreach ($v in $vals) {
        $colLetter = $COLS[$colIdx]
        $ref = "${colLetter}${rn}"
        $esc = Xml-Escape $v
        [void]$cells.Append("<c r=`"$ref`" t=`"inlineStr`"><is><t>$esc</t></is></c>")
        $colIdx++
    }
    [void]$sheetRows.Append("<row r=`"$rn`">$($cells.ToString())</row>")
}

$sheetXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet $OXNS>
  <sheetData>
$($sheetRows.ToString())
  </sheetData>
</worksheet>
"@

$wbXmlOut = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Project Tasks" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>
'@

$wbRels = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>
'@

$contentTypes = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml"  ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>
'@

$rootRels = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
'@

if (Test-Path $OutPath) { Remove-Item $OutPath -Force }
$ms   = New-Object System.IO.MemoryStream
$arch = [System.IO.Compression.ZipArchive]::new($ms, [System.IO.Compression.ZipArchiveMode]::Create, $true)
function Add-Entry([System.IO.Compression.ZipArchive]$z, [string]$name, [string]$content) {
    $e  = $z.CreateEntry($name)
    $sw = New-Object System.IO.StreamWriter($e.Open(), [Text.Encoding]::UTF8)
    $sw.Write($content); $sw.Close()
}
Add-Entry $arch '[Content_Types].xml'          $contentTypes
Add-Entry $arch '_rels/.rels'                  $rootRels
Add-Entry $arch 'xl/workbook.xml'              $wbXmlOut
Add-Entry $arch 'xl/_rels/workbook.xml.rels'   $wbRels
Add-Entry $arch 'xl/worksheets/sheet1.xml'     $sheetXml
$arch.Dispose()
[System.IO.File]::WriteAllBytes($OutPath, $ms.ToArray())
$ms.Dispose()

Write-Host ""
Write-Host "Done. Written: $OutPath"
Write-Host "Row count (including header): $($rows.Count)"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Delete the current 'MRA Project Tasks' SharePoint list"
Write-Host "  2. New > List > From Excel > upload MRA_ProjectTasks_fixed.xlsx"
Write-Host "  3. Name it 'MRA Project Tasks'"
