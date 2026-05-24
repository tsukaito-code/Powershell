<#
.SYNOPSIS
Analyzes Active Directory Group Policy Objects (GPOs) and detects changes. After the analysis, the script sends an email report.

.DESCRIPTION
This script analyzes changes in the Active Directory Group Policy area.

Based on the comparison with the previous day's export, the script identifies:
- Overview of all GPOs (display name and GPO ID) for today and yesterday
- Newly created GPOs
- Renamed existing GPOs
- Deleted GPOs
- GPOs with changed settings, including a detailed analysis of what changed
- Archived data for documentation and possible manual reconstruction of GPO settings

To accomplish this, the script exports all GPO configurations as XML reports.
These reports are then compared and the detected changes are documented.

Note:
This script is not intended to be a backup or restore solution for GPO recovery.
Backup and restore functionality must be handled separately.

This script is designed for GPO monitoring. Based on the recorded timestamps,
further investigation can be performed using Active Directory log files.

Relevant domain controller events for GPO creation, deletion, and modification:
5137, 5136, 5138, 5130

.PARAMETER
None

.EXAMPLE
None

.INPUTS
None

.OUTPUTS
Email report

.NOTES
NAME:
TG-AD GPO Analyzer.ps1

REQUIREMENTS:
- Read permissions for GPOs in Active Directory
- A previous-day GPO export must exist (created automatically during the first execution)
- A scheduled task should run the script once per day

VERSION HISTORY:
2022.09.30 Initial version
2022.0x.xx CHANGE ADD FIX REMOVE

TODO:
- Add a notification in the email when no changes are detected
#>

#$TestMode = $true # Current effect: No file cleanup at the end of the script, email subject includes the tag "Test"
$TestMode = $false

#region Set variables
$ExportPath = "C:\batch\GPO"

$ADDomain = "contoso.com"

# SMTP settings
$SmtpServer = "smtp.contoso.com"
$SmtpFrom   = "gpo-report@contoso.com"
$SmtpTo     = "admin@contoso.com"

$PathBaseFolder = "$ExportPath\GPO-ChangeReporter" # Base directory used for all paths

# Define paths and create directories if they do not exist
$PathGPOArchiveFiles      = $PathBaseFolder + "\Archive"
$PathGPOCompare           = $PathBaseFolder + "\Compare"
$PathGPOToday             = $PathBaseFolder + "\Compare\Today"
$PathGPOYesterday         = $PathBaseFolder + "\Compare\Yesterday"
$PathGPOChangeHistory     = $PathBaseFolder + "\Compare\ChangeHistory"

$ExportGPOSummaryToday            = $PathBaseFolder + "\Compare\GPOSummaryToday.csv"             # All current GPOs with ID and display name
$ExportGPOSummaryYesterday        = $PathBaseFolder + "\Compare\GPOSummaryYesterday.csv"         # All GPOs from the previous day
$ExportGPOSummaryDeleted          = $PathBaseFolder + "\Compare\GPOSummaryDeleted.csv"           # All deleted GPOs
$ExportGPOSummaryNew              = $PathBaseFolder + "\Compare\GPOSummaryNew.csv"               # All newly detected GPOs
$ExportGPOSummaryChangedName      = $PathBaseFolder + "\Compare\GPOSummaryChangedName.csv"       # All GPOs with renamed display names
$ExportGPOSummaryChangedSettings  = $PathBaseFolder + "\Compare\GPOSummaryChangedSettings.csv"   # All GPOs with changed settings
#endregion

$PathArray = @($PathGPOArchiveFiles, $PathGPOCompare, $PathGPOToday, $PathGPOYesterday, $PathGPOChangeHistory)
foreach ($Path in $PathArray) {
    if (!(Test-Path -PathType Container $Path)) {
        New-Item -ItemType Directory -Path $Path
    }
}

# Function to replace special characters in GPO names
# for example ':', '/', '\' or German umlauts with file-system-safe characters
function Replace-Umlaut {
    param (
        [string]$Text
    )

    $CleanText = $Text
    switch -regex ($Text) {
        'ä'   { $CleanText = $CleanText -creplace 'ä', 'ae' }
        'Ä'   { $CleanText = $CleanText -creplace 'Ä', 'Ae' }
        'ö'   { $CleanText = $CleanText -creplace 'ö', 'oe' }
        'Ö'   { $CleanText = $CleanText -creplace 'Ö', 'Oe' }
        'ü'   { $CleanText = $CleanText -creplace 'ü', 'ue' }
        'Ü'   { $CleanText = $CleanText -creplace 'Ü', 'Ue' }
        'ß'   { $CleanText = $CleanText -creplace 'ß', 'ss' }
        ':'   { $CleanText = $CleanText -creplace ':', '-' }
        '/'   { $CleanText = $CleanText -creplace '/', '-' }
        '\\'  { $CleanText = $CleanText -creplace '\\', '-' }
    }
    $CleanText
}

