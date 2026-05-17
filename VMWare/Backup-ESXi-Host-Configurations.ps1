<#
.SYNOPSIS
    Back up ESXi host configurations to a specified directory.

.DESCRIPTION
    This script checks whether VMware PowerCLI is installed. If not, the user is asked
    whether it should be installed. If the module is not installed and installation is
    declined or fails, the script aborts.

    Afterwards, the script connects to a list of ESXi hosts, retrieves their firmware
    configuration, and saves the backups in a folder named with the current date.
    Each host's backup is stored in a subfolder named after its build version.

.PARAMETER esxhosts
    An array of IP addresses or hostnames of the ESXi hosts to back up.

.PARAMETER Backupdate
    The current date in "yyyyMMdd" format, used to create the backup folder.

.PARAMETER BackupPath
    The base path where the backups will be stored, appended with the current date.

.NOTES
    Author: Tsukaito
    Date: 30.01.2025
    Version: 1.1

.REQUIREMENTS
    - VMware PowerCLI must be installed.
    - Sufficient permissions to connect to the ESXi hosts and export configurations.
    - Ensure the destination path is accessible and has sufficient storage.
#>

# Define an array of ESXi host IP addresses or hostnames
$esxhosts = "ESXHost01.trench-group.net","ESXHost02.trench-group.net","ESXHost03.trench-group.net","ESXHost04.trench-group.net"

# Get the current date in "yyyyMMdd" format to use in the backup folder name
$Backupdate = Get-Date -Format "yyyyMMdd"

# Define the base path where backups will be stored, appending the current date
$BackupPath = Join-Path "C:\temp\Config-Files\VMware" $Backupdate

# Check whether VMware PowerCLI is installed
$PowerCLIModule = Get-Module -ListAvailable -Name VMware.PowerCLI

if (-not $PowerCLIModule) {
    Write-Host "VMware PowerCLI is not installed." -ForegroundColor Yellow
    $installChoice = Read-Host "Do you want to install VMware PowerCLI now? (Y/N)"

    if ($installChoice -match '^(J|j|Y|y)$') {
        try {
            Write-Host "Installing VMware PowerCLI ..." -ForegroundColor Cyan

            # Optional: TLS 1.2 for older systems / PSGallery issues
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

            Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            Import-Module VMware.PowerCLI -ErrorAction Stop

            Write-Host "VMware PowerCLI was installed successfully." -ForegroundColor Green
        }
        catch {
            Write-Error "VMware PowerCLI could not be installed. The script will now stop. Error: $($_.Exception.Message)"
            exit 1
        }
    }
    else {
        Write-Warning "VMware PowerCLI is not installed. The script will now stop."
        exit 1
    }
}
else {
    try {
        Import-Module VMware.PowerCLI -ErrorAction Stop
        Write-Host "VMware PowerCLI is already installed." -ForegroundColor Green
    }
    catch {
        Write-Error "VMware PowerCLI is installed but could not be loaded. The script will now stop. Error: $($_.Exception.Message)"
        exit 1
    }
}

# Create backup base folder if it does not exist
if (!(Test-Path $BackupPath)) {
    New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
}

# Configure PowerCLI to ignore invalid SSL certificate warnings
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

# Loop through each ESXi host in the array
foreach ($esxhost in $esxhosts) {

    # Prompt the user to prepare for entering the ESXi root password
    Write-Host "Please press any key when you are ready to enter the ESXi root password..."
    Pause

    try {
        # Connect to the current ESXi host using root credentials
        $connect = Connect-VIServer -Server $esxhost -ErrorAction Stop

        # Retrieve the version and build number of the connected host
        $Build = "$($connect.Version).$($connect.Build)"

        # Create a subfolder for this host's backup, named with its version and build number
        $BackupPathVersion = Join-Path $BackupPath "$esxhost ($Build)"
        if (!(Test-Path $BackupPathVersion)) {
            New-Item -Path $BackupPathVersion -ItemType Directory -Force | Out-Null
        }

        # Export the firmware configuration of the ESXi host to the specified backup folder
        Get-VMHostFirmware -VMHost $esxhost -BackupConfiguration -DestinationPath $BackupPathVersion -ErrorAction Stop

        Write-Host "Backup for $esxhost completed successfully: $BackupPathVersion" -ForegroundColor Green
    }
    catch {
        Write-Error "Error on host $esxhost: $($_.Exception.Message)"
    }
    finally {
        # Disconnect from the current ESXi host if connected
        if ($global:DefaultVIServers | Where-Object { $_.Name -eq $esxhost }) {
            Disconnect-VIServer -Server $esxhost -Force -Confirm:$false | Out-Null
        }
    }
}