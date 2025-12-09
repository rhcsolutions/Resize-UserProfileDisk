#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Uninstall the User Profile Disk Web Service
.DESCRIPTION
    This script removes the UPD Web Service from Windows Services.
    It's a shortcut to running: Install-Service.ps1 -Action Uninstall
.EXAMPLE
    .\Uninstall-Service.ps1
#>

Write-Host "=== Uninstalling UPD Web Service ===" -ForegroundColor Cyan
Write-Host ""

# Call the main installer with Uninstall action
& "$PSScriptRoot\Install-Service.ps1" -Action Uninstall
