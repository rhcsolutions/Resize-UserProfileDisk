#Requires -RunAsAdministrator
<#
.SYNOPSIS
    User Profile Disk Web Service - Self-hosted HTTP service for managing VHDX resize operations
.DESCRIPTION
    This service runs independently as a Windows Service (via NSSM) and provides:
    - Web interface for managing UPD resize operations
    - REST API for automation
    - Real-time job status monitoring
    - Structured error logging
    - Scheduled operations without Task Scheduler dependency
.NOTES
    Created by: T13nn3s
    Version: 4.0 (December 2025)
    Requires: Windows Server 2016+, Administrator privileges
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "$PSScriptRoot\config.json"
)

#region Configuration
$Global:Config = @{
    Port = 8080
    LogPath = "$PSScriptRoot\Logs"
    WebRoot = "$PSScriptRoot\Web"
    JobHistoryPath = "$PSScriptRoot\JobHistory"
    MaxConcurrentJobs = 1
    LogRetentionDays = 30
}

if (Test-Path $ConfigPath) {
    $configData = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $configData.PSObject.Properties | ForEach-Object {
        $Global:Config[$_.Name] = $_.Value
    }
}

# Ensure directories exist
@($Global:Config.LogPath, $Global:Config.WebRoot, $Global:Config.JobHistoryPath) | ForEach-Object {
    if (!(Test-Path $_)) {
        New-Item -Path $_ -ItemType Directory -Force | Out-Null
    }
}
#endregion

#region Global State
$Global:Jobs = [System.Collections.Concurrent.ConcurrentDictionary[string,object]]::new()
$Global:ServiceRunning = $true
$Global:CurrentJob = $null
#endregion

#region Logging Functions
function Write-ServiceLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('Information', 'Warning', 'Error', 'Debug')]
        [string]$Severity,
        
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$JobId = "System",
        
        [Parameter(Mandatory=$false)]
        [hashtable]$Data = @{}
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = [PSCustomObject]@{
        Timestamp = $timestamp
        JobId = $JobId
        Severity = $Severity
        Message = $Message
        Data = $Data
        MachineName = $env:COMPUTERNAME
    }
    
    # Write to daily log file
    $logFile = Join-Path $Global:Config.LogPath "UPD-Service_$(Get-Date -Format 'yyyy-MM-dd').json"
    $logEntry | ConvertTo-Json -Compress | Add-Content $logFile
    
    # Write to console
    $color = switch ($Severity) {
        'Error' { 'Red' }
        'Warning' { 'Yellow' }
        'Information' { 'Green' }
        'Debug' { 'Gray' }
    }
    Write-Host "[$timestamp] [$Severity] $Message" -ForegroundColor $color
}

function Get-RecentLogs {
    param(
        [int]$Count = 100,
        [string]$Severity = $null,
        [string]$JobId = $null
    )
    
    $logs = Get-ChildItem "$($Global:Config.LogPath)\*.json" | 
        Sort-Object LastWriteTime -Descending | 
        Select-Object -First 3 |
        ForEach-Object {
            Get-Content $_.FullName | ForEach-Object {
                try {
                    $_ | ConvertFrom-Json
                } catch {}
            }
        }
    
    if ($Severity) {
        $logs = $logs | Where-Object { $_.Severity -eq $Severity }
    }
    
    if ($JobId) {
        $logs = $logs | Where-Object { $_.JobId -eq $JobId }
    }
    
    return $logs | Select-Object -First $Count
}

function Clear-OldLogs {
    $cutoffDate = (Get-Date).AddDays(-$Global:Config.LogRetentionDays)
    Get-ChildItem "$($Global:Config.LogPath)\*.json" | 
        Where-Object { $_.LastWriteTime -lt $cutoffDate } |
        Remove-Item -Force
    
    Get-ChildItem "$($Global:Config.JobHistoryPath)\*.json" | 
        Where-Object { $_.LastWriteTime -lt $cutoffDate } |
        Remove-Item -Force
}
#endregion

#region Job Management
function New-ResizeJob {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter(Mandatory=$false)]
        [string]$SingleVhdxFile,
        
        [Parameter(Mandatory=$false)]
        [switch]$IncludeTemplate,
        
        [Parameter(Mandatory=$false)]
        [switch]$Defrag,
        
        [Parameter(Mandatory=$false)]
        [switch]$ZeroFreeSpace,
        
        [Parameter(Mandatory=$false)]
        [string]$ScheduledTime
    )
    
    $jobId = [Guid]::NewGuid().ToString()
    
    $job = [PSCustomObject]@{
        JobId = $jobId
        Status = "Queued"
        CreatedAt = Get-Date
        StartedAt = $null
        CompletedAt = $null
        Path = $Path
        SingleVhdxFile = $SingleVhdxFile
        IncludeTemplate = $IncludeTemplate.IsPresent
        Defrag = $Defrag.IsPresent
        ZeroFreeSpace = $ZeroFreeSpace.IsPresent
        ScheduledTime = $ScheduledTime
        Progress = 0
        TotalFiles = 0
        ProcessedFiles = 0
        SizeBefore = 0
        SizeAfter = 0
        Savings = 0
        Errors = @()
        Messages = @()
    }
    
    $Global:Jobs[$jobId] = $job
    
    Write-ServiceLog -Severity Information -Message "New job created" -JobId $jobId -Data @{
        Path = $Path
        SingleFile = $SingleVhdxFile
        Defrag = $Defrag.IsPresent
        ZeroFreeSpace = $ZeroFreeSpace.IsPresent
    }
    
    return $job
}

function Start-ResizeJob {
    param(
        [Parameter(Mandatory=$true)]
        [string]$JobId
    )
    
    if ($Global:CurrentJob) {
        Write-ServiceLog -Severity Warning -Message "Cannot start job - another job is running" -JobId $JobId
        return $false
    }
    
    $job = $Global:Jobs[$JobId]
    if (!$job) {
        Write-ServiceLog -Severity Error -Message "Job not found" -JobId $JobId
        return $false
    }
    
    $Global:CurrentJob = $JobId
    $job.Status = "Running"
    $job.StartedAt = Get-Date
    
    Write-ServiceLog -Severity Information -Message "Starting resize job" -JobId $JobId
    
    # Start job in background runspace
    $runspace = [powershell]::Create()
    $runspace.AddScript({
        param($JobId, $Job, $PSScriptRoot, $Config)
        
        try {
            # Import the original resize function
            . "$PSScriptRoot\Resize-UserProfileDisk.ps1"
            
            # Build parameters
            $params = @{}
            if ($Job.SingleVhdxFile) {
                $params['SingleVhdxFile'] = $Job.SingleVhdxFile
            } else {
                $params['Path'] = $Job.Path
            }
            
            if ($Job.IncludeTemplate) { $params['IncludeTemplate'] = $true }
            if ($Job.Defrag) { $params['Defrag'] = $true }
            if ($Job.ZeroFreeSpace) { $params['ZeroFreeSpace'] = $true }
            
            # Execute resize operation
            Resize-UserProfileDisk @params
            
            # Mark as completed
            $Job.Status = "Completed"
            $Job.CompletedAt = Get-Date
            
        } catch {
            $Job.Status = "Failed"
            $Job.Errors += $_.Exception.Message
            $Job.CompletedAt = Get-Date
        }
    }).AddArgument($JobId).AddArgument($job).AddArgument($PSScriptRoot).AddArgument($Global:Config)
    
    $handle = $runspace.BeginInvoke()
    
    # Monitor job completion
    Register-ObjectEvent -InputObject $runspace -EventName InvocationStateChanged -Action {
        $jobId = $Event.MessageData
        $Global:CurrentJob = $null
        
        $job = $Global:Jobs[$jobId]
        
        # Save job history
        $historyFile = Join-Path $Global:Config.JobHistoryPath "$jobId.json"
        $job | ConvertTo-Json -Depth 10 | Set-Content $historyFile
        
        Write-ServiceLog -Severity Information -Message "Job completed" -JobId $jobId -Data @{
            Status = $job.Status
            Duration = ($job.CompletedAt - $job.StartedAt).TotalMinutes
            Savings = $job.Savings
        }
    } -MessageData $JobId | Out-Null
    
    return $true
}

function Get-JobStatus {
    param([string]$JobId)
    
    if ($JobId) {
        return $Global:Jobs[$JobId]
    } else {
        return $Global:Jobs.Values | Sort-Object CreatedAt -Descending
    }
}
#endregion

#region HTTP Server
function Send-HttpResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode = 200,
        [string]$ContentType = "application/json",
        [string]$Body = ""
    )
    
    $Response.StatusCode = $StatusCode
    $Response.ContentType = "$ContentType; charset=utf-8"
    
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.OutputStream.Close()
}

