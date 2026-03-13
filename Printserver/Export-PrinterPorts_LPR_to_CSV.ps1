<# 
.NAME
    Export-PrinterPorts_LPR_to_CSV.ps1
 
.AUTHOR
    Tsukaito
 
.SYNOPSIS
    Script exports all LPR Printer Ports to a csv file.
 
.DESCRIPTION 
    Script exports all LPR Printer Ports with all settings to a csv file. In the csv file there are name, protocol, port nubmer and printer host address.
  
.NOTES 
    The script exports only LPR Ports, not TCP Ports (see other script).
 
.COMPONENT 
    No powershell modules needed
 
.LINK 
    No Links
  
.Parameter ParameterName 
    $CSVPath - Define export path of the csv file
#>
# Export CSV path
$CSVPath = "C:\Printmig\PortsLPR.csv"
 
# Get Printerports with all nessesary informations
$Printerports = Get-PrinterPort | ?{$_.PortMonitor -eq "LPR Port"} | Select-Object Name, Protocol, PortNumber, PrinterHostAddress
 
#Export informations to CSV
$Printerports | Export-Csv -Path $CSVPath -Delimiter ";" -Encoding UTF8 -NoTypeInformation