#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Install or uninstall the User Profile Disk Web Service
.DESCRIPTION
    This script installs the UPD Web Service as a Windows Service using NSSM (Non-Sucking Service Manager).
    Works on Windows Server 2016 and later.
.PARAMETER Action
    Install, Uninstall, Start, Stop, or Restart the service
.EXAMPLE
    .\Install-Service.ps1 -Action Install
    .\Install-Service.ps1 -Action Uninstall
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Install', 'Uninstall', 'Start', 'Stop', 'Restart', 'Status')]
    [string]$Action,
    
    [Parameter(Mandatory=$false)]
    [string]$ServicePath = "C:\UPD-Service",
    
    [Parameter(Mandatory=$false)]
    [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'

# Load configuration
$configPath = Join-Path $PSScriptRoot "config.json"
if (Test-Path $configPath) {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $ServiceName = $config.ServiceName
    $ServiceDisplayName = $config.ServiceDisplayName
    $ServiceDescription = $config.ServiceDescription
} else {
    $ServiceName = "UPD-WebService"
    $ServiceDisplayName = "User Profile Disk Web Service"
    $ServiceDescription = "Web service for managing and resizing User Profile Disk (VHDX) files"
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-NSSM {
    Write-Host "Checking for NSSM..." -ForegroundColor Cyan
    
    $nssmPath = Join-Path $PSScriptRoot "nssm.exe"
    
    if (!(Test-Path $nssmPath)) {
        Write-Host "NSSM not found. Downloading..." -ForegroundColor Yellow
        
        $nssmUrl = "https://nssm.cc/release/nssm-2.24.zip"
        $zipPath = Join-Path $env:TEMP "nssm.zip"
        $extractPath = Join-Path $env:TEMP "nssm"
        
        try {
            # Download NSSM
            Invoke-WebRequest -Uri $nssmUrl -OutFile $zipPath -UseBasicParsing
            
            # Extract
            Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
            
            # Copy appropriate version
            $arch = if ([Environment]::Is64BitOperatingSystem) { "win64" } else { "win32" }
            $nssmExe = Get-ChildItem -Path $extractPath -Recurse -Filter "nssm.exe" | 
                Where-Object { $_.FullName -like "*\$arch\*" } | 
                Select-Object -First 1
            
            if ($nssmExe) {
                Copy-Item -Path $nssmExe.FullName -Destination $nssmPath -Force
                Write-Host "NSSM downloaded successfully" -ForegroundColor Green
            } else {
                throw "Could not find NSSM executable in download"
            }
            
            # Cleanup
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
            Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Host "Failed to download NSSM automatically." -ForegroundColor Red
            Write-Host "Please download NSSM manually from https://nssm.cc/download" -ForegroundColor Yellow
            Write-Host "Extract nssm.exe to: $PSScriptRoot" -ForegroundColor Yellow
            throw
        }
    } else {
        Write-Host "NSSM found at: $nssmPath" -ForegroundColor Green
    }
    
    return $nssmPath
}

function Install-Service {
    Write-Host "`n=== Installing UPD Web Service ===" -ForegroundColor Cyan
    
    # Check if service already exists
    $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existingService) {
        Write-Host "Service already exists. Please uninstall first." -ForegroundColor Yellow
        return
    }
    
    # Create service directory
    if (!(Test-Path $ServicePath)) {
        Write-Host "Creating service directory: $ServicePath" -ForegroundColor Cyan
        New-Item -Path $ServicePath -ItemType Directory -Force | Out-Null
    }
    
    # Copy files
    Write-Host "Copying service files..." -ForegroundColor Cyan
    
    $filesToCopy = @(
        "UPD-WebService.ps1",
        "Resize-UserProfileDisk.ps1",
        "config.json",
        "Write-Log"  # This will copy the Write-Log function file if exists
    )
    
    foreach ($file in $filesToCopy) {
        $sourcePath = Join-Path $PSScriptRoot $file
        if (Test-Path $sourcePath) {
            Copy-Item -Path $sourcePath -Destination $ServicePath -Force
            Write-Host "  Copied: $file" -ForegroundColor Gray
        }
    }
    
    # Copy Web directory
    $webSource = Join-Path $PSScriptRoot "Web"
    $webDest = Join-Path $ServicePath "Web"
    if (Test-Path $webSource) {
        Copy-Item -Path $webSource -Destination $webDest -Recurse -Force
        Write-Host "  Copied: Web directory" -ForegroundColor Gray
    }
    
    # Install NSSM
    $nssmPath = Install-NSSM
    
    # Create service
    Write-Host "Installing Windows Service..." -ForegroundColor Cyan
    
    $servicePsScript = Join-Path $ServicePath "UPD-WebService.ps1"
    $powershellPath = (Get-Command powershell.exe).Source
    
    & $nssmPath install $ServiceName $powershellPath `
        "-ExecutionPolicy Bypass -NoProfile -File `"$servicePsScript`""
    
    # Configure service
    & $nssmPath set $ServiceName DisplayName "$ServiceDisplayName"
    & $nssmPath set $ServiceName Description "$ServiceDescription"
    & $nssmPath set $ServiceName Start SERVICE_AUTO_START
    & $nssmPath set $ServiceName AppDirectory $ServicePath
    
    # Configure service recovery
    & $nssmPath set $ServiceName AppExit Default Restart
    & $nssmPath set $ServiceName AppRestartDelay 5000
    
    # Configure logging
    $logDir = Join-Path $ServicePath "Logs"
    if (!(Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    
    & $nssmPath set $ServiceName AppStdout "$logDir\service-stdout.log"
    & $nssmPath set $ServiceName AppStderr "$logDir\service-stderr.log"
    & $nssmPath set $ServiceName AppRotateFiles 1
    & $nssmPath set $ServiceName AppRotateBytes 1048576
    
    # Configure firewall
    Write-Host "Configuring Windows Firewall..." -ForegroundColor Cyan
    
    $firewallRule = Get-NetFirewallRule -DisplayName "UPD Web Service" -ErrorAction SilentlyContinue
    if (!$firewallRule) {
        New-NetFirewallRule -DisplayName "UPD Web Service" `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort $Port `
            -Action Allow `
            -Profile Any | Out-Null
        Write-Host "  Firewall rule created for port $Port" -ForegroundColor Green
    } else {
        Write-Host "  Firewall rule already exists" -ForegroundColor Gray
    }
    
    Write-Host "`nService installed successfully!" -ForegroundColor Green
    Write-Host "Service Name: $ServiceName" -ForegroundColor White
    Write-Host "Service Path: $ServicePath" -ForegroundColor White
    Write-Host "Web Interface: http://localhost:$Port" -ForegroundColor White
    Write-Host "`nTo start the service, run: .\Install-Service.ps1 -Action Start" -ForegroundColor Yellow
}

function Uninstall-Service {
    Write-Host "`n=== Uninstalling UPD Web Service ===" -ForegroundColor Cyan
    
    # Check if service exists
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (!$service) {
        Write-Host "Service not found." -ForegroundColor Yellow
        return
    }
    
    # Stop service if running
    if ($service.Status -eq 'Running') {
        Write-Host "Stopping service..." -ForegroundColor Cyan
        Stop-Service -Name $ServiceName -Force
        Start-Sleep -Seconds 2
    }
    
    # Get NSSM
    $nssmPath = Join-Path $PSScriptRoot "nssm.exe"
    if (!(Test-Path $nssmPath)) {
        Write-Host "NSSM not found. Using sc.exe..." -ForegroundColor Yellow
        sc.exe delete $ServiceName
    } else {
        # Remove service
        Write-Host "Removing service..." -ForegroundColor Cyan
        & $nssmPath remove $ServiceName confirm
    }
    
    # Remove firewall rule
    Write-Host "Removing firewall rule..." -ForegroundColor Cyan
    Remove-NetFirewallRule -DisplayName "UPD Web Service" -ErrorAction SilentlyContinue
    
    Write-Host "`nService uninstalled successfully!" -ForegroundColor Green
    Write-Host "Service files remain at: $ServicePath" -ForegroundColor White
    Write-Host "To remove files, delete the directory manually." -ForegroundColor Yellow
}

function Start-ServiceCommand {
    Write-Host "Starting service..." -ForegroundColor Cyan
    Start-Service -Name $ServiceName
    Start-Sleep -Seconds 2
    $service = Get-Service -Name $ServiceName
    Write-Host "Service Status: $($service.Status)" -ForegroundColor Green
    Write-Host "Web Interface: http://localhost:$Port" -ForegroundColor White
}

function Stop-ServiceCommand {
    Write-Host "Stopping service..." -ForegroundColor Cyan
    Stop-Service -Name $ServiceName -Force
    Start-Sleep -Seconds 2
    $service = Get-Service -Name $ServiceName
    Write-Host "Service Status: $($service.Status)" -ForegroundColor Green
}

function Restart-ServiceCommand {
    Write-Host "Restarting service..." -ForegroundColor Cyan
    Restart-Service -Name $ServiceName -Force
    Start-Sleep -Seconds 2
    $service = Get-Service -Name $ServiceName
    Write-Host "Service Status: $($service.Status)" -ForegroundColor Green
    Write-Host "Web Interface: http://localhost:$Port" -ForegroundColor White
}

function Get-ServiceStatus {
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    
    if (!$service) {
        Write-Host "`nService Status: NOT INSTALLED" -ForegroundColor Yellow
        return
    }
    
    Write-Host "`n=== UPD Web Service Status ===" -ForegroundColor Cyan
    Write-Host "Service Name: $($service.Name)" -ForegroundColor White
    Write-Host "Display Name: $($service.DisplayName)" -ForegroundColor White
    Write-Host "Status: $($service.Status)" -ForegroundColor $(if ($service.Status -eq 'Running') { 'Green' } else { 'Yellow' })
    Write-Host "Start Type: $($service.StartType)" -ForegroundColor White
    
    if ($service.Status -eq 'Running') {
        Write-Host "`nWeb Interface: http://localhost:$Port" -ForegroundColor Green
    }
}

# Main execution
if (!(Test-Administrator)) {
    Write-Host "This script requires administrator privileges." -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
    exit 1
}

try {
    switch ($Action) {
        'Install' { Install-Service }
        'Uninstall' { Uninstall-Service }
        'Start' { Start-ServiceCommand }
        'Stop' { Stop-ServiceCommand }
        'Restart' { Restart-ServiceCommand }
        'Status' { Get-ServiceStatus }
    }
}
catch {
    Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
