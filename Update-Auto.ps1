# MRA Dashboard - silent auto-update (run by Task Scheduler, e.g. every 15 min)
# Rebuilds data.js from the workbook, then uploads it to Azure via AzCopy.
# No window, no prompts. Writes a small log to auto-log.txt for troubleshooting.
# Lives in the same folder as Export-Data.ps1, azcopy.exe and azure-target.txt.

Set-Location -Path $PSScriptRoot
"=== Run started $(Get-Date) ===" | Out-File "$PSScriptRoot\auto-log.txt"

# 1) Pull in any completed intake files dropped in "Intake Inbox" (best-effort;
#    never blocks the export/push - it bails if the master is open or Excel fails).
try {
    & "$PSScriptRoot\Import-Intake.ps1" *>> "$PSScriptRoot\auto-log.txt"
} catch {
    "Import-Intake error: $($_.Exception.Message)" | Out-File "$PSScriptRoot\auto-log.txt" -Append
}

# 2) Rebuild data.js from the workbook.
try {
    & "$PSScriptRoot\Export-Data.ps1" *>> "$PSScriptRoot\auto-log.txt"
} catch {
    "Export error: $($_.Exception.Message)" | Out-File "$PSScriptRoot\auto-log.txt" -Append
}

$target = (Get-Content "$PSScriptRoot\azure-target.txt" -Raw).Trim()
& "$PSScriptRoot\azcopy.exe" copy "$PSScriptRoot\data.js" $target --overwrite=true --content-type "application/javascript" *>> "$PSScriptRoot\auto-log.txt"

"=== Run finished $(Get-Date) ===" | Out-File "$PSScriptRoot\auto-log.txt" -Append
