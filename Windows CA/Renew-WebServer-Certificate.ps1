<#
.SYNOPSIS
    Requests a new certificate from an internal CA using an existing certificate or manual input.

.DESCRIPTION
    This script generates a certificate signing request (CSR) based on either:
    - An existing certificate in the local certificate store (import mode)
    - Manually specified subject fields (manual mode)

    The CSR is submitted to a Microsoft CA using the specified template.
    Optionally, the issued certificate can be exported as a PFX file.

.NOTES
    Author  : Tsukaito
    Date    : 23.04.2026
    Version : 1.2
    Requires: Administrator privileges, certreq.exe, Enroll permission on CA template
#>

# ============================================================
# Mode selection: "manual" or "import"
# ============================================================
$Mode = "import"   # "manual" = fill in fields manually
                   # "import" = read from existing certificate

# ============================================================
# Import mode – certificate store location
# ============================================================
$SourceStore  = "LocalMachine\My"   # e.g. LocalMachine\My, LocalMachine\WebHosting

# ============================================================
# Manual mode – fill in subject fields manually
# ============================================================
$CommonName   = "webserver.domain.tld"
$FriendlyName = $CommonName
$Org          = "Company"
$OrgUnit      = "IT"
$City         = "New York"
$Country      = "US"
$EMail        = "system.owner@domain.tld"
$SANs         = @("webserver.domain.tld", "other-url.domain.tld")   # e.g. @("myserver.domain.com", "192.168.1.100")

# ============================================================
# CA & Template – always required
# ============================================================
$CAName        = "Server.domain.tld\Company Issuing CA"
$Template      = "WebServerTemplate"
$OutputBaseDir = "C:\Temp\CertRequest"
# ============================================================


# ---------------------------------------------------------------
# IMPORT MODE: Read certificate data from the local store
# ---------------------------------------------------------------
if ($Mode -eq "import") {

    $SourceSerial = Read-Host -Prompt "Please enter certificate serial number" # Serial number (no spaces)
    # Open the specified certificate store
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
        ($SourceStore -split "\\")[1],
        ($SourceStore -split "\\")[0]
    )
    $store.Open("ReadOnly")

    # Find certificate by serial number
    $srcCert = $store.Certificates | Where-Object {
        $_.SerialNumber -eq $SourceSerial.ToUpper().Replace(" ","")
    }
    $store.Close()

    if (-not $srcCert) {
        Write-Error "No certificate with serial number '$SourceSerial' found in '$SourceStore'."
        exit 1
    }

    Write-Host "`nCertificate found:" -ForegroundColor Cyan
    Write-Host "  Subject      : $($srcCert.Subject)"
    Write-Host "  Friendly Name: $($srcCert.FriendlyName)"
    Write-Host "  Valid until  : $($srcCert.NotAfter)"

    # Parse subject fields into a hashtable
    $subjectFields = @{}
    $srcCert.Subject -split ",\s*" | ForEach-Object {
        $parts = $_ -split "=", 2
        if ($parts.Count -eq 2) { $subjectFields[$parts[0].Trim()] = $parts[1].Trim() }
    }

    $CommonName   = $subjectFields["CN"]
    $EMail        = $subjectFields["E"]
    $Org          = $subjectFields["O"]
    $OrgUnit      = $subjectFields["OU"]
    $City         = $subjectFields["L"]
    $Country      = $subjectFields["C"]
    $FriendlyName = $srcCert.FriendlyName

    # Extract Subject Alternative Names (DNS and IP)
    $sanExt = $srcCert.Extensions | Where-Object { $_.Oid.FriendlyName -eq "Subject Alternative Name" }
    if ($sanExt) {
        $SANs = $sanExt.Format($false) -split ",\s*" | ForEach-Object {
            if ($_ -match "^DNS Name=(.+)$")        { $matches[1].Trim() }
            elseif ($_ -match "^IP Address=(.+)$")  { $matches[1].Trim() }
        } | Where-Object { $_ }
    }

    Write-Host "  SANs         : $($SANs -join ', ')"

    # Prompt for any fields that are empty after import
    Write-Host "`nPlease provide missing fields (press Enter to leave optional fields empty):" -ForegroundColor Yellow
    if (-not $CommonName)   { $CommonName   = Read-Host "  Common Name (CN)" }
    if (-not $FriendlyName) { $FriendlyName = Read-Host "  Friendly Name     (empty = use CN)" }
    if (-not $FriendlyName) { $FriendlyName = $CommonName }   # Fall back to CN if still empty
    if (-not $Org)          { $Org          = Read-Host "  Organisation (O)" }
    if (-not $OrgUnit)      { $OrgUnit      = Read-Host "  Organisational Unit (OU)" }
    if (-not $City)         { $City         = Read-Host "  City (L)" }
    if (-not $Country)      { $Country      = Read-Host "  Country (C, 2-letter code)" }
    if (-not $EMail)        { $EMail        = Read-Host "  E-Mail (E)" }
    if ($SANs.Count -eq 0) {
        $sanInput = Read-Host "  SANs (comma-separated, e.g. server.domain.com, 192.168.1.1)"
        if ($sanInput) { $SANs = $sanInput -split "\s*,\s*" }
    }
}


