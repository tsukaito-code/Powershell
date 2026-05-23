<#
.SYNOPSIS
Searches all Group Policy Objects (GPOs) in the current domain for a specific string.

.DESCRIPTION
This script searches all GPOs in the current domain and checks their XML reports
for a user-defined string. Matching GPOs are collected and displayed in a clear
summary at the end.

.PARAMETER SearchString
Optional. Defines the string to search for inside GPO reports.
If not provided, the script prompts the user for input.

.NOTES
Requirements:
- Group Policy module must be available
- Permissions to read GPOs in the domain are required
- Must be run in the context of the target domain
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$SearchString
)

try {
    if ([string]::IsNullOrWhiteSpace($SearchString)) {
        $SearchString = Read-Host -Prompt "What string do you want to search for?"
    }

    if ([string]::IsNullOrWhiteSpace($SearchString)) {
        throw "No search string was provided. Script execution stopped."
    }

    $DomainName = $env:USERDNSDOMAIN

    if ([string]::IsNullOrWhiteSpace($DomainName)) {
        throw "Could not determine the current domain from USERDNSDOMAIN."
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " GPO Search Tool" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Domain       : $DomainName" -ForegroundColor Yellow
    Write-Host "Search String: $SearchString" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "[INFO ] Loading Group Policy module..." -ForegroundColor Cyan
    Import-Module GroupPolicy -ErrorAction Stop

    Write-Host "[INFO ] Retrieving all GPOs from the domain..." -ForegroundColor Cyan
    $AllGposInDomain = Get-GPO -All -Domain $DomainName -ErrorAction Stop

    if (-not $AllGposInDomain) {
        throw "No GPOs were found in domain $DomainName."
    }

    $MatchedGPOList = New-Object System.Collections.Generic.List[string]
    $CheckedCount = 0

    Write-Host "[INFO ] Starting search..." -ForegroundColor Cyan
    Write-Host ""

    foreach ($Gpo in $AllGposInDomain) {
        $CheckedCount++

        try {
            $Report = Get-GPOReport -Guid $Gpo.Id -ReportType Xml -ErrorAction Stop

            if ($Report -match [regex]::Escape($SearchString)) {
                Write-Host "[MATCH] $($Gpo.DisplayName)" -ForegroundColor Green
                $MatchedGPOList.Add($Gpo.DisplayName)
            }
            else {
                Write-Host "[SKIP ] $($Gpo.DisplayName)" -ForegroundColor DarkGray
            }
        }
        catch {
            Write-Host "[FAIL ] Could not process GPO: $($Gpo.DisplayName)" -ForegroundColor Red
            Write-Host "        Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " Search Results" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "GPOs checked : $CheckedCount" -ForegroundColor Yellow
    Write-Host "Matches found: $($MatchedGPOList.Count)" -ForegroundColor Yellow
    Write-Host ""

    if ($MatchedGPOList.Count -gt 0) {
        foreach ($Match in $MatchedGPOList) {
            Write-Host "[FOUND] $Match" -ForegroundColor Green
        }
    }
    else {
        Write-Host "[INFO ] No matching GPOs were found." -ForegroundColor Yellow
    }
}
catch {
    Write-Host ""
    Write-Host "[ERROR] Script execution failed." -ForegroundColor Red
    Write-Host "        $($_.Exception.Message)" -ForegroundColor Red
}