<# 
.NAME
    Create-Printerports_TCP_from_CSV.ps1
 
.AUTHOR
    Tsukaito
 
.SYNOPSIS
    Script creates all TCP Printer Ports from a csv file.
 
.DESCRIPTION 
    Script creates all TCP Printer Ports with all settings from a csv file. In the csv file there are address, port number and smtp settings.
  
.NOTES 
    With the testmode $true you can run the script without any changes. It will only show whatif
 
.COMPONENT 
    No powershell modules needed
 
.LINK 
    No Links
  
.Parameter ParameterName 
    $CSVPath - Define import path of the csv file
    $Testmode - Defines testmode: $true = test | $false = live
#>
 
$CSVPath = "C:\Printmig\PortsTCP.csv"
$Testmode = $false
 
# Import CSV with Port Informations
$PrinterPorts = Import-CSV -Path $CSVPath -Delimiter ";"
 
# Loop through 
Foreach($Port in $PrinterPorts){
 
Write-Host "Creating Printerport $Name"
 
# Check if Printerport already exists
if(!(Get-PrinterPort -Name $Port.Name -ErrorAction SilentlyContinue))
    {
        Add-PrinterPort -Name $Port.Name -PrinterHostAddress $Port.PrinterHostAddress -PortNumber $Port.Portnumber -SNMPCommunity $Port.SNMPCommunity -SNMP $true -WhatIf:$Testmode
    }
}

