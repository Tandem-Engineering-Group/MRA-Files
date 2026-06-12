# MRA Dashboard - silent auto-update (run by Task Scheduler, every 15 min)
# EXCEL-FREE: rebuilds data.js from the workbook, then uploads it to Azure via
# AzCopy. No window, no prompts. Logs to auto-log.txt.
#
# NOTE: the intake import is intentionally NOT run here. It needs Excel, and
# Excel can't be driven reliably from a background scheduled task (it hangs).
# To import dropped intake files, double-click Import-Now.bat instead - the
# next scheduled push (or running this) will then show the new rows.

Set-Location -Path $PSScriptRoot
"=== Run started $(Get-Date) ===" | Out-File "$PSScriptRoot\auto-log.txt"

try {
    & "$PSScriptRoot\Export-Data.ps1" *>> "$PSScriptRoot\auto-log.txt"
} catch {
    "Export error: $($_.Exception.Message)" | Out-File "$PSScriptRoot\auto-log.txt" -Append
}

$target = (Get-Content "$PSScriptRoot\azure-target.txt" -Raw).Trim()
& "$PSScriptRoot\azcopy.exe" copy "$PSScriptRoot\data.js" $target --overwrite=true --content-type "application/javascript" *>> "$PSScriptRoot\auto-log.txt"

"=== Run finished $(Get-Date) ===" | Out-File "$PSScriptRoot\auto-log.txt" -Append
