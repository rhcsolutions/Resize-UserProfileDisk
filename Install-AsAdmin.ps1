# Launch Install-Service.ps1 as Administrator
$scriptPath = Join-Path $PSScriptRoot "Install-Service.ps1"
Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass", "-File `"$scriptPath`"", "-Action Install" -Verb RunAs