# Read all GPOs and export them
# Result:
# - XML export of each GPO configuration
# - CSV file containing all current GPOs with ID and display name
Write-Verbose "[PROCESS] Starting retrieval of GPOs from Active Directory" -Verbose
$GPOResultSet = Get-GPO -All -Domain $ADDomain
$GPOResultSet | Select ID, DisplayName | Export-Csv $ExportGPOSummaryToday -NoTypeInformation -Encoding Unicode

foreach ($Policy in $GPOResultSet) {
    $PolicyNew = Replace-Umlaut $Policy.DisplayName
    $TmpPath = $PathGPOToday + "\" + $PolicyNew + ".xml"
    Get-GPOReport -Name $Policy.DisplayName -ReportType XML -Path $TmpPath
}

# Check whether new GPOs were created since the last comparison
# Result: CSV file listing all newly detected GPOs
Write-Verbose "[PROCESS] Starting check for new GPOs" -Verbose
if (Test-Path $ExportGPOSummaryNew) { Remove-Item $ExportGPOSummaryNew }

$VarGPOToday = Import-Csv $ExportGPOSummaryToday | Select ID, DisplayName
$VarGPOYesterday = Import-Csv $ExportGPOSummaryYesterday | Select ID, DisplayName
$VarDiff = Compare-Object -DifferenceObject $VarGPOToday.ID -ReferenceObject $VarGPOYesterday.ID | Where-Object SideIndicator -eq "=>" | Select InputObject

$VarHeader = "`"ID`", `"DisplayName`""
Add-Content $ExportGPOSummaryNew $VarHeader

foreach ($Item1 in $VarDiff) {
    foreach ($Item in $Item1) {
        $VarLine = ""
        $VarGPOTodayID = $Item.InputObject
        $VarLineTmp = $VarGPOToday | Where-Object { $_.ID -eq $Item.InputObject } | Select ID, DisplayName
        $VarLine = "`"" + $VarLineTmp.ID + "`", `"" + $VarLineTmp.DisplayName + "`""
    }
    Add-Content $ExportGPOSummaryNew $VarLine
}

# Check whether GPOs were deleted since the last comparison
# Result: CSV file listing all deleted GPOs
Write-Verbose "[PROCESS] Starting check for deleted GPOs" -Verbose
if (Test-Path $ExportGPOSummaryDeleted) { Remove-Item $ExportGPOSummaryDeleted }

$VarDiff = Compare-Object -DifferenceObject (Get-Content $ExportGPOSummaryToday) -ReferenceObject (Get-Content $ExportGPOSummaryYesterday) | Where-Object SideIndicator -eq "<=" | Select InputObject

$VarHeader = "`"ID`", `"DisplayName`""
Add-Content $ExportGPOSummaryDeleted $VarHeader

foreach ($Item1 in $VarDiff) {
    foreach ($Item in $Item1) {
        $VarLine = ""
        $VarLine = $VarLine + $Item.InputObject
    }
    Add-Content $ExportGPOSummaryDeleted $VarLine
}

# Check whether existing GPOs were renamed
# Result: CSV file listing all renamed GPOs
Write-Verbose "[PROCESS] Starting check for renamed GPOs - patience you must have!" -Verbose
$VarGPOToday = Import-Csv $ExportGPOSummaryToday | Select ID, DisplayName
$VarGPOYesterday = Import-Csv $ExportGPOSummaryYesterday | Select ID, DisplayName

if (Test-Path $ExportGPOSummaryChangedName) { Remove-Item $ExportGPOSummaryChangedName }

$VarHeader = "`"ID`", `"DisplayName Old`", `"DisplayName New`""
Add-Content $ExportGPOSummaryChangedName $VarHeader

foreach ($Item2 in $VarGPOToday) {
    foreach ($Item3 in $VarGPOYesterday) {
        if ($Item2 | Select ID, DisplayName | Where-Object { ($Item2.ID -eq $Item3.ID) -and ($Item2.DisplayName -notlike $Item3.DisplayName) }) {
            $VarLine = "`"" + $Item2.ID + "`", `"" + $Item3.DisplayName + "`", `"" + $Item2.DisplayName + "`""
            Add-Content $ExportGPOSummaryChangedName $VarLine
        }
    }
}

