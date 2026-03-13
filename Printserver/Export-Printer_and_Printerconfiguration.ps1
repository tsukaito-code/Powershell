<# 
.NAME
    Export-Printer_and_Printerconfiguration.ps1
 
.AUTHOR
    Tsukaito
 
.SYNOPSIS
    Script exports all network printers and printer settings.
 
.DESCRIPTION 
    Script exports all network Printers with all settings to a single csv file.
    The printer configurations are also exported in a xml file for each printer name (printername.xml)
    The export includes name, shared name, port name, driver name, location, comment und publishing information.
 
.NOTES 
    The script exports only network printers.
 
.COMPONENT 
    No powershell modules needed
 
.LINK 
    No Links
  
.Parameter ParameterName 
    $CSVPath - Define export path of the csv file
    $XMLPath - Define export path of xml file for each printer configuration
#>
# Export CSV path
$CSVPath = "C:\Printmig\Printers.csv"
$XMLPath = "C:\Printmig\"
 
# Get all printers and informtaions
$Printers = Get-Printer | ?{$_.PortName -ne "PORTPROMPT:"} | select Name, ShareName, PortName, DriverName, Location, Comment, Published, Shared
 
# Export Printers to csv
$Printers | Export-Csv -Path $CSVPath -Delimiter ";" -Encoding UTF8 -NoTypeInformation
 
Foreach ($Printer in $Printers){
 
    #Exportpaht for XML
 
    $XMLFilePath = $XMLPath + $Printer.Name + ".xml"
 
    # Export PrinterConfiguration to XML
    $GPC = get-printconfiguration -PrinterName $Printer.Name
    $GPC.PrintTicketXML | out-file $XMLFilePath
}