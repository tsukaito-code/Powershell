<#
.SYNOPSIS
Triggers Active Directory replication across all domain controllers.

.DESCRIPTION
This script initiates AD replication on all domain controllers in the domain 
using repadmin /syncall. After triggering replication, it waits for 10 seconds 
and then displays replication partner status information.

.NOTES
Requirements:
- Domain Administrator privileges are required to execute replication.

.PARAMETER None
This script does not require any parameters.
#>

# Retrieve all Domain Controllers in the current domain
$DCs = (Get-ADDomainController -Filter *).Name

foreach ($DC in $DCs) {

    # Start replication for each Domain Controller
    Write-Host "Initiating replication on DC: $DC" -ForegroundColor Green
    repadmin /syncall $DC (Get-ADDomain).DistinguishedName /e /A | Out-Null
}

# Wait before checking replication status
Write-Host "Waiting 10 seconds before collecting replication status..." -BackgroundColor White -ForegroundColor Black
Start-Sleep -Seconds 10

# Display replication partner metadata
Write-Host "Retrieving replication status from all domain controllers..." -ForegroundColor Cyan

Get-ADReplicationPartnerMetadata -Target "$env:USERDNSDOMAIN" -Scope Domain |
Select-Object Server,
@{
    Name = 'Partner'
    Expression = { $_.Partner.Split(",")[-5] }
},
LastReplicationSuccess