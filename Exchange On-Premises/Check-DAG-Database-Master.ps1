<#
.SYNOPSIS
    Checks if all mailbox databases are mounted on their preferred servers.

.DESCRIPTION
    This script loops through all mailbox databases in the Exchange environment,
    compares their current active server with the preferred server (ActivationPreference = 1),
    and reports whether each database is correctly placed or not.
    No changes are made — it only provides status information.

.AUTHOR
    Tsukaito

.VERSION
    1.0

.NOTES
    - Run this script from an elevated Exchange Management Shell.
    - It is safe to execute in production since it only checks database placement.
    - For correcting mismatches, use the accompanying "rebalance" script.
#>

# Load the Exchange Management PowerShell snap-in
Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn

# Retrieve all mailbox databases in the organization, sorted by name
Get-MailboxDatabase | Sort-Object Name | ForEach-Object {

    # Store current database name
    $db = $_.Name

    # Get the server currently hosting the active copy
    $ActiveServer = $_.Server.Name

    # Find the preferred server (ActivationPreference = 1)
    $PreferredServer = ($_.ActivationPreference | Where-Object { $_.Value -eq 1 }).Key

    # Compare active and preferred servers and output status
    if ($ActiveServer -ne $PreferredServer)
    {
        Write-Host "$db is active on $ActiveServer but should preferably run on $PreferredServer – INCORRECT" -ForegroundColor Red
    }
    else
    {
        Write-Host "$db is active on $ActiveServer and correctly runs on $PreferredServer – OK" -ForegroundColor Green
    }
}
