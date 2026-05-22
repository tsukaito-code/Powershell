<#
.SYNOPSIS
Force reinstall tool for Microsoft Intune applications.

.DESCRIPTION
This script imports a list of Intune applications from a CSV file located in the
same directory as the script. It allows the operator to select an application for
a forced reinstall by using a graphical selection window.

If the selected application appears to still be installed, the script prompts the
operator to uninstall it manually before continuing. It then removes related
registry entries from the Intune Management Extension for all detected user entries.

At the end, the script reminds the operator to restart the device and trigger a
sync in the Company Portal.

.PARAMETER None
This script does not require any parameters.
It reads the file 'Apps.csv' from the script directory.

.NOTES
This script uses $PSScriptRoot and must be executed as a PowerShell script file (*.ps1).
#>

function Write-Status {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO','OK','WARN','ERROR')]
        [string]$Level = 'INFO'
    )

    switch ($Level) {
        'INFO'  { Write-Host "[INFO ] $Message" -ForegroundColor Cyan }
        'OK'    { Write-Host "[ OK  ] $Message" -ForegroundColor Green }
        'WARN'  { Write-Host "[WARN ] $Message" -ForegroundColor Yellow }
        'ERROR' { Write-Host "[FAIL ] $Message" -ForegroundColor Red }
    }
}

try {
    Write-Status "Starting Force reinstall tool." "INFO"

    # Define the path to the CSV file in the script directory
    $csvPath = Join-Path -Path $PSScriptRoot -ChildPath 'Apps.csv'
    Write-Status "Checking CSV file path: $csvPath" "INFO"

    # Verify that the CSV file exists before importing it
    if (-not (Test-Path -Path $csvPath -PathType Leaf)) {
        throw "Required file not found: $csvPath"
    }

    Write-Status "CSV file found." "OK"

    # Import application data from the CSV file
    $Apps = Import-Csv -Path $csvPath -Delimiter ";" -ErrorAction Stop

    if (-not $Apps) {
        throw "The CSV file is empty or could not be read correctly."
    }

    Write-Status "Loaded $($Apps.Count) application entries from CSV." "OK"

    # Open a graphical selection window and return the selected application
    Write-Status "Opening application selection window." "INFO"
    $App = $Apps | Out-GridView -PassThru -Title "Select an application for forced reinstall"

    # Stop the script if no application was selected
    if (-not $App) {
        Write-Status "No application was selected. Script execution stopped." "WARN"
        return
    }

    # Retrieve the AppID of the selected application
    $AppID = $App.AppID

    if ([string]::IsNullOrWhiteSpace($AppID)) {
        throw "The selected application does not contain a valid AppID."
    }

    Write-Status "Selected application: $($App.Application)" "OK"
    Write-Status "Selected AppID: $AppID" "INFO"

    # Define the registry path for Intune Win32 application data
    $Path = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps"

    if (-not (Test-Path -Path $Path)) {
        throw "Registry path not found: $Path"
    }

    Write-Status "Verified Intune registry base path." "OK"

    # Check whether the selected application appears to be installed
    Write-Status "Checking whether the application is currently installed." "INFO"
    $pkg = Get-Package -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$($App.ShortName)*" }

    # If the application is installed, ask the operator to uninstall it manually
    if ($pkg) {
        Write-Status "$($App.Application) appears to still be installed." "WARN"
        Write-Status "Please uninstall the application now, then press any key to continue." "WARN"
        pause
    }
    else {
        Write-Status "$($App.Application) is not currently installed." "OK"
    }

    # Get all user-related subkeys below the Intune Win32Apps registry path
    Write-Status "Collecting user registry keys from Intune Management Extension." "INFO"
    $Users = (Get-ChildItem -Path $Path -ErrorAction Stop).Name | Where-Object { $_ -like "*-*-*-*-*" }

    if (-not $Users) {
        Write-Status "No matching user registry keys were found." "WARN"
    }

    # Process each detected user key
    foreach ($User in $Users) {
        try {
            Write-Status "Processing user registry branch: $User" "INFO"

            # Convert registry path from standard format to PowerShell provider format
            $Name = $User -replace "HKEY_LOCAL_MACHINE", "HKLM:"

            # Extract the user ID from the registry path
            $UserID = $User.Split("\")[-1]

            # Find application registry entries matching the selected AppID
            $Applications = Get-ChildItem -Path $Name -ErrorAction Stop | Where-Object { $_.Name -like "*$AppID*" }

            if ($Applications) {
                foreach ($Application in $Applications) {
                    $AppName = $Application.Name -replace "HKEY_LOCAL_MACHINE", "HKLM:"
                    Write-Status "Removing application registry key: $AppName" "INFO"
                    Remove-Item -Path $AppName -Recurse -Force -ErrorAction Stop
                    Write-Status "Removed application registry key successfully." "OK"
                }
            }
            else {
                Write-Status "No application registry keys found for AppID in user branch $UserID." "INFO"
            }

            # Define the GRS subkey path for the current user
            $GRSPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\$UserID\GRS"

            if (Test-Path -Path $GRSPath) {
                $GRSes = Get-ChildItem -Path $GRSPath -ErrorAction Stop

                foreach ($GRS in $GRSes) {
                    $GRSProps = $GRS | Get-ItemProperty -ErrorAction Stop
                    $Count = $GRSProps.PSObject.Properties.Count

                    # Check whether the key contains additional application-related properties
                    if ($Count -gt 5) {
                        $TotalKey = $GRSProps.PSObject.Properties.Name | Where-Object { $_ -like "*-*-*-*-*" }

                        # Remove the GRS key if it contains the selected AppID
                        if ($TotalKey -like "*$AppID*") {
                            $PathToRemove = $GRS.Name -replace "HKEY_LOCAL_MACHINE", "HKLM:"
                            Write-Status "Removing GRS registry key: $PathToRemove" "INFO"
                            Remove-Item -Path $PathToRemove -Recurse -Force -ErrorAction Stop
                            Write-Status "Removed GRS registry key successfully." "OK"
                        }
                    }
                }
            }
            else {
                Write-Status "No GRS path found for user branch $UserID." "INFO"
            }
        }
        catch {
            Write-Status "Failed to process user branch $User. Error: $($_.Exception.Message)" "ERROR"
        }
    }
}
catch {
    Write-Status "Script execution failed. Error: $($_.Exception.Message)" "ERROR"
}
finally {
    Write-Status "Force reinstall tool finished." "INFO"
    Write-Status "Please restart the computer and then run a sync in the Company Portal." "WARN"
}