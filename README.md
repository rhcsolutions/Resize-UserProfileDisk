# User Profile Disk Management Web Service

A modern web-based service for managing and resizing Windows User Profile Disk (VHDX) files on Windows Server 2016+. Runs independently as a Windows Service without requiring Task Scheduler.

## 🌟 Features

- **Web Interface**: Modern, responsive UI for managing VHDX resize operations
- **REST API**: Full API for automation and integration
- **Real-time Monitoring**: Live job status and progress tracking
- **Structured Logging**: JSON-based error logs with web viewing
- **Independent Operation**: Runs as Windows Service using NSSM
- **Background Processing**: Non-blocking job execution
- **Auto-Recovery**: Service automatically restarts on failure
- **Space Analytics**: Track space savings across operations

## 📋 Requirements

- Windows Server 2016 or later
- PowerShell 5.1 or later
- Administrator privileges
- NSSM (included in repository)
- SDelete.exe (optional, for zero free space operations)

## 🚀 Quick Start

### 1. Installation

```powershell
# Clone or download the repository
cd C:\Path\To\Resize-UserProfileDisk

# Test the service first (optional)
.\Test-WebService.ps1

# Install as Windows Service
.\Install-Service.ps1 -Action Install

# The service will start automatically and open your browser
```

### 2. Access Web Interface

Open your browser and navigate to:

```text
http://localhost:8080
```

### 3. Create Your First Job

1. Click on the **Operations** tab
2. Enter the path to your UPD folder (e.g., `D:\UPD`)
3. Select optional operations:
   - ✅ **Defragment** - Optimize space before compacting
   - ✅ **Zero Free Space** - Use SDelete for better compression
4. Click **Start Resize Operation**
5. Monitor progress in the **Jobs** tab

## 📖 Detailed Usage

### Service Management

```powershell
# Check service status
.\Install-Service.ps1 -Action Status

# Stop the service
.\Install-Service.ps1 -Action Stop

# Restart the service
.\Install-Service.ps1 -Action Restart

# Uninstall the service
.\Uninstall-Service.ps1
# or
.\Install-Service.ps1 -Action Uninstall
```

### Configuration

Edit `config.json` to customize settings:

```json
{
  "Port": 8080,
  "LogPath": "C:\\UPD-Service\\Logs",
  "WebRoot": "C:\\UPD-Service\\Web",
  "JobHistoryPath": "C:\\UPD-Service\\JobHistory",
  "MaxConcurrentJobs": 1,
  "LogRetentionDays": 30,
  "DefaultUPDPath": "D:\\UPD"
}
```

**Important**: Restart the service after configuration changes.

### REST API Endpoints

#### Get All Jobs

```http
GET /api/jobs
```

#### Create New Job

```http
POST /api/jobs
Content-Type: application/json

{
  "path": "D:\\UPD",
  "includeTemplate": false,
  "defrag": true,
  "zeroFreeSpace": false
}
```

#### Get Job Status

```http
GET /api/jobs/{jobId}
```

#### Get Service Status

```http
GET /api/status
```

#### Get Logs

```http
GET /api/logs?count=100&severity=Error&jobId=xxx
```

### PowerShell API Examples

```powershell
# Create a new resize job
$body = @{
    path = "D:\UPD"
    defrag = $true
    zeroFreeSpace = $false
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8080/api/jobs" `
    -Method POST `
    -Body $body `
    -ContentType "application/json"

# Get job status
$jobId = "12345678-1234-1234-1234-123456789abc"
Invoke-RestMethod -Uri "http://localhost:8080/api/jobs/$jobId"

