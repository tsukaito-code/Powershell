<#
.SYNOPSIS
    Rebalances mailbox databases to their preferred servers in an Exchange DAG.

.DESCRIPTION
    This script checks all mailbox databases currently mounted on the local server.
    If a database is active on a non-preferred server, it moves the database
    back to its preferred (primary) server based on the activation preference list.

.AUTHOR
    Tsukaito

.VERSION
    1.0

.NOTES
    - Run this script from an elevated Exchange Management Shell.
    - It is designed for DAG environments to ensure database distribution balance.
    - The script operates only on databases currently hosted on the local server.
#>

# Load the Exchange Management PowerShell snap-in
Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn

# Retrieve all mailbox databases currently mounted on the local server
Get-MailboxDatabase -Server $env:COMPUTERNAME | Sort-Object Name | ForEach-Object {

    # Store database name for readability
    $db = $_.Name

    # Get the server currently hosting the active copy
    $ActiveServer = $_.Server.Name

    # Determine the preferred server based on ActivationPreference = 1
    $PreferredServer = ($_.ActivationPreference | Where-Object { $_.Value -eq 1 }).Key

    # Compare active and preferred servers
    if ($ActiveServer -ne $PreferredServer)
    {
        # Database is active on a non-preferred server
        Write-Host "$db is active on $ActiveServer but should run on $PreferredServer – INCORRECT" -ForegroundColor Red
        
        # Move the active database back to its preferred server
        Move-ActiveMailboxDatabase $db -ActivateOnServer $PreferredServer -Confirm:$false
    }
    else
    {
        # Database runs on its preferred server
        Write-Host "$db is active on $ActiveServer and correctly runs on $PreferredServer – OK" -ForegroundColor Green
    }
}
