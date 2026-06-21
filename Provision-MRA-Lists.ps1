<#
  Provision-MRA-Lists.ps1
  STEP 3 (1 of 4): create the SharePoint Lists that replace the Excel workbook.

  Idempotent — safe to re-run; it only creates what's missing.

  PREREQS (one time):
    Install-Module PnP.PowerShell -Scope CurrentUser
    # You must be a SITE OWNER of the MRA Site Project site.

  RUN:
    ./Provision-MRA-Lists.ps1 -SiteUrl "https://snptechnical.sharepoint.com/sites/MRASiteProject"

  Then: spot-check the new Lists in SharePoint, and run Migrate-Workbook-To-Lists.ps1.
#>
param(
  [Parameter(Mandatory = $true)] [string] $SiteUrl
)

$ErrorActionPreference = 'Stop'
Connect-PnPOnline -Url $SiteUrl -Interactive

# ---- helpers -----------------------------------------------------------------
function Ensure-List([string]$Title) {
  $l = Get-PnPList -Identity $Title -ErrorAction SilentlyContinue
  if (-not $l) {
    Write-Host "Creating list '$Title'…" -ForegroundColor Cyan
    $l = New-PnPList -Title $Title -Template GenericList -EnableVersioning
  } else {
    Write-Host "List '$Title' already exists." -ForegroundColor DarkGray
  }
  return $l
}

# Set the built-in Title column's display label (Title is always present).
function Set-TitleLabel([string]$List, [string]$Label) {
  try { Set-PnPField -List $List -Identity 'Title' -Values @{ Title = $Label } | Out-Null } catch {}
}

# Add a field if it isn't already there. $Type: Text|Note|Number|Boolean|Choice|DateTime
function Ensure-Field([string]$List, [string]$Internal, [string]$Display, [string]$Type, [string[]]$Choices) {
  $f = Get-PnPField -List $List -Identity $Internal -ErrorAction SilentlyContinue
  if ($f) { Write-Host "  · $List.$Internal exists" -ForegroundColor DarkGray; return }
  Write-Host "  + $List.$Internal ($Type)" -ForegroundColor Green
  if ($Type -eq 'Choice') {
    Add-PnPField -List $List -DisplayName $Display -InternalName $Internal -Type Choice -Choices $Choices -AddToDefaultView | Out-Null
  } else {
    Add-PnPField -List $List -DisplayName $Display -InternalName $Internal -Type $Type -AddToDefaultView | Out-Null
  }
}

# ---- MRA Users ---------------------------------------------------------------
$u = 'MRA Users'
Ensure-List $u | Out-Null
Set-TitleLabel $u 'Name'
Ensure-Field $u 'Code'   'Code'   'Text'
Ensure-Field $u 'Active' 'Active' 'Boolean'
Ensure-Field $u 'Role'   'Role'   'Choice' @('Admin','Editor','Viewer')

# ---- MRA Jobs (floor jobs / trailers) ---------------------------------------
$j = 'MRA Jobs'
Ensure-List $j | Out-Null
Set-TitleLabel $j 'Project'
Ensure-Field $j 'Bay'         'Bay'         'Text'
Ensure-Field $j 'Client'      'Client'      'Text'
Ensure-Field $j 'JobNum'      'JobNum'      'Text'
Ensure-Field $j 'JobStatus'   'JobStatus'   'Choice' @('Active','Scheduled','On Hold','Shipped','Leave','TBD')
Ensure-Field $j 'Category'    'Category'    'Text'
Ensure-Field $j 'ShipISO'     'ShipISO'     'Text'
Ensure-Field $j 'SortOrder'   'SortOrder'   'Number'
Ensure-Field $j 'PhysicalBay' 'PhysicalBay' 'Boolean'

# ---- MRA Shop Tasks ----------------------------------------------------------
$st = 'MRA Shop Tasks'
Ensure-List $st | Out-Null
Set-TitleLabel $st 'Task'
Ensure-Field $st 'Project'   'Project'   'Text'
Ensure-Field $st 'Assigned'  'Assigned'  'Text'
Ensure-Field $st 'Status'    'Status'    'Choice' @('Open','In Progress','Done','N/A')
Ensure-Field $st 'Milestone' 'Milestone' 'Boolean'
Ensure-Field $st 'Comments'  'Comments'  'Note'
Ensure-Field $st 'SortOrder' 'SortOrder' 'Number'

# ---- MRA Project Tasks -------------------------------------------------------
$pt = 'MRA Project Tasks'
Ensure-List $pt | Out-Null
Set-TitleLabel $pt 'Task'
Ensure-Field $pt 'Project'     'Project'     'Text'
Ensure-Field $pt 'TaskID'      'TaskID'      'Number'
Ensure-Field $pt 'Phase'       'Phase'       'Text'
Ensure-Field $pt 'Type'        'Type'        'Text'
Ensure-Field $pt 'Assigned'    'Assigned'    'Text'
Ensure-Field $pt 'StartISO'    'StartISO'    'Text'
Ensure-Field $pt 'FinishISO'   'FinishISO'   'Text'
Ensure-Field $pt 'Duration'    'Duration'    'Text'
Ensure-Field $pt 'Status'      'Status'      'Text'
Ensure-Field $pt 'PM'          'PM'          'Text'
Ensure-Field $pt 'Milestone'   'Milestone'   'Boolean'
Ensure-Field $pt 'Comments'    'Comments'    'Note'
Ensure-Field $pt 'Predecessor' 'Predecessor' 'Text'
Ensure-Field $pt 'Sub'         'Sub'         'Boolean'
Ensure-Field $pt 'ParentID'    'ParentID'    'Number'
Ensure-Field $pt 'SubRes'      'SubRes'      'Text'
Ensure-Field $pt 'EstDays'     'EstDays'     'Number'
Ensure-Field $pt 'EstHours'    'EstHours'    'Number'
Ensure-Field $pt 'Budget'      'Budget'      'Number'
Ensure-Field $pt 'SortOrder'   'SortOrder'   'Number'

# ---- MRA Holidays (optional) -------------------------------------------------
$h = 'MRA Holidays'
Ensure-List $h | Out-Null
Set-TitleLabel $h 'Name'
Ensure-Field $h 'DateISO' 'DateISO' 'Text'
Ensure-Field $h 'Country' 'Country' 'Choice' @('US','CA','BOTH')

Write-Host "`nDone. Lists provisioned on $SiteUrl" -ForegroundColor Cyan
Write-Host "Next: Migrate-Workbook-To-Lists.ps1 to fill them from the current workbook." -ForegroundColor Yellow