# Get recent logs
Invoke-RestMethod -Uri "http://localhost:8080/api/logs?count=50&severity=Error"
```

## 🔧 Advanced Features

### SDelete Integration

For optimal VHDX compression, download SDelete.exe:

1. Download from: <https://docs.microsoft.com/sysinternals/downloads/sdelete>
2. Extract `sdelete.exe` to service directory: `C:\UPD-Service\`
3. Enable "Zero Free Space" option in web interface

### Firewall Configuration

The installer automatically creates a firewall rule for port 8080. To use a different port:

1. Edit `config.json` and change the `Port` value
2. Update firewall rule:

   ```powershell
   Set-NetFirewallRule -DisplayName "UPD Web Service" -LocalPort 8081
   ```

3. Restart the service

### Remote Access

To access the web interface from other machines:

1. Ensure firewall allows incoming connections
2. Access via server hostname or IP:

   ```text
   http://your-server:8080
   ```

### Monitoring and Logs

**Service Logs** (JSON format):

```text
C:\UPD-Service\Logs\UPD-Service_YYYY-MM-DD.json
```

**Job History**:

```text
C:\UPD-Service\JobHistory\{jobId}.json
```

**Windows Service Logs**:

```text
C:\UPD-Service\Logs\service-stdout.log
C:\UPD-Service\Logs\service-stderr.log
```

View logs in real-time via the **Logs** tab in the web interface.

## 📊 Web Interface Overview

### Operations Tab

- Create new resize operations
- Choose between folder or single file mode
- Configure defrag and zero free space options
- View current running operation

### Jobs Tab

- View all job history
- Filter by status (Queued, Running, Completed, Failed)
- See duration, file counts, and space savings
- View detailed job information

### Logs Tab

- Real-time service logs
- Filter by severity (Error, Warning, Information, Debug)
- Filter by Job ID
- Auto-refresh every 5 seconds

### Statistics Tab

- Service uptime
- Total jobs processed
- Success/failure rates
- Current queue status

## ⚠️ Troubleshooting

### Service Won't Start

1. Check Windows Event Viewer for errors
2. Verify PowerShell execution policy:

   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
   ```

3. Check service logs in `C:\UPD-Service\Logs\`
4. Test the service manually:

   ```powershell
   .\Test-WebService.ps1
   ```

5. Check URL reservation:

   ```powershell
   netsh http show urlacl url=http://+:8080/
   ```

### Web Interface Not Loading

1. Verify service is running:

   ```powershell
   Get-Service UPD-WebService
   ```

2. Check firewall rules:

   ```powershell
   Get-NetFirewallRule -DisplayName "UPD Web Service"
   ```

3. Test local access: `http://localhost:8080`

### Jobs Fail to Start

1. Verify paths exist and are accessible
2. Check VHDX files are not in use
3. Review error logs in the Logs tab
4. Ensure administrator privileges

### High Memory Usage

- Reduce `MaxConcurrentJobs` in config.json
- Decrease log retention days
- Clear old job history manually

## 🔒 Security Considerations

- Service runs with SYSTEM privileges (required for VHDX operations)
- Web interface has no authentication by default
- For production use, consider:
  - Adding authentication middleware
  - Using HTTPS with SSL certificate
  - Restricting firewall to specific IPs
  - Running on non-standard port

## 📝 Version History

**Version 4.0** (December 2025)

- Complete rewrite as web service
- Added REST API
- Modern web interface
- Independent Windows Service operation
- Structured JSON logging
- Real-time job monitoring

**Version 3.2** (March 2020)

- Original PowerShell script version
- Command-line operation
- Task Scheduler dependency

## 👥 Credits

- Original Script: T13nn3s
- Web Service Version: T13nn3s (December 2025)
- NSSM: [nssm.cc](https://nssm.cc)
- SDelete: Microsoft Sysinternals

## 📄 License

This project is provided as-is for managing User Profile Disks in Windows Server environments.

## 🤝 Contributing

Contributions are welcome! Please submit issues or pull requests via GitHub.

## 📞 Support

For issues and questions:

- Check the troubleshooting section
- Review service logs
- Open a GitHub issue with:
  - Windows Server version
  - PowerShell version
  - Error messages from logs
  - Steps to reproduce
