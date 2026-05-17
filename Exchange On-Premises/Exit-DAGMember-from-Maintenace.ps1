<#
.SYNOPSIS
    Brings an Exchange Server out of maintenance mode.

.DESCRIPTION
    This script reactivates an Exchange DAG member after maintenance.
    It enables all server components, resumes cluster operations, re-enables
    mailbox database activation, restores mail flow, and reactivates security policies.

.AUTHOR
    Tsuakito

.VERSION
    1.0

.NOTES
    - Run this script from an elevated Exchange Management Shell.
    - It assumes the server was previously placed in maintenance mode.
    - Review output carefully to confirm that all services return to normal operation.
#>

# Reactivate all server components
Write-Host "Reactivating server components..." -ForegroundColor Cyan
Set-ServerComponentState $env:ComputerName -Component ServerWideOffline -State Active -Requester Maintenance

# Bring the cluster node back online
Write-Host "Resuming cluster node..." -ForegroundColor Cyan
Resume-ClusterNode -Name $env:ComputerName

# Reactivate mailbox databases for failback (no forced switchback)
Write-Host "Re-enabling mailbox databases for activation..." -ForegroundColor Cyan
Write-Host "No automatic failback will be triggered." -ForegroundColor Yellow
Set-MailboxServer $env:ComputerName -DatabaseCopyAutoActivationPolicy Unrestricted
Set-MailboxServer $env:ComputerName -DatabaseCopyActivationDisabledAndMoveNow $false

# Reactivate Hub Transport – mail flow resumes
Write-Host "Re-enabling Hub Transport service - mail flow resuming..." -ForegroundColor Cyan
Set-ServerComponentState $env:ComputerName -Component HubTransport -State Active -Requester Maintenance

# Re-enable Defender real-time protection and restore execution policy
Write-Host "Re-enabling Windows Defender and restoring PowerShell policy..." -ForegroundColor Cyan
Set-MpPreference -DisableRealtimeMonitoring $false
Set-ExecutionPolicy RemoteSigned -Force

# Verify if the server is back to normal mode
if ((Get-ClusterNode -Name $env:ComputerName).State -eq "Up")
{
    Write-Host "Server $env:ComputerName is now in NORMAL MODE" -ForegroundColor Green
}
else
{
    Write-Host "Server $env:ComputerName is STILL in MAINTENANCE MODE" -ForegroundColor Red
    Write-Host "Please check services and Event Logs for issues." -ForegroundColor Red
}

# Diagnostic checks for key services and components
Write-Host "###########################################################" -ForegroundColor Yellow
Write-Host "####### Diagnostic checks for critical services ###########" -ForegroundColor Yellow
Write-Host "###########################################################" -ForegroundColor Yellow
Write-Host "`n"

# Cluster node status
Write-Host "--- Cluster Node should be UP ---" -ForegroundColor Yellow
Get-ClusterNode -Name $env:ComputerName
Pause

# Test Exchange service health
Write-Host "--- Running Test-ServiceHealth ---" -ForegroundColor Yellow
Write-Host "All roles must show RequiredServicesRunning = TRUE" -ForegroundColor Yellow
Write-Host "`n"
Test-ServiceHealth | Format-Table -AutoSize
Pause

# Check all server components
Write-Host "--- Checking all server components ---" -ForegroundColor Yellow
Write-Host "All should be ACTIVE except ForwardSyncDaemon and ProvisioningRps" -ForegroundColor Yellow
Write-Host "`n"
Get-ServerComponentState $env:ComputerName | Where-Object {$_.State -ne "Active"} | Format-Table
Pause

# Display database copy status
Write-Host "--- Displaying all mailbox database copy statuses ---" -ForegroundColor Yellow
Write-Host "`n"
Get-MailboxDatabaseCopyStatus -Server $env:ComputerName | Format-Table

Write-Host "Done! Server is fully operational." -ForegroundColor Green