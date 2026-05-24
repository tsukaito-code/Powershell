<#
.SYNOPSIS
    Exports public user S/MIME certificates from Active Directory to files and imports
    the files into the GAL by binding them to the user mailbox with Set-Mailbox.

.DESCRIPTION
    This script collects issued S/MIME certificates from the internal Windows CA, exports
    matching user certificates from Active Directory to .cer files, and then imports those
    certificates into Exchange Online so they are published to the GAL.

.MODULES
    The script uses the PowerShell modules:
    - ADObjectCertificate
    - ExchangeOnlineManagement

    PowerShell Gallery reference:
    https://www.powershellgallery.com/packages/CPolydorou.ActiveDirectory/1.9.1

.PARAMETER CertPath
    File location of the exported S/MIME certificates.

.PARAMETER LogPath
    File location of the log file used for transcription.

.NOTES
    03.07.2024 (RE): Initial development of the script.

    Requirements:
    - This script should be executed on the internal Windows Certification Authority (CA)
      server, because it uses certutil to query issued certificates from the CA database.
    - The required PowerShell modules must be installed.
    - The executing account must have the necessary permissions in Active Directory,
      on the Certification Authority, and in Exchange Online.
#>

# Import required PowerShell modules
Import-Module ADObjectCertificate
Import-Module ExchangeOnlineManagement

# Parameters
$CertPath = "C:\SMIME_Push2GAL\SMIMECerts\"
$LogPath = "C:\SMIME_Push2GAL\SMIME2GAL.log"

# Fake placeholder values for demonstration purposes
$CertThumb = "A1B2C3D4E5F678901234567890ABCDEF12345678"
$AppID = "12345678-90ab-cdef-1234-567890abcdef"

Start-Transcript -Path $LogPath

# Clean up the certificate folder before starting
Write-Host "Cleaning up certificate store folder:" $CertPath
Get-ChildItem -Path $CertPath -File | Remove-Item -Confirm:$false -Force

Write-Host "### EXPORT S/MIME CERTIFICATES ###"

# Get all issued certificates from the Windows CA, limited to template UserSMIME, sorted by serial number
$issuedCerts = (certutil -out "Serial Number,User Principal Name,Request Disposition,Revocation Date,Certificate Expiration Date,Certificate Effective Date,Certificate Template,Issued Common Name,Issued Email Address" -view csv) |
    ConvertFrom-Csv |
    Where-Object {
        $_."Request Disposition" -eq "20 -- Issued" -and
        $_."Revocation Date" -eq "EMPTY" -and
        $_."Certificate Template" -like "*UserSMIME*"
    } |
    Sort-Object "Serial Number"

# Loop through all issued certificates
foreach ($cert in $issuedCerts) {

    # Get certificate details
    $SerialNumber = $cert."Serial Number"
    $CertUPN = $cert."User Principal Name"
    $ExpirationDate = $cert."Certificate Expiration Date"

    # Get all published certificates of the user from Active Directory by UPN
    $UserCerts = Get-ActiveDirectoryObjectCertificate -UserPrincipalName $CertUPN

    # Loop through all published user certificates
    foreach ($UserCert in $UserCerts) {

        # Check whether the certificate is expired
        if ((Get-Date $ExpirationDate) -lt (Get-Date)) {
            Write-Host "Certificate" $SerialNumber "was expired:" $ExpirationDate
            continue
        }
        else {
            Write-Host "Certificate" $SerialNumber "is valid:" $ExpirationDate
        }

        # Get the Active Directory user certificate with the matching serial number
        $SMIMECert = $UserCert.Certificate | Where-Object { $_.SerialNumber -eq $SerialNumber }

        # Export S/MIME certificate
        $CertFile = $CertPath + $CertUPN + ".cer"
        Write-Host "Exporting user certificate" $CertUPN "to file" $CertFile
        Export-ActiveDirectoryObjectCertificate -UserPrincipalName $CertUPN -Thumbprint $SMIMECert.Thumbprint -Path $CertFile
    }
}

Write-Host "### IMPORT S/MIME CERTIFICATES TO GAL ###"

# Connect to Exchange Online
Write-Host "Connecting to Exchange Online..."
Connect-ExchangeOnline -CertificateThumbPrint $CertThumb -AppID $AppID -Organization "contoso.onmicrosoft.com" -Verbose

# Get S/MIME certificate files from the folder
$SMIMECertFiles = Get-ChildItem -Path $CertPath -Filter "*.cer" -File
Write-Host "Found S/MIME certificate files in folder:" $SMIMECertFiles.Count

# Loop through certificate files
foreach ($SMIMECertFile in $SMIMECertFiles) {

    # Extract the UPN from the certificate file name
    $SMIMEUPN = $SMIMECertFile.Name.Substring(0, $SMIMECertFile.Name.Length - 4)
    Write-Host "Processing UPN:" $SMIMEUPN "and certificate file:" $SMIMECertFile.Name

    # Create a certificate array for GAL import
    $SMIMECert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate $SMIMECertFile.FullName
    $CertArray = New-Object System.Collections.ArrayList
    $CertArray.Insert(0, $SMIMECert.GetRawCertData())

    # Set the S/MIME certificate for the user mailbox and publish it to the GAL
    Set-Mailbox $SMIMEUPN -UserSMimeCertificate $CertArray -UserCertificate $CertArray -Verbose
    # Get-Mailbox $SMIMEUPN | Select-Object UserPrincipalName, UserSMimeCertificate, UserCertificate
}

# Clean up the certificate store folder after processing
Write-Host "Cleaning up certificate store folder after processing:" $CertPath
Get-ChildItem -Path $CertPath -File | Remove-Item -Confirm:$false -Force

Stop-Transcript