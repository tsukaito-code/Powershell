<# 
.NAME
    Create-Printers_from_CSV.ps1
 
.AUTHOR
    Tsukaito
 
.SYNOPSIS
    Script creates all printers from a csv file. Config will be restored by import xml file.
 
.DESCRIPTION 
    Script creates all printers with all settings from a csv and xml file.
    With the testmode $true you can run the script without any changes. It will only show whatif
    A log file will be created
  
.NOTES 
    You have to install the printer drivers on the system before you run the script.
    printer driver names must be changed in the csv file if it differs from the original names.
    If the pritner is offline the creation will take approximal 1 mintue.
 
.COMPONENT 
    No powershell modules needed
 
.LINK 
    No Links
  
.Parameter ParameterName 
    $CSVPath - Define export path of the csv file
    $Testmode - Defines testmode: $true = test | $false = live
    $Logpath - Path for log file
#>
 
#Testmode ($true = active | $false = inactive)
$Testmode = $false
 
# CSV Import path
$CSVPath = "C:\Printmig\Printers.csv"
 
# XML import path
$XMLPath = "C:\Printmig\"
 
# Log File
$Logpath = "C:\Printmig\CreatePrinter.log"
 
#Start transciption 
Start-Transcript -Path $Logpath -Append
 
# Import Printers
$Printers = Import-Csv -Path $CSVPath -Delimiter ";"
 
 
 
foreach($Printer in $Printers){
 
    if(!(Get-Printer -Name $Printer.Name -ErrorAction SilentlyContinue))
    {
        Write-Host "Generating new pritner" $Printer.Name -ForegroundColor Green
        # If port not exists create a new one with parameters from csv import
        Add-Printer -Name $Printer.Name -PortName $Printer.Portname -DriverName $Printer.Drivername -Location $Printer.Location -Comment $Printer.Comment -WhatIf:$Testmode
        Start-Sleep -Seconds 2
 
        Write-Host "Import printer configuration from xml" $Printer.Name -ForegroundColor Green
        # If port not exists create a new one with parameters from csv import
        # Generate printer configuration path to xml file
        $XMLConfigFile = $XMLPath + $Printer.Name + ".xml"
        # Import printer configuration from xml file
        $XMLConfig = Get-Content $XMLConfigFile | Out-String
        # Set printer configuration from xml file
        Set-PrintConfiguration -PrinterName $Printer.Name -PrintTicketXml $XMLConfig -WhatIf:$Testmode
    }
}
 
Stop-Transcript