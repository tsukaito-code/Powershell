<#
.SYNOPSIS
Tests Active Directory authentication for a user account.

.DESCRIPTION
This script prompts for a user name and password, then validates the supplied
credentials against Active Directory by using the
System.DirectoryServices.AccountManagement namespace.

The script can validate credentials against the current domain or an optionally
specified domain controller.

.PARAMETER User
Optional. The user name to validate. If not provided, the script prompts for credentials.

.PARAMETER Password
Optional. The password to validate. If not provided, the script prompts for credentials.

.PARAMETER Server
Optional. Specifies a domain controller to use for authentication.

.PARAMETER Domain
Optional. Specifies the Active Directory domain to use.
Default: current user domain.

.NOTES
Requirements:
- The system must be joined to the domain or be able to reach the target domain.
- The .NET assembly System.DirectoryServices.AccountManagement must be available.
- For best compatibility, use the user name in simple account name format if possible.
#>

function Test-ADAuthentication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$User,

        [Parameter(Mandatory = $false)]
        [string]$Password,

        [Parameter(Mandatory = $false)]
        [string]$Server,

        [Parameter(Mandatory = $false)]
        [string]$Domain = $env:USERDOMAIN
    )

    try {
        Write-Host "[INFO ] Loading required .NET assembly..." -ForegroundColor Cyan
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement -ErrorAction Stop

        # If user name or password was not supplied, prompt for credentials
        if ([string]::IsNullOrWhiteSpace($User) -or [string]::IsNullOrWhiteSpace($Password)) {
            Write-Host "[INFO ] Prompting for credentials..." -ForegroundColor Cyan
            $Credential = Get-Credential -Message "Enter the Active Directory credentials to validate"

            if (-not $Credential) {
                throw "No credentials were provided."
            }

            # Extract plain-text password from the credential object
            $User = $Credential.UserName
            $Password = $Credential.GetNetworkCredential().Password
        }

        # If the username was entered as DOMAIN\username, split it
        if ($User -like "*\*") {
            $UserParts = $User.Split('\', 2)
            $Domain = $UserParts[0]
            $User = $UserParts[1]
        }

        Write-Host "[INFO ] Preparing Active Directory context..." -ForegroundColor Cyan

        $ContextType = [System.DirectoryServices.AccountManagement.ContextType]::Domain
        $ArgumentList = New-Object System.Collections.ArrayList

        $null = $ArgumentList.Add($ContextType)
        $null = $ArgumentList.Add($Domain)

        if (-not [string]::IsNullOrWhiteSpace($Server)) {
            $null = $ArgumentList.Add($Server)
            Write-Host "[INFO ] Using domain controller: $Server" -ForegroundColor Yellow
        }

        $PrincipalContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext -ArgumentList $ArgumentList

        if ($null -eq $PrincipalContext) {
            throw "Could not create the Active Directory principal context."
        }

        Write-Host "[INFO ] Validating credentials for $Domain\$User ..." -ForegroundColor Cyan

        if ($PrincipalContext.ValidateCredentials($User, $Password)) {
            Write-Host "[ OK  ] $Domain\$User - Active Directory authentication successful." -ForegroundColor Green
        }
        else {
            Write-Warning "$Domain\$User - Active Directory authentication failed."
        }
    }
    catch {
        Write-Host "[FAIL ] Script execution failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        # Clear sensitive data from variables where possible
        $Password = $null
        $Credential = $null
        $PrincipalContext = $null
    }
}

# Run the authentication test
Test-ADAuthentication