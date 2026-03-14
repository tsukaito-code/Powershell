<#
.SYNOPSIS
    Puts an Exchange Server into maintenance mode.

.DESCRIPTION
    This script prepares an Exchange DAG member for maintenance by disabling services,
    draining the transport queues, moving databases to other nodes, and disabling
    the cluster node. It also verifies whether the server is already in maintenance mode
    before making any changes.

.AUTHOR
    Tsukaito

.VERSION
    1.0

.NOTES
    - Run this script from an elevated Exchange Management Shell.
    - Replace <dag-member-server.domain.tld> with another DAG member’s FQDN that is online
#>

# Load the Exchange Management PowerShell snap-in
Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn

# FQDN of the DAG member to redirect mail queue if necessary (must be online)
$DAGRedirectMember = "dag-member-server.domain.tld"

# Check if the server is already in maintenance mode
# (Cluster node not UP and no mounted databases)
if ((Get-ClusterNode -Name $env:ComputerName).State -ne "Up" -and 
    (Get-MailboxDatabaseCopyStatus -Server $env:ComputerName | Where-Object {$_.Status -eq "Mounted"}).Count -eq 0)
{
    Write-Host "Server $env:ComputerName is already in MAINTENANCE MODE" -ForegroundColor Green
    Write-Host "No changes were made..." -ForegroundColor Green
    Exit
}

# Disable security restrictions and Defender real-time protection
Write-Host "Putting server $env:ComputerName into maintenance mode..."
Write-Host "Disabling PowerShell Execution Policy and Windows Defender..."
Set-ExecutionPolicy Unrestricted -Force
Set-MpPreference -DisableRealtimeMonitoring $true
Start-Sleep -Seconds 3
Write-Host "PowerShell policy unrestricted and Defender disabled"

# Drain Hub Transport (no new mail flow)
Write-Host "Disabling Hub Transport and redirecting mail queues..."
Set-ServerComponentState $env:ComputerName -Component HubTransport -State Draining -Requester Maintenance
Start-Sleep -Seconds 5

# Redirect existing messages to another DAG member
Redirect-Message -Server $env:ComputerName -Target $DAGRedirectMember -Confirm:$false
Write-Host "Hub Transport disabled"

# Suspend the cluster node
Write-Host "Suspending Cluster Node $env:ComputerName..."
Suspend-ClusterNode -Name $env:ComputerName
Start-Sleep -Seconds 3
Write-Host "Cluster Node $env:ComputerName suspended"

# Move active mailbox databases away from this server
Write-Host "Evacuating active mailbox databases..."
Set-MailboxServer $env:ComputerName -DatabaseCopyActivationDisabledAndMoveNow $true
Set-MailboxServer $env:ComputerName -DatabaseCopyAutoActivationPolicy Blocked

Write-Host "Waiting until database evacuation finishes - check interval: 30 seconds"
while ((Get-MailboxDatabaseCopyStatus -Server $env:ComputerName | Where-Object {$_.Status -eq "Mounted"}).Count -ne 0) {
    Start-Sleep -Seconds 30
}
Write-Host "All mailbox databases have been evacuated - no active copies remain on $env:ComputerName"

# Disable all server components
Set-ServerComponentState $env:ComputerName -Component ServerWideOffline -State Inactive -Requester Maintenance
Write-Host "All server components have been deactivated"

# Final verification - check if maintenance mode is active
if ((Get-ClusterNode -Name $env:ComputerName).State -ne "Up" -and 
    (Get-MailboxDatabaseCopyStatus -Server $env:ComputerName | Where-Object {$_.Status -eq "Mounted"}).Count -eq 0)
{
    Write-Host "Server $env:ComputerName is in MAINTENANCE MODE" -ForegroundColor Green
}
else
{
    Write-Host "Server $env:ComputerName is NOT in MAINTENANCE MODE" -ForegroundColor Red
    Write-Host "Please review service and command outputs for errors" -ForegroundColor Red
}
