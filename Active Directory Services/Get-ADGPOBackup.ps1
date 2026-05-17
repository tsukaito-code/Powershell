<#
.SYNOPSIS
    Exports current Group Policy settings as HTML reports and creates a backup archive.

.DESCRIPTION
    This script backs up Active Directory Group Policies and creates HTML reports of the
    current configuration (except for excluded GPOs such as LANCrypt, if applicable).

    The script performs the following tasks:
    - Creates an overview of all GPOs, including DisplayName and GpoID, in a summary file
    - Creates backups of all GPOs
    - Archives the generated backup and report data for historical reference and possible recovery
    - Sends an email report with the backup results

    Limitation:
    This script does not analyze or compare GPO changes. Change analysis must be handled
    separately by another process or script.

    Before running the script, you must customize the environment-specific configuration
    values in the script, especially the Active Directory domain and the export path.

.PARAMETER ADDomain
    Specifies the Active Directory domain that should be queried.

    Note:
    This is not passed as a formal script parameter. The value must be defined directly
    in the script by adjusting the $ADDomain variable.

.PARAMETER ExportPath
    Specifies the base path used for reports, backups, archives, and log output.

    Note:
    This is not passed as a formal script parameter. The value must be defined directly
    in the script by adjusting the $ExportPath variable.

.EXAMPLE
    Example configuration:
    $ADDomain   = "contoso.com"
    $ExportPath = "C:\Scripts\GPO-Backup"

    After adjusting these variables to match your environment, run the script manually
    or as a scheduled task with sufficient permissions to read Group Policy Objects
    and write data to the configured backup location.

.INPUTS
    None.

.OUTPUTS
    HTML email report
    ZIP archive containing backup data
    HTML GPO reports
    CSV summary file

.NOTES
    Name: Get-ADGPOBackup.ps1
    Author: Tsukaito
    Date: 2022.09.30
    Version: 1.4

    Requirements:
    - Read permissions for Group Policy Objects in Active Directory
    - A valid storage location for backups and archives
    - A scheduled task that runs the script once per day
    - The variables $ADDomain and $ExportPath must be adapted to the target environment
      before execution

    Version History:
    2022.09.30 Initial version
    2022.10.12
        CHANGE Removed the function that renamed each GPO backup directory to the DisplayName.
               Restore testing showed that restoring by Backup-ID only works if the directory
               is named after the ID.
        ADD    The report now includes an additional list with the Backup-ID, alongside the
               existing list with ModificationTime.
        ADD    Delete archive files older than 90 days
    2024.08.01
        ADD    Include retention information in the email output
               (backups older than the configured date will be deleted)
#>

# Set variables
$Daysback = "-90" # Number of days / age after which archive files will be deleted
$ADDomain = "domain.tld"
$smtpServer = "mailserver.domain.tld"
$smtpFrom = "GPOBackup@domain.tld"
$smtpTo = "admin@domain.tld"
$messageSubject = "IT-Security Audit: Active Directory Group Policy Backups"
$logPath = "C:\Scripts\GPO-Backup\tasklog.txt"
$ExportPath = "C:\export\GPO"

Start-Transcript -Path $logPath

# Retention date for deleting old backups
$CurrentDate = Get-Date
$DatetoDelete = $CurrentDate.AddDays($Daysback)
$DaysbackPositiv = [int]$Daysback * (-1)
$DatetoDeleteShort = $DatetoDelete.ToShortDateString()

#region Set variables
$pathBasisfolder = "$ExportPath\GPO-Backup" # Base directory on which all paths are built
$pathGPOBackup = $pathBasisfolder + "\Backup\GPOBackup" # Directory for GPO backups
$pathGPOReportsHTML = $pathBasisfolder + "\Backup\GPOReport" # Directory for HTML export of each GPO
$pathFolder2Backup = $pathBasisfolder + "\Backup" # Directory for the GPO summary and source directory for the backup of created files (ZIP file)
$pathGPOArchivefiles = $pathBasisfolder + "\Archive" # Directory where the compressed backups are stored
$pathGPOSummary = $pathFolder2Backup + "\GPOSummary.csv" # Summary of all GPO IDs and names

# Check / create paths
$PathArray = @($pathGPOBackup, $pathGPOReportsHTML, $pathFolder2Backup, $pathGPOArchivefiles)
foreach ($Path in $PathArray) {
    if (!(Test-Path -PathType Container $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

# Function to replace special characters in GPO names (e.g. ':', '/') with file-system-compatible characters
function Replace-Umlaut {
    param (
        [string]$Text
    )

    $CleanText = $Text
    switch -regex ($Text) {
        'ä' { $CleanText = $CleanText -creplace 'ä','ae' }
        'Ä' { $CleanText = $CleanText -creplace 'Ä','Ae' }
        'ö' { $CleanText = $CleanText -creplace 'ö','oe' }
        'Ö' { $CleanText = $CleanText -creplace 'Ö','Oe' }
        'ü' { $CleanText = $CleanText -creplace 'ü','ue' }
        'Ü' { $CleanText = $CleanText -creplace 'Ü','Ue' }
        'ß' { $CleanText = $CleanText -creplace 'ß','ss' }
        ':' { $CleanText = $CleanText -creplace ':','-' }
        '/' { $CleanText = $CleanText -creplace '/','-' }
        '\\' { $CleanText = $CleanText -creplace '\\','-' }
    }
    $CleanText
}

# Export GPO settings as HTML report (to review settings) and create a summary file (GPO ID, name)
Write-Verbose "[PROCESS] Starting GPO retrieval and creating an HTML report for each GPO" -Verbose
$GPOResultSet = Get-GPO -All -Domain $ADDomain

foreach ($Policy in $GPOResultSet) {
    $PolicyNew = Replace-Umlaut $Policy.DisplayName
    $tmpPath = $pathGPOReportsHTML + "\" + $PolicyNew + ".html"
    Get-GPOReport -Name $Policy.DisplayName -ReportType HTML -Path $tmpPath
}

# Back up GPOs and create summary with GPO name, GPO ID, and Backup-ID
Write-Verbose "[PROCESS] Creating GPO backups" -Verbose
$varHeader = "`"DisplayName`", `"GpoID`", `"Backup-ID`""
Add-Content -Path $pathGPOSummary -Value $varHeader

foreach ($GPO in $GPOResultSet) {
    Write-Host "[PROCESS] Backup: $($GPO.DisplayName)"
    $BackupInfo = Backup-GPO -Name $GPO.DisplayName -Path $pathGPOBackup
    $GpoBackupID = $BackupInfo.ID.Guid
    $GpoGuid = $BackupInfo.GPOID.Guid
    $GpoName = $BackupInfo.DisplayName

    # Write the summary file (including GpoGUID and Backup-ID)
    $varLine = "`"$GpoName`", `"$GpoGuid`", `"$GpoBackupID`""
    Add-Content -Path $pathGPOSummary -Value $varLine
}

# Archive the data / keep history
Write-Verbose "[PROCESS] Creating archive of the backed-up data" -Verbose
$date = Get-Date -Format "yyyyMMdd"
$ArchiveZIP = $pathGPOArchivefiles + "\" + "ArchiveGPOBackup (" + $date + ").zip"

Compress-Archive -Path $pathFolder2Backup -DestinationPath $ArchiveZIP -Force

# Prepare information for email delivery
Write-Verbose "[PROCESS] Starting report preparation and sending" -Verbose
$infoBackupArchives = Get-ChildItem -Path $pathGPOArchivefiles | Select-Object Name, @{Name="MB";Expression={ "{0:N0}" -f ($_.Length / 1MB) }}
$InfoBackupedGPOs = Import-Csv -Path $pathGPOSummary
$InfoBackupedGPOs2 = $GPOResultSet | Select-Object DisplayName, ID, ModificationTime | Sort-Object -Property DisplayName

$body = @"
<html>
<head>
<style>
body {
    font-family: Arial, sans-serif;
    font-size: 10pt;
    color: #000000;
}
table {
    border-width: 1px;
    border-style: solid;
    border-color: black;
    border-collapse: collapse;
}
th {
    border-width: 1px;
    padding: 4px;
    border-style: solid;
    border-color: black;
    background-color: #d9d9d9;
}
td {
    border-width: 1px;
    padding: 3px;
    border-style: solid;
    border-color: black;
}
h1, h2 {
    font-family: Arial, sans-serif;
}
</style>
</head>
<body>
<h1>IT-Security Audit: Active Directory Group Policy Backups</h1>

<p>
Report generated on $env:COMPUTERNAME on $(Get-Date -Format 'dd.MM.yyyy')<br />
Active Directory domain: $ADDomain<br />
SMTP server: $smtpServer<br />
Sender: $smtpFrom<br />
Recipient: $smtpTo<br />
Script log path: $logPath<br />
Export base path: $ExportPath<br />
Backup base folder: $pathBasisfolder<br />
GPO backup folder: $pathGPOBackup<br />
GPO HTML report folder: $pathGPOReportsHTML<br />
Archive folder: $pathGPOArchivefiles<br />
Summary file: $pathGPOSummary<br />
Deleting backups older than $DatetoDeleteShort ($DaysbackPositiv days)
</p>

<p>Content:</p>
<ul>
    <li>Overview of GPO backups</li>
    <li>Summary of backed-up Group Policies (with GpoID and Backup-ID)</li>
    <li>Summary of backed-up Group Policies (with ModificationTime)</li>
</ul>

<h2>Overview of GPO backups</h2>
$($infoBackupArchives | ConvertTo-Html -Fragment | Out-String)

<h2>Summary of backed-up Group Policies (with GpoID and Backup-ID)</h2>
$($InfoBackupedGPOs | ConvertTo-Html -Fragment | Out-String)

<h2>Summary of backed-up Group Policies (with ModificationTime)</h2>
$($InfoBackupedGPOs2 | ConvertTo-Html -Fragment | Out-String)

</body>
</html>
"@

Write-Verbose "[PROCESS] Sending report" -Verbose
$message = New-Object System.Net.Mail.MailMessage $smtpFrom, $smtpTo
$message.Subject = $messageSubject
$message.IsBodyHTML = $true
$message.Body = $body
$smtp = New-Object Net.Mail.SmtpClient($smtpServer)
$smtp.Send($message)
$message.Dispose()

# Delete the exports
if (Test-Path $pathFolder2Backup) {
    Write-Host "[PROCESS] Temporary exports in $pathFolder2Backup are being deleted."
    Remove-Item $pathFolder2Backup -Recurse -Force
}

# Delete archives older than the configured retention period
Write-Host "[PROCESS] Archive data older than $DatetoDeleteShort is being deleted."
Get-ChildItem -Path $pathGPOArchivefiles -File | Where-Object { $_.LastWriteTime -lt $DatetoDelete } | Remove-Item -Force

Stop-Transcript