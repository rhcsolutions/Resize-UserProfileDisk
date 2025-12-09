#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Install or uninstall the Resize-UserProfileDisk Web Service
.DESCRIPTION
    This script installs the Resize-UserProfileDisk Web Service as a Windows Service using NSSM (Non-Sucking Service Manager).
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
    [string]$ServicePath = "C:\Resize-UserProfileDisk",
    
    [Parameter(Mandatory=$false)]
    [int]$Port = 8080,
    
    [Parameter(Mandatory=$false)]
    [switch]$DebugLog
)

$ErrorActionPreference = 'Stop'

# Setup logging
$logPath = Join-Path $PSScriptRoot "install-log-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to console with color
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARN" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage -ForegroundColor White }
    }
    
    # Write to log file
    Add-Content -Path $logPath -Value $logMessage
    
    # If DebugLog mode, write verbose info
    if ($DebugLog) {
        Write-Verbose $logMessage
    }
}

Write-Log "Installation script started" "INFO"
Write-Log "Action: $Action" "INFO"
Write-Log "Service Path: $ServicePath" "INFO"
Write-Log "Port: $Port" "INFO"
Write-Log "Log File: $logPath" "INFO"

# Load configuration
$configPath = Join-Path $PSScriptRoot "config.json"
Write-Log "Loading configuration from: $configPath" "INFO"

if (Test-Path $configPath) {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $ServiceName = $config.ServiceName
    $ServiceDisplayName = $config.ServiceDisplayName
    $ServiceDescription = $config.ServiceDescription
    Write-Log "Configuration loaded successfully" "SUCCESS"
    Write-Log "Service Name: $ServiceName" "INFO"
} else {
    Write-Log "Configuration file not found, using defaults" "WARN"
    $ServiceName = "Resize-UserProfileDisk"
    $ServiceDisplayName = "Resize User Profile Disk Service"
    $ServiceDescription = "Web service for managing and resizing User Profile Disk (VHDX) files"
}

function Test-Administrator {
    Write-Log "Checking administrator privileges..." "INFO"
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if ($isAdmin) {
        Write-Log "Running with administrator privileges" "SUCCESS"
    } else {
        Write-Log "NOT running with administrator privileges" "ERROR"
    }
    
    return $isAdmin
}

function Get-NSSM {
    Write-Log "Checking for NSSM..." "INFO"
    
    # Determine architecture and select appropriate NSSM executable
    $arch = if ([Environment]::Is64BitOperatingSystem) { "64-bit" } else { "32-bit" }
    Write-Log "System architecture: $arch" "INFO"
    
    $nssmFileName = if ([Environment]::Is64BitOperatingSystem) { "nssm.exe" } else { "nssm-x86.exe" }
    $nssmPath = Join-Path $PSScriptRoot $nssmFileName
    Write-Log "Looking for NSSM at: $nssmPath" "INFO"
    
    if (!(Test-Path $nssmPath)) {
        Write-Log "NSSM not found at: $nssmPath" "ERROR"
        Write-Log "The repository should include NSSM executables:" "ERROR"
        Write-Log "  - nssm.exe (64-bit)" "ERROR"
        Write-Log "  - nssm-x86.exe (32-bit)" "ERROR"
        Write-Log "Please ensure the NSSM executable is present in: $PSScriptRoot" "ERROR"
        throw "NSSM executable not found"
    }
    
    Write-Log "NSSM found at: $nssmPath ($arch)" "SUCCESS"
    return $nssmPath
}

function Install-Service {
    Write-Log "=== Installing Resize-UserProfileDisk Web Service ===" "INFO"
    
    # Check if service already exists
    Write-Log "Checking if service '$ServiceName' already exists..." "INFO"
    $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existingService) {
        Write-Log "Service already exists. Please uninstall first." "WARN"
        return
    }
    Write-Log "Service does not exist, proceeding with installation" "SUCCESS"
    
    # Create service directory
    if (!(Test-Path $ServicePath)) {
        Write-Log "Creating service directory: $ServicePath" "INFO"
        New-Item -Path $ServicePath -ItemType Directory -Force | Out-Null
        Write-Log "Service directory created" "SUCCESS"
    } else {
        Write-Log "Service directory already exists: $ServicePath" "INFO"
    }
    
    # Copy files
    Write-Log "Copying service files..." "INFO"
    
    $filesToCopy = @(
        "UPD-WebService.ps1",
        "Resize-UserProfileDisk.ps1",
        "config.json",
        "Write-Log"  # This will copy the Write-Log function file if exists
    )
    
    foreach ($file in $filesToCopy) {
        $sourcePath = Join-Path $PSScriptRoot $file
        if (Test-Path $sourcePath) {
            try {
                Copy-Item -Path $sourcePath -Destination $ServicePath -Force
                Write-Log "  Copied: $file" "SUCCESS"
            } catch {
                Write-Log "  Failed to copy $file : $_" "ERROR"
            }
        } else {
            Write-Log "  File not found (skipping): $file" "WARN"
        }
    }
    
    # Copy Web directory
    $webSource = Join-Path $PSScriptRoot "Web"
    $webDest = Join-Path $ServicePath "Web"
    if (Test-Path $webSource) {
        try {
            Copy-Item -Path $webSource -Destination $webDest -Recurse -Force
            Write-Log "  Copied: Web directory" "SUCCESS"
        } catch {
            Write-Log "  Failed to copy Web directory: $_" "ERROR"
        }
    } else {
        Write-Log "  Web directory not found" "WARN"
    }
    
    # Get NSSM path
    $nssmPath = Get-NSSM
    
    # Create service
    Write-Log "Installing Windows Service..." "INFO"
    
    $servicePsScript = Join-Path $ServicePath "UPD-WebService.ps1"
    Write-Log "Service script path: $servicePsScript" "INFO"
    
    $powershellPath = (Get-Command powershell.exe).Source
    Write-Log "PowerShell path: $powershellPath" "INFO"
    
    try {
        & $nssmPath install $ServiceName $powershellPath `
            "-ExecutionPolicy Bypass -NoProfile -File `"$servicePsScript`""
        Write-Log "Service installed successfully" "SUCCESS"
    } catch {
        Write-Log "Failed to install service: $_" "ERROR"
        throw
    }
    
    # Configure service
    Write-Log "Configuring service properties..." "INFO"
    & $nssmPath set $ServiceName DisplayName "$ServiceDisplayName"
    & $nssmPath set $ServiceName Description "$ServiceDescription"
    & $nssmPath set $ServiceName Start SERVICE_AUTO_START
    & $nssmPath set $ServiceName AppDirectory $ServicePath
    Write-Log "Service startup mode: Automatic" "SUCCESS"
    
    # Configure service recovery
    Write-Log "Configuring service recovery options..." "INFO"
    & $nssmPath set $ServiceName AppExit Default Restart
    & $nssmPath set $ServiceName AppRestartDelay 5000
    Write-Log "Recovery configured: Restart on failure with 5s delay" "SUCCESS"
    
    # Configure logging
    Write-Log "Configuring service logging..." "INFO"
    $logDir = Join-Path $ServicePath "Logs"
    if (!(Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        Write-Log "Created log directory: $logDir" "SUCCESS"
    }
    
    & $nssmPath set $ServiceName AppStdout "$logDir\service-stdout.log"
    & $nssmPath set $ServiceName AppStderr "$logDir\service-stderr.log"
    & $nssmPath set $ServiceName AppRotateFiles 1
    & $nssmPath set $ServiceName AppRotateBytes 1048576
    Write-Log "Log files configured in: $logDir" "SUCCESS"
    
    # Reserve URL for HTTP listener
    Write-Log "Reserving URL for HTTP listener..." "INFO"
    try {
        $urlReservation = "http://+:$Port/"
        Write-Log "URL reservation: $urlReservation" "INFO"
        $result = netsh http add urlacl url=$urlReservation user="NT AUTHORITY\SYSTEM" 2>&1
        Write-Log "URL reservation result: $result" "INFO"
        Write-Log "URL reservation created: $urlReservation" "SUCCESS"
    } catch {
        Write-Log "Could not create URL reservation. Service will use localhost only." "WARN"
        Write-Log "Error details: $_" "WARN"
    }
    
    # Configure firewall
    Write-Log "Configuring Windows Firewall..." "INFO"
    
    $firewallRule = Get-NetFirewallRule -DisplayName "Resize-UserProfileDisk" -ErrorAction SilentlyContinue
    if (!$firewallRule) {
        try {
            New-NetFirewallRule -DisplayName "Resize-UserProfileDisk" `
                -Direction Inbound `
                -Protocol TCP `
                -LocalPort $Port `
                -Action Allow `
                -Profile Any | Out-Null
            Write-Log "Firewall rule created for port $Port" "SUCCESS"
        } catch {
            Write-Log "Failed to create firewall rule: $_" "ERROR"
        }
    } else {
        Write-Log "Firewall rule already exists" "INFO"
    }
    
    Write-Log "=== Service installation completed ===" "SUCCESS"
    Write-Log "Service Name: $ServiceName" "INFO"
    Write-Log "Service Path: $ServicePath" "INFO"
    Write-Log "Web Interface: http://localhost:$Port" "INFO"
    Write-Log "To start the service, run: .\Install-Service.ps1 -Action Start" "INFO"
    Write-Log "Starting service and opening web browser..." "INFO"
    
    # Start the service
    try {
        Start-Service -Name $ServiceName
        Write-Log "Service started successfully" "SUCCESS"
        Start-Sleep -Seconds 3
    } catch {
        Write-Log "Failed to start service: $_" "ERROR"
        throw
    }
    
    # Open web browser
    try {
        Start-Process "http://localhost:$Port"
        Write-Log "Web browser launched" "SUCCESS"
    } catch {
        Write-Log "Failed to open web browser: $_" "WARN"
    }
}

function Uninstall-Service {
    Write-Log "=== Uninstalling Resize-UserProfileDisk Web Service ===" "INFO"
    
    # Check if service exists
    Write-Log "Checking if service exists..." "INFO"
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (!$service) {
        Write-Log "Service not found" "WARN"
        return
    }
    Write-Log "Service found: $ServiceName" "SUCCESS"
    
    # Stop service if running
    if ($service.Status -eq 'Running') {
        Write-Log "Service is running, stopping..." "INFO"
        try {
            Stop-Service -Name $ServiceName -Force
            Start-Sleep -Seconds 2
            Write-Log "Service stopped successfully" "SUCCESS"
        } catch {
            Write-Log "Failed to stop service: $_" "ERROR"
        }
    } else {
        Write-Log "Service is already stopped" "INFO"
    }
    
    # Get NSSM
    Write-Log "Looking for NSSM to remove service..." "INFO"
    $nssmPath = Join-Path $PSScriptRoot "nssm.exe"
    if (!(Test-Path $nssmPath)) {
        # Try 32-bit version
        $nssmPath = Join-Path $PSScriptRoot "nssm-x86.exe"
        if (!(Test-Path $nssmPath)) {
            Write-Log "NSSM not found. Using sc.exe..." "WARN"
            sc.exe delete $ServiceName
            Write-Log "Service uninstalled using sc.exe" "SUCCESS"
            Write-Log "Service files remain at: $ServicePath" "INFO"
            Write-Log "To remove files, delete the directory manually" "INFO"
            return
        }
    }
    Write-Log "Using NSSM at: $nssmPath" "INFO"
    
    # Remove service
    Write-Log "Removing service..." "INFO"
    try {
        & $nssmPath remove $ServiceName confirm
        Write-Log "Service removed successfully" "SUCCESS"
    } catch {
        Write-Log "Failed to remove service: $_" "ERROR"
    }
    
    # Remove firewall rule
    Write-Log "Removing firewall rule..." "INFO"
    try {
        Remove-NetFirewallRule -DisplayName "Resize-UserProfileDisk" -ErrorAction SilentlyContinue
        Write-Log "Firewall rule removed" "SUCCESS"
    } catch {
        Write-Log "No firewall rule to remove or error occurred" "INFO"
    }
    
    # Remove URL reservation
    Write-Log "Removing URL reservation..." "INFO"
    try {
        $urlReservation = "http://+:$Port/"
        $result = netsh http delete urlacl url=$urlReservation 2>&1
        Write-Log "URL reservation removed: $result" "SUCCESS"
    } catch {
        Write-Log "No URL reservation to remove or error occurred" "INFO"
    }
    
    Write-Log "=== Service uninstalled successfully ===" "SUCCESS"
    Write-Log "Service files remain at: $ServicePath" "INFO"
    Write-Log "To remove files, delete the directory manually" "INFO"
}

function Start-ServiceCommand {
    Write-Log "Starting service..." "INFO"
    try {
        Start-Service -Name $ServiceName
        Start-Sleep -Seconds 2
        $service = Get-Service -Name $ServiceName
        Write-Log "Service Status: $($service.Status)" "SUCCESS"
        Write-Log "Web Interface: http://localhost:$Port" "INFO"
        Write-Log "Opening web browser..." "INFO"
        Start-Process "http://localhost:$Port"
    } catch {
        Write-Log "Failed to start service: $_" "ERROR"
        throw
    }
}

function Stop-ServiceCommand {
    Write-Log "Stopping service..." "INFO"
    try {
        Stop-Service -Name $ServiceName -Force
        Start-Sleep -Seconds 2
        $service = Get-Service -Name $ServiceName
        Write-Log "Service Status: $($service.Status)" "SUCCESS"
    } catch {
        Write-Log "Failed to stop service: $_" "ERROR"
        throw
    }
}

function Restart-ServiceCommand {
    Write-Log "Restarting service..." "INFO"
    try {
        Restart-Service -Name $ServiceName -Force
        Start-Sleep -Seconds 2
        $service = Get-Service -Name $ServiceName
        Write-Log "Service Status: $($service.Status)" "SUCCESS"
        Write-Log "Web Interface: http://localhost:$Port" "INFO"
        Write-Log "Opening web browser..." "INFO"
        Start-Process "http://localhost:$Port"
    } catch {
        Write-Log "Failed to restart service: $_" "ERROR"
        throw
    }
}

function Get-ServiceStatus {
    Write-Log "Checking service status..." "INFO"
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    
    if (!$service) {
        Write-Log "Service Status: NOT INSTALLED" "WARN"
        return
    }
    
    Write-Log "=== Resize-UserProfileDisk Web Service Status ===" "INFO"
    Write-Log "Service Name: $($service.Name)" "INFO"
    Write-Log "Display Name: $($service.DisplayName)" "INFO"
    Write-Log "Status: $($service.Status)" $(if ($service.Status -eq 'Running') { 'SUCCESS' } else { 'WARN' })
    Write-Log "Start Type: $($service.StartType)" "INFO"
    
    if ($service.Status -eq 'Running') {
        Write-Log "Web Interface: http://localhost:$Port" "SUCCESS"
    }
}

# Main execution
Write-Log "Checking administrator privileges..." "INFO"
if (!(Test-Administrator)) {
    Write-Log "This script requires administrator privileges" "ERROR"
    Write-Log "Please run PowerShell as Administrator and try again" "ERROR"
    exit 1
}

try {
    Write-Log "Executing action: $Action" "INFO"
    switch ($Action) {
        'Install' { Install-Service }
        'Uninstall' { Uninstall-Service }
        'Start' { Start-ServiceCommand }
        'Stop' { Stop-ServiceCommand }
        'Restart' { Restart-ServiceCommand }
        'Status' { Get-ServiceStatus }
    }
    Write-Log "Action completed successfully: $Action" "SUCCESS"
}
catch {
    Write-Log "Error occurred: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}
finally {
    Write-Log "Installation script finished" "INFO"
    Write-Log "Log file saved to: $logPath" "INFO"
}