# Check whether GPO settings changed and document what changed
# Result: One file per changed GPO for later inclusion in the email report
Write-Verbose "[PROCESS] Starting check for modified GPO settings" -Verbose
if (Test-Path $ExportGPOSummaryChangedSettings) { Remove-Item $ExportGPOSummaryChangedSettings }

$VarHeader = "`"DisplayName`", `" `""
Add-Content $ExportGPOSummaryChangedSettings $VarHeader

$GPOsToCompare = (Get-ChildItem -Path $PathGPOToday).BaseName
foreach ($GPO in $GPOsToCompare) {
    $CompareFileUpdate = $PathGPOToday + "\" + $GPO + ".xml"
    $CompareFileReference = $PathGPOYesterday + "\" + $GPO + ".xml"
    $Changes = ""

    # Check whether a reference file from yesterday exists
    if (Test-Path -Path $CompareFileReference) {
        Write-Verbose "[PROCESS] $CompareFileReference - Reference file found - starting comparison" -Verbose
        $Changes = Compare-Object -DifferenceObject (Get-Content $CompareFileUpdate) -ReferenceObject (Get-Content $CompareFileReference) |
            Select-Object @{n = 'State'; e = { if ($_.SideIndicator -eq "=>") { "Added" } else { "Removed" } } }, InputObject |
            Where-Object { $_.InputObject -notlike "*ReadTime*" }

        Write-Verbose "[PROCESS] $CompareFileReference - comparison completed" -Verbose

        if ($Changes -ne $null) {
            $Changes | Export-Csv -Path (Join-Path -Path $PathGPOChangeHistory -ChildPath "$($GPO).txt") -NoTypeInformation -Encoding Unicode
            $VarLine = "`"" + $GPO + "`""
            Add-Content $ExportGPOSummaryChangedSettings $VarLine
        }
    }
    else {
        Write-Verbose "[PROCESS] $CompareFileReference - no reference file found" -Verbose
    }
}

# Prepare the report for email delivery
Write-Verbose "[PROCESS] Preparing report and email delivery" -Verbose
$InfoChangesHistoryFiles = (Get-ChildItem -Path $PathGPOChangeHistory).BaseName
$InfoGPONew = if (Test-Path $ExportGPOSummaryNew) { Import-Csv $ExportGPOSummaryNew }
$InfoGPODeleted = if (Test-Path $ExportGPOSummaryDeleted) { Import-Csv $ExportGPOSummaryDeleted }
$InfoGPOChangedName = if (Test-Path $ExportGPOSummaryChangedName) { Import-Csv $ExportGPOSummaryChangedName }
$InfoGPOChangedSettings = if (Test-Path $ExportGPOSummaryChangedSettings) { Import-Csv $ExportGPOSummaryChangedSettings }

# HTML header used for the email tables
$Header = @"
<style>
TABLE {border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse;}
TD {border-width: 1px; padding: 3px; border-style: solid; border-color: black;}
</style>
"@

$Body = "<h1>IT Security Audit: Active Directory Group Policy Analyzer</h1>"
$Body += "<p>Report generated on $env:COMPUTERNAME at $(Get-Date -Format dd.MM.yyyy)</br>"
$Body += "Script path: C:\AdminScripts\ADS</p>"
$Body += "Export / Reports / Archive: D:\Administrative_Scripts\Exports\GPO-Analyzer</p>"
$Body += "<br>"
$Body += "<h2>New Group Policies</h2>"
$Body += $InfoGPONew | ConvertTo-Html -Head $Header
$Body += "<br>"
$Body += "<h2>Deleted Group Policies</h2>"
$Body += $InfoGPODeleted | ConvertTo-Html -Fragment
$Body += "<br>"
$Body += "<h2>Renamed Group Policies</h2>"
$Body += $InfoGPOChangedName | ConvertTo-Html -Fragment
$Body += "<br>"
$Body += "<h2>Modified Group Policies</h2>"
$Body += "<br>"
$Body += $InfoGPOChangedSettings | ConvertTo-Html -Fragment
$Body += "<br>"
$Body += "<h2>Detailed Information</h2>"

if ($InfoChangesHistoryFiles) {
    foreach ($Change in $InfoChangesHistoryFiles) {
        $InfoGPOName = $Change
        $InfoGPOChangeFile = $PathGPOChangeHistory + "\" + $InfoGPOName + ".txt"
        $InfoGPOChangeHistory = Import-Csv -Path $InfoGPOChangeFile -Encoding Unicode
        $Body += "<h3>GPO $InfoGPOName</h3>"
        $Body += $InfoGPOChangeHistory | ConvertTo-Html -Fragment
    }
}

$Body = $Body -replace "Added", "<font color=`"blue`"><b>Added</b></font>"
$Body = $Body -replace "Removed", "<font color=`"red`"><b>Removed</b></font>"
$Body += "</p>"

Write-Verbose "[PROCESS] Sending report" -Verbose

if ($TestMode -eq $true) {
    $MessageSubject = "(Test) IT Security Audit: Active Directory Group Policy Changes"
}
else {
    $MessageSubject = "IT Security Audit: Active Directory Group Policy Changes"
}

$Message = New-Object System.Net.Mail.MailMessage $SmtpFrom, $SmtpTo
$Message.Subject = $MessageSubject
$Message.IsBodyHTML = $true
$Message.Body = $Body

$Smtp = New-Object Net.Mail.SmtpClient($SmtpServer)
$Smtp.Send($Message)
$Message.Dispose()

# Archive the exported data and prepare for the next comparison
Write-Verbose "[PROCESS] Creating archive of exported data" -Verbose
[DateTime]$Datum = "01.01.1601 01:00:00"
$Date = Get-Date -Format "yyyyMMdd"
$ArchiveZIP = $PathGPOArchiveFiles + "\" + "ArchiveGPOAnalyzer (" + $Date + ").zip"
Compress-Archive -Path $PathGPOCompare -DestinationPath $ArchiveZIP -Force

# Remove temporary data and prepare reference data for the next execution
# Today's data is moved to the Yesterday folder to serve as the next reference set
if ($TestMode -eq $true) {
    if (Test-Path $PathGPOYesterday) { Remove-Item "$PathGPOYesterday\*.*" -WhatIf }
    if (Test-Path $PathGPOToday) { Move-Item "$PathGPOToday\*.*" $PathGPOYesterday -WhatIf }
    if (Test-Path $PathGPOToday) { Remove-Item "$PathGPOToday" -Recurse -Force -WhatIf }
    if (Test-Path $PathGPOChangeHistory) { Remove-Item "$PathGPOChangeHistory" -Recurse -Force -WhatIf }
    if (Test-Path $ExportGPOSummaryDeleted) { Remove-Item $ExportGPOSummaryDeleted -WhatIf }
    if (Test-Path $ExportGPOSummaryNew) { Remove-Item $ExportGPOSummaryNew -WhatIf }
    if (Test-Path $ExportGPOSummaryChangedName) { Remove-Item $ExportGPOSummaryChangedName -WhatIf }
    if (Test-Path $ExportGPOSummaryChangedSettings) { Remove-Item $ExportGPOSummaryChangedSettings -WhatIf }
    if (Test-Path $ExportGPOSummaryYesterday) { Remove-Item $ExportGPOSummaryYesterday -WhatIf }
    if (Test-Path $ExportGPOSummaryToday) { Move-Item $ExportGPOSummaryToday $ExportGPOSummaryYesterday -WhatIf }
}
else {
    if (Test-Path $PathGPOYesterday) { Remove-Item "$PathGPOYesterday\*.*" }
    if (Test-Path $PathGPOToday) { Move-Item "$PathGPOToday\*.*" $PathGPOYesterday }
    if (Test-Path $PathGPOToday) { Remove-Item "$PathGPOToday" -Recurse -Force }
    if (Test-Path $PathGPOChangeHistory) { Remove-Item "$PathGPOChangeHistory" -Recurse -Force }
    if (Test-Path $ExportGPOSummaryDeleted) { Remove-Item $ExportGPOSummaryDeleted }
    if (Test-Path $ExportGPOSummaryNew) { Remove-Item $ExportGPOSummaryNew }
    if (Test-Path $ExportGPOSummaryChangedName) { Remove-Item $ExportGPOSummaryChangedName }
    if (Test-Path $ExportGPOSummaryChangedSettings) { Remove-Item $ExportGPOSummaryChangedSettings }
    if (Test-Path $ExportGPOSummaryYesterday) { Remove-Item $ExportGPOSummaryYesterday }
    if (Test-Path $ExportGPOSummaryToday) { Move-Item $ExportGPOSummaryToday $ExportGPOSummaryYesterday }
}