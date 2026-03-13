<#
.SYNOPSIS
    Updates DNS Server (OptionId 6) for all DHCP reservations from CSV file

.DESCRIPTION
    This script reads IP reservations from C:\data\reservations.csv and sets 
    DNS server 192.168.100.100 for each reserved IP address in the DHCP server.
    
    CSV format expected (semicolon-separated):
    IP;Type
    192.168.1.100;Server
    192.168.1.101;Workstation

.EXAMPLE
    .\Set-DhcpDnsReservations.ps1

.NOTES
    Author: Tsukaito
    Version: 1.1
    Date: April 2025
    Requires: DHCP Server PowerShell module
    Permissions: DHCP Administrators group membership
    
    Change History:
    v1.0 - Initial version with English comments
    v1.1 - Professional header added
#>

# New IP auf DNS server 
$NewDNS = '192.168.100.100'

# Path settings
$CSVPath = "C:\data\reservations.csv"
$LogPath = "C:\data\Set_New_DHCP_Settings.log"
 
# import csv file with all IPs
$IPs = Import-Csv -Path $CSVPath -Delimiter ";" -Encoding "UTF8"
 
# write a log file
Start-Transcript -Path $LogPath
 
# loop through all imported IP addresses
foreach ($IP in $IPs){
 
    # change the OptionId 6 (DNS server) for the IPs
    Write-Host "IP:" $IP.IP "Type:" $IP.Type "- Set new DNS server:" $NewDNS
    Set-DhcpServerv4OptionValue -ReservedIP $IP.IP -OptionId 6 -Value $NewDNS -Verbose
     
}
 
#Stop log file writing
Stop-Transcript