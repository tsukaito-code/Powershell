<#
.SYNOPSIS
    Signs a PowerShell script.

.DESCRIPTION
    This script signs a PowerShell script by using the user's code-signing certificate.

    The script first checks the current user's certificate store for a valid
    code-signing certificate. If no certificate is found, or if the certificate
    is expired, the script stops and displays an error message.

    If a valid certificate is found, the script signs the specified PowerShell file
    and writes a log entry to a central CSV log file.

.NOTES
    ATTENTION:
    A valid code-signing certificate must be available in the current user's
    certificate store.

.PARAMETER PSPath
    Full path to the PowerShell script that should be signed.

.PARAMETER PSSigLog
    Full path to the CSV log file used for signing documentation.

.VERSION
    2024-10-18 (RE): Use only code-signing certificate bbga8ze0
                     Write signing documentation to CSV
#>

# Parameters

# Prompt for the full path of the PowerShell script to sign
$PSPath = Read-Host "Please enter the full path of the PowerShell script"

# Remove quotation marks from the input path if present
$PSPath = ($PSPath).Replace("""", "")

# Define the log file used for code-signing documentation
$PSSigLog = "\\server\CodeSigning\PS_Codesigning.csv"

# Get the code-signing certificate from the current user's certificate store
$SigningCert = $null
$SigningCert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.Subject -like "*coding*" }
$SigSubject = ((($SigningCert.Subject).Split(","))[0]).Replace("CN=", "")

if ($SigningCert -ne $null) {

    # Code-signing certificate found -> Check whether it is still valid
    Write-Host "Code-signing certificate found:" $SigningCert.Subject -ForegroundColor Green
    Write-Host "Certificate valid until:" $SigningCert.NotAfter -ForegroundColor Green

    $CertDate = Get-Date -Date $SigningCert.NotAfter
    $DateNow = Get-Date

    if ($CertDate -lt $DateNow) {
        # Certificate is expired -> Abort
        Write-Host "The code-signing certificate is no longer valid:" $SigningCert.NotAfter -ForegroundColor Red
        Write-Host "Code signing is not possible. A new certificate is required." -ForegroundColor Red
        return
    }
    else {
        # Certificate is valid -> Continue
        Write-Host "The code-signing certificate is valid:" $SigningCert.NotAfter -ForegroundColor Green
        Write-Host "Code signing can continue." -ForegroundColor Green
    }

}
else {

    # No code-signing certificate found -> Abort
    Write-Host "No code-signing certificate was found." -ForegroundColor Red
    Write-Host "Code signing is not possible. Aborting." -ForegroundColor Red
    return
}

# Check whether the PowerShell script file exists
if (Test-Path $PSPath) {
    # Script path is valid -> Continue
    Write-Host "PowerShell script found:" $PSPath -ForegroundColor Green
    Write-Host "Signing can continue." -ForegroundColor Green
}
else {
    # Script file not found -> Abort
    Write-Host "PowerShell script not found:" $PSPath -ForegroundColor Red
    Write-Host "Please verify the path. Aborting." -ForegroundColor Red
    return
}

# Start the code-signing process
Write-Host "Start code signing of the script?"
Pause

Set-AuthenticodeSignature $PSPath -Certificate $SigningCert

# Write code-signing information to the CSV log file
$SigDate = Get-Date -Format "dd.MM.yyyy"
$SigTime = Get-Date -Format "HH:mm"
$LogText = $SigDate + ";" + $SigTime + ";" + $PSPath + ";" + $SigSubject + ";" + $SigningCert.Thumbprint + ";" + $SigningCert.NotAfter + ";" + $env:USERNAME + ";" + $env:COMPUTERNAME
$LogText | Out-File $PSSigLog -Append -Encoding utf8

Write-Host "The signing log file was written to" $PSSigLog -ForegroundColor Green