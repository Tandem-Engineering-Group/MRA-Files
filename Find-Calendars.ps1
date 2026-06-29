# Find-Calendars.ps1
# READ-ONLY. Searches this PC for synced "Logistics Calendar" workbooks and
# reports where (if anywhere) they live locally. Changes nothing.
# Results are printed AND saved to your Desktop as calendar-search.txt.

$ErrorActionPreference = 'SilentlyContinue'
$out = Join-Path ([Environment]::GetFolderPath('Desktop')) 'calendar-search.txt'
Start-Transcript -Path $out -Force | Out-Null

Write-Host "Searching for '*Logistics*Calendar*.xlsx' in synced (OneDrive/SharePoint) folders..."

# Candidate sync roots: OneDrive + org-synced SharePoint libraries
# (those show up as top-level folders like "Tenant - LibraryName").
$roots = @()
if ($env:OneDrive)           { $roots += $env:OneDrive }
if ($env:OneDriveCommercial) { $roots += $env:OneDriveCommercial }
Get-ChildItem -Path $env:USERPROFILE -Directory |
    Where-Object { $_.Name -match 'OneDrive' -or $_.Name -match ' - ' } |
    ForEach-Object { $roots += $_.FullName }
$roots = $roots | Where-Object { $_ -and (Test-Path $_) } | Sort-Object -Unique

Write-Host "`nFolders searched:"
$roots | ForEach-Object { Write-Host "   $_" }

$hits = foreach ($r in $roots) {
    Get-ChildItem -Path $r -Recurse -File -Filter '*Logistics*' -Depth 6 |
        Where-Object { $_.Extension -eq '.xlsx' -and $_.Name -match 'Calendar' }
}
$hits = $hits | Sort-Object FullName -Unique

Write-Host "`n==================== RESULT ===================="
if (-not $hits) {
    Write-Host "NONE FOUND in synced folders."
    Write-Host "=> The calendars are probably NOT synced to this PC (online-only)."
} else {
    Write-Host "FOUND $($hits.Count) calendar file(s)."
    Write-Host "`nDistinct folder(s) they live in:"
    $hits | Select-Object -ExpandProperty DirectoryName -Unique | ForEach-Object { Write-Host "   $_" }
    Write-Host "`nFiles:"
    $hits | ForEach-Object { Write-Host "   $($_.Name)" }
}
Write-Host "================================================"
Write-Host "`n(Read-only - nothing was changed. Results saved to: $out)"

Stop-Transcript | Out-Null