function Handle-HttpRequest {
    param([System.Net.HttpListenerContext]$Context)
    
    $request = $Context.Request
    $response = $Context.Response
    
    $method = $request.HttpMethod
    $path = $request.Url.AbsolutePath
    
    Write-ServiceLog -Severity Debug -Message "$method $path"
    
    try {
        # API Routes
        switch -Regex ($path) {
            '^/api/jobs$' {
                if ($method -eq 'GET') {
                    $jobs = Get-JobStatus | Select-Object -First 50
                    Send-HttpResponse -Response $response -Body ($jobs | ConvertTo-Json -Depth 5)
                }
                elseif ($method -eq 'POST') {
                    $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                    $params = $body | ConvertFrom-Json
                    
                    $jobParams = @{
                        Path = $params.path
                    }
                    if ($params.singleFile) { $jobParams['SingleVhdxFile'] = $params.singleFile }
                    if ($params.includeTemplate) { $jobParams['IncludeTemplate'] = $true }
                    if ($params.defrag) { $jobParams['Defrag'] = $true }
                    if ($params.zeroFreeSpace) { $jobParams['ZeroFreeSpace'] = $true }
                    
                    $job = New-ResizeJob @jobParams
                    
                    if (!$params.scheduledTime) {
                        Start-ResizeJob -JobId $job.JobId
                    }
                    
                    Send-HttpResponse -Response $response -StatusCode 201 -Body ($job | ConvertTo-Json -Depth 5)
                }
                break
            }
            
            '^/api/jobs/([a-f0-9\-]+)$' {
                $jobId = $matches[1]
                $job = Get-JobStatus -JobId $jobId
                
                if ($job) {
                    Send-HttpResponse -Response $response -Body ($job | ConvertTo-Json -Depth 5)
                } else {
                    Send-HttpResponse -Response $response -StatusCode 404 -Body '{"error":"Job not found"}'
                }
                break
            }
            
            '^/api/logs$' {
                $count = if ($request.QueryString['count']) { [int]$request.QueryString['count'] } else { 100 }
                $severity = $request.QueryString['severity']
                $jobId = $request.QueryString['jobId']
                
                $logs = Get-RecentLogs -Count $count -Severity $severity -JobId $jobId
                Send-HttpResponse -Response $response -Body ($logs | ConvertTo-Json -Depth 3)
                break
            }
            
            '^/api/status$' {
                $status = @{
                    ServiceRunning = $Global:ServiceRunning
                    CurrentJob = $Global:CurrentJob
                    TotalJobs = $Global:Jobs.Count
                    QueuedJobs = ($Global:Jobs.Values | Where-Object { $_.Status -eq 'Queued' }).Count
                    RunningJobs = ($Global:Jobs.Values | Where-Object { $_.Status -eq 'Running' }).Count
                    CompletedJobs = ($Global:Jobs.Values | Where-Object { $_.Status -eq 'Completed' }).Count
                    FailedJobs = ($Global:Jobs.Values | Where-Object { $_.Status -eq 'Failed' }).Count
                    Uptime = (Get-Date) - $Global:ServiceStartTime
                }
                Send-HttpResponse -Response $response -Body ($status | ConvertTo-Json)
                break
            }
            
            '^/$' {
                # Serve main page
                $indexPath = Join-Path $Global:Config.WebRoot "index.html"
                if (Test-Path $indexPath) {
                    $content = Get-Content $indexPath -Raw
                    Send-HttpResponse -Response $response -ContentType "text/html" -Body $content
                } else {
                    Send-HttpResponse -Response $response -StatusCode 404 -Body "Index page not found"
                }
                break
            }
            
            default {
                # Serve static files
                $filePath = Join-Path $Global:Config.WebRoot $path.TrimStart('/')
                if (Test-Path $filePath) {
                    $content = Get-Content $filePath -Raw
                    $contentType = switch -Regex ($filePath) {
                        '\.html?$' { 'text/html' }
                        '\.css$' { 'text/css' }
                        '\.js$' { 'application/javascript' }
                        '\.json$' { 'application/json' }
                        default { 'text/plain' }
                    }
                    Send-HttpResponse -Response $response -ContentType $contentType -Body $content
                } else {
                    Send-HttpResponse -Response $response -StatusCode 404 -Body "Not Found"
                }
            }
        }
    }
    catch {
        Write-ServiceLog -Severity Error -Message "Request handling error: $($_.Exception.Message)"
        Send-HttpResponse -Response $response -StatusCode 500 -Body "{`"error`": `"$($_.Exception.Message)`"}"
    }
}

function Start-HttpServer {
    $Global:ServiceStartTime = Get-Date
    
    $listener = New-Object System.Net.HttpListener
    $prefix = "http://+:$($Global:Config.Port)/"
    $listener.Prefixes.Add($prefix)
    
    try {
        $listener.Start()
        Write-ServiceLog -Severity Information -Message "HTTP Server started on port $($Global:Config.Port)"
        
        while ($Global:ServiceRunning) {
            # Clean old logs periodically
            if ((Get-Date).Hour -eq 2 -and (Get-Date).Minute -eq 0) {
                Clear-OldLogs
            }
            
            # Non-blocking check for requests
            if ($listener.IsListening) {
                $contextTask = $listener.GetContextAsync()
                
                while (!$contextTask.AsyncWaitHandle.WaitOne(200)) {
                    if (!$Global:ServiceRunning) { break }
                }
                
                if ($contextTask.IsCompleted) {
                    $context = $contextTask.GetAwaiter().GetResult()
                    Handle-HttpRequest -Context $context
                }
            }
        }
    }
    catch {
        Write-ServiceLog -Severity Error -Message "HTTP Server error: $($_.Exception.Message)"
    }
    finally {
        if ($listener.IsListening) {
            $listener.Stop()
        }
        $listener.Close()
        Write-ServiceLog -Severity Information -Message "HTTP Server stopped"
    }
}
#endregion

#region Service Control
function Stop-Service {
    Write-ServiceLog -Severity Information -Message "Service shutdown initiated"
    $Global:ServiceRunning = $false
}

# Handle Ctrl+C gracefully
[Console]::TreatControlCAsInput = $false
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Stop-Service
}
#endregion

# Start the service
Write-ServiceLog -Severity Information -Message "User Profile Disk Web Service Starting"
Write-ServiceLog -Severity Information -Message "Configuration: $($Global:Config | ConvertTo-Json)"

Start-HttpServer