# ---------------------------------------------------------------
# Create output directory named after the Common Name
# ---------------------------------------------------------------
$safeCN    = $CommonName -replace '[\\/:*?"<>|]', '_'
$OutputDir = Join-Path $OutputBaseDir $safeCN
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
Write-Host "`nOutput directory : $OutputDir" -ForegroundColor Cyan


# ---------------------------------------------------------------
# Build the subject distinguished name (DN)
# ---------------------------------------------------------------
$subjectParts = @("CN=$CommonName")
if ($OrgUnit) { $subjectParts += "OU=$OrgUnit" }
if ($EMail)   { $subjectParts += "E=$EMail" }
if ($Org)     { $subjectParts += "O=$Org" }
if ($City)    { $subjectParts += "L=$City" }
if ($Country) { $subjectParts += "C=$Country" }
$Subject = $subjectParts -join ", "

Write-Host "`nValues to be used:" -ForegroundColor Yellow
Write-Host "  Subject      : $Subject"
Write-Host "  Friendly Name: $FriendlyName"
Write-Host "  SANs         : $($SANs -join ', ')"

pause


# ---------------------------------------------------------------
# Build SAN string for the INF file
# ---------------------------------------------------------------
$sanEntries = @()
foreach ($san in $SANs) {
    # Detect IP addresses vs. DNS names
    if ($san -match '^\d{1,3}(\.\d{1,3}){3}$') { $sanEntries += "ipaddress=$san" }
    else                                          { $sanEntries += "dns=$san" }
}
$sanString = $sanEntries -join "&"


# ---------------------------------------------------------------
# Define file paths
# ---------------------------------------------------------------
$InfFile = "$OutputDir\request.inf"
$ReqFile = "$OutputDir\request.req"
$CerFile = "$OutputDir\cert.cer"
$PfxFile = "$OutputDir\" + $safeCN + ".pfx"


# ---------------------------------------------------------------
# Write the INF request file
# ---------------------------------------------------------------
@"
[Version]
Signature="`$Windows NT`$"

[NewRequest]
Subject          = "$Subject"
FriendlyName     = "$FriendlyName"
KeySpec          = 1
KeyLength        = 2048
Exportable       = TRUE
MachineKeySet    = TRUE
SMIME            = False
PrivateKeyArchive= FALSE
UserProtected    = FALSE
UseExistingKeySet= FALSE
ProviderName     = "Microsoft RSA SChannel Cryptographic Provider"
ProviderType     = 12
RequestType      = PKCS10
KeyUsage         = 0xa0
HashAlgorithm    = SHA256

[EnhancedKeyUsageExtension]
OID=1.3.6.1.5.5.7.3.1   ; Server Authentication

[Extensions]
2.5.29.17 = "{text}"
_continue_ = "$sanString"

[RequestAttributes]
CertificateTemplate = $Template
"@ | Set-Content -Encoding ASCII $InfFile

Write-Host "`nINF file created : $InfFile" -ForegroundColor Cyan


# ---------------------------------------------------------------
# Generate the CSR
# ---------------------------------------------------------------
certreq -new $InfFile $ReqFile
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create CSR."; exit 1 }
Write-Host "CSR created      : $ReqFile" -ForegroundColor Cyan


# ---------------------------------------------------------------
# Submit the CSR to the CA
# ---------------------------------------------------------------
certreq -submit -config $CAName $ReqFile $CerFile
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to submit CSR to CA."; exit 1 }
Write-Host "Certificate received: $CerFile" -ForegroundColor Green


# ---------------------------------------------------------------
# Install the certificate and link the private key
# ---------------------------------------------------------------
certreq -accept $CerFile
Write-Host "Certificate installed successfully." -ForegroundColor Green


# ---------------------------------------------------------------
# Optional: Export certificate as PFX
# ---------------------------------------------------------------
$pfxPwd = Read-Host "`nPFX export password (press Enter to skip export)" -AsSecureString
if ([Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pfxPwd)) -ne "") {

    # Find the newly installed certificate by CN
    $thumb = (Get-ChildItem Cert:\LocalMachine\My |
              Where-Object { $_.Subject -match [regex]::Escape($CommonName) } |
              Sort-Object NotBefore -Descending | Select-Object -First 1).Thumbprint

    Export-PfxCertificate -Cert "Cert:\LocalMachine\My\$thumb" `
                          -FilePath $PfxFile -Password $pfxPwd | Out-Null
    Write-Host "PFX exported     : $PfxFile" -ForegroundColor Green
}