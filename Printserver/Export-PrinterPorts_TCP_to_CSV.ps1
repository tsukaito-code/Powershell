<# 
.NAME
    Export-PrinterPorts_TCP_to_CSV.ps1
 
.AUTHOR
    Tsukaito
 
.SYNOPSIS
    Script exports all TCP Printer Ports to a csv file.
 
.DESCRIPTION 
    Script exports all TCP Printer Ports with all settings to a csv file. In the csv file there are address, port number and smtp settings.
  
.NOTES 
    The script exports only TCP Ports, not LPR Ports (see other script).
 
.COMPONENT 
    No powershell modules needed
 
.LINK 
    No Links
  
.Parameter ParameterName 
    $CSVPath - Define export path of the csv file
#>
 
# Export CSV path
$CSVPath = "C:\Printmig\PortsTCP.csv"
 
# Get Printerports with all nessesary informations
$Printerports = Get-PrinterPort | ?{$_.Description -like "*TCP*"} | select Name, PrinterHostAddress, PortNumber, SNMPCommunity, SNMPEnabled 
 
#Export informations to CSV
$Printerports | Export-Csv -Path $CSVPath -Delimiter ";" -Encoding UTF8 -NoTypeInformation