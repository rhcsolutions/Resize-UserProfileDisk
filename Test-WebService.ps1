#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Test the UPD Web Service directly without installing as a Windows Service
.DESCRIPTION
    This script runs the web service in the current PowerShell window for testing purposes.
    Press Ctrl+C to stop the service.
.EXAMPLE
    .\Test-WebService.ps1
#>

Write-Host "=== UPD Web Service Test Mode ===" -ForegroundColor Cyan
Write-Host "Starting web service in current window..." -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop the service" -ForegroundColor Yellow
Write-Host ""

# Run the web service
& "$PSScriptRoot\UPD-WebService.ps1"
