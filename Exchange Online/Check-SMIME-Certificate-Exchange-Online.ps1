<#
.SYNOPSIS
    Connects to Exchange Online and displays the S/MIME certificate issuing CA.

.DESCRIPTION
    This script checks whether the ExchangeOnlineManagement module is installed.
    If the module is missing, the user is asked whether it should be installed.
    If the installation is declined or fails, the script stops.

    The script then checks whether a connection to Exchange Online already exists.
    If no active connection is found, it connects by using Connect-ExchangeOnline.

    After the connection is available, the script retrieves the
    SMIMECertificateIssuingCA value from the Exchange Online S/MIME configuration,
    imports it into an X509Certificate2Collection, and outputs the certificate details.

.PARAMETER None
    This script does not use external parameters.

.NOTES
    Author: Tsukaito
    Date: 2025
    Version: 1.1

.REQUIREMENTS
    - PowerShell
    - ExchangeOnlineManagement module
    - Permissions to connect to Exchange Online and read S/MIME configuration
#>

# Check whether the Exchange Online module is installed
$ExoModule = Get-Module -ListAvailable -Name ExchangeOnlineManagement

if (-not $ExoModule) {
    Write-Host "ExchangeOnlineManagement is not installed." -ForegroundColor Yellow
    $installChoice = Read-Host "Do you want to install ExchangeOnlineManagement now? (Y/N)"

    if ($installChoice -match '^(Y|y|J|j)$') {
        try {
            Write-Host "Installing ExchangeOnlineManagement ..." -ForegroundColor Cyan

            # Optional: enforce TLS 1.2 for older systems / PSGallery connectivity
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

            Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            Import-Module ExchangeOnlineManagement -ErrorAction Stop

            Write-Host "ExchangeOnlineManagement was installed successfully." -ForegroundColor Green
        }
        catch {
            Write-Error "ExchangeOnlineManagement could not be installed. The script will now stop. Error: $($_.Exception.Message)"
            exit 1
        }
    }
    else {
        Write-Warning "ExchangeOnlineManagement is not installed. The script will now stop."
        exit 1
    }
}
else {
    try {
        Import-Module ExchangeOnlineManagement -ErrorAction Stop
        Write-Host "ExchangeOnlineManagement is already installed." -ForegroundColor Green
    }
    catch {
        Write-Error "ExchangeOnlineManagement is installed but could not be loaded. The script will now stop. Error: $($_.Exception.Message)"
        exit 1
    }
}

# Check whether an active Exchange Online connection already exists
try {
    $ExistingConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like "ExchangeOnline*"
    }

    if (-not $ExistingConnection) {
        Write-Host "No active Exchange Online connection found. Connecting now ..." -ForegroundColor Yellow
        Connect-ExchangeOnline -ErrorAction Stop
        Write-Host "Connected to Exchange Online successfully." -ForegroundColor Green
    }
    else {
        Write-Host "An active Exchange Online connection already exists." -ForegroundColor Green
    }
}
catch {
    Write-Error "Could not establish a connection to Exchange Online. The script will now stop. Error: $($_.Exception.Message)"
    exit 1
}

# Retrieve the S/MIME certificate issuing CA from Exchange Online
$sst = (Get-SmimeConfig).SMIMECertificateIssuingCA

# Create an empty X.509 certificate collection
$certs = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection

# Import the certificate data into the collection
$certs.Import($sst, $null, 0)

# Output the certificate collection
$certs