<# 
.NAME
    Create-Printerports_LPR_from_CSV.ps1
 
.AUTHOR
    Tsukaito
 
.SYNOPSIS
    Script creates all LPR Printer Ports from a csv file.
 
.DESCRIPTION 
    Script creates all LPR Printer Ports with all settings from a csv file.
    In the csv file there are name, protocol, port nubmer and printer host address.
  
.NOTES 
    With the testmode $true you can run the script without any changes. It will only show whatif
 
.COMPONENT 
    ATTENTION: You have to install the LPR printer monitor before you add the ports!
    No powershell modules needed
 
.LINK 
    No Links
  
.Parameter ParameterName 
    $CSVPath - Define import path of the csv file
    $Testmode - Defines testmode: $true = test | $false = live
#>
 
$CSVPath = "C:\Printmig\PortsLPR.csv"
$Testmode = $false
 
# Import CSV with Port Informations
$PrinterPorts = Import-CSV -Path $CSVPath -Delimiter ";"
 
# Loop through 
Foreach($Port in $PrinterPorts){
 
Write-Host "Creating Printerport "$Port.Name
 
# Check if Printerport already exists
if(!(Get-PrinterPort -Name $Port.Name -ErrorAction SilentlyContinue))
    {
        #Add-PrinterPort -Name $Port.PrinterName -PrinterHostAddress $Port.hostname -WhatIf:$Testmode
        Add-PrinterPort -PrinterName $Port.Printername -HostName $port.Hostname   -WhatIf:$Testmode
    }
}