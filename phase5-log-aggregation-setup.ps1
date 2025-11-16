# Phase 5: Log Aggregation Setup
# This script creates comprehensive log directory structure and configures log rotation

param(
    [string]$BaseLogPath = "C:\Logs\localai",
    [int]$RetentionDays = 30,
    [switch]$CreateScheduledTask,
    [switch]$SetupRotation
)

# Function to create log directory structure
function New-LogDirectoryStructure {
    param([string]$BasePath)

    Write-Host "Creating log directory structure at $BasePath..." -ForegroundColor Green

    $directories = @(
        "services",
        "security",
        "system",
        "monitoring",
        "backups",
        "alerts",
        "performance"
    )

    foreach ($dir in $directories) {
        $fullPath = Join-Path $BasePath $dir
        if (!(Test-Path $fullPath)) {
            New-Item -ItemType Directory -Path $fullPath -Force
            Write-Host "Created directory: $fullPath"
        }
    }

    # Create subdirectories for services
    $services = @("n8n", "supabase", "ollama", "qdrant", "neo4j", "langfuse", "searxng", "flowise", "openwebui")
    foreach ($service in $services) {
        $servicePath = Join-Path $BasePath "services\$service"
        if (!(Test-Path $servicePath)) {
            New-Item -ItemType Directory -Path $servicePath -Force
            Write-Host "Created service directory: $servicePath"
        }
    }
}

# Function to configure Docker log rotation
function Set-DockerLogRotation {
    Write-Host "Configuring Docker log rotation..." -ForegroundColor Green

    $daemonConfigPath = "$env:ProgramData\Docker\config\daemon.json"

    # Read existing daemon.json or create new one
    if (Test-Path $daemonConfigPath) {
        $daemonConfig = Get-Content $daemonConfigPath | ConvertFrom-Json
    } else {
        $daemonConfig = @{}
    }

    # Set log driver options
    $daemonConfig."log-driver" = "json-file"
    $daemonConfig."log-opts" = @{
        "max-size" = "10m"
        "max-file" = "3"
    }

    # Write back to daemon.json
    $daemonConfig | ConvertTo-Json -Depth 10 | Set-Content $daemonConfigPath -Encoding UTF8

    Write-Host "Docker log rotation configured. Restart Docker service to apply changes."
}

# Function to set up Windows Event Log custom logs
function New-CustomEventLogs {
    Write-Host "Creating custom Windows Event Logs..." -ForegroundColor Green

    $logNames = @("LocalAI-Services", "LocalAI-Security", "LocalAI-Monitoring", "LocalAI-Alerts")

    foreach ($logName in $logNames) {
        try {
            if (!(Get-WinEvent -ListLog $logName -ErrorAction SilentlyContinue)) {
                New-EventLog -LogName $logName -Source "LocalAI"
                Write-Host "Created custom event log: $logName"
            } else {
                Write-Host "Event log already exists: $logName"
            }
        } catch {
            Write-Warning "Failed to create event log $logName`: $_"
        }
    }
}

# Function to configure log rotation for custom logs
function Set-LogRotationPolicy {
    param([string]$LogPath, [int]$Days)

    Write-Host "Setting up log rotation policy for $LogPath (retention: $Days days)..." -ForegroundColor Green

    # Create PowerShell script for log rotation
    $rotationScript = @"
param([string]`$LogPath = "$LogPath", [int]`$RetentionDays = $Days)

Get-ChildItem -Path `$LogPath -Recurse -Include "*.log" | Where-Object {
    `$_.LastWriteTime -lt (Get-Date).AddDays(-`$RetentionDays)
} | Remove-Item -Force -Confirm:`$false

Write-Host "Log rotation completed for `$LogPath"
"@

    $scriptPath = "$BaseLogPath\log-rotation.ps1"
    $rotationScript | Out-File -FilePath $scriptPath -Encoding UTF8

    Write-Host "Log rotation script created: $scriptPath"
    return $scriptPath
}

# Function to create scheduled task for log management
function New-LogManagementTask {
    param([string]$RotationScriptPath)

    Write-Host "Creating scheduled task for automated log management..." -ForegroundColor Green

    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File `"$RotationScriptPath`""
        $trigger = New-ScheduledTaskTrigger -Daily -At "02:00"  # Run at 2 AM daily
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

        Register-ScheduledTask -TaskName "LocalAI-Log-Rotation" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Rotates and cleans up LocalAI logs daily"

        Write-Host "Scheduled task created for log rotation."
    } catch {
        Write-Error "Failed to create scheduled task: $_"
    }
}

# Function to implement comprehensive logging strategy
function Set-ComprehensiveLogging {
    param([string]$LogPath)

    Write-Host "Setting up comprehensive logging strategy..." -ForegroundColor Green

    # Create logging configuration file
    $loggingConfig = @"
{
    "version": "1.0",
    "logLevels": {
        "services": "INFO",
        "security": "WARN",
        "system": "INFO",
        "monitoring": "INFO",
        "alerts": "ERROR"
    },
    "logFormats": {
        "standard": "{timestamp} [{level}] {source}: {message}",
        "detailed": "{timestamp} [{level}] {source} [{thread}] {message} {stacktrace}"
    },
    "logRotation": {
        "maxSize": "10MB",
        "maxFiles": 5,
        "retentionDays": $RetentionDays
    },
    "outputs": [
        "file",
        "eventlog",
        "console"
    ]
}
"@

    $configPath = "$LogPath\logging-config.json"
    $loggingConfig | Out-File -FilePath $configPath -Encoding UTF8

    Write-Host "Logging configuration created: $configPath"
}

# Function to set up log aggregation from Docker containers
function Set-DockerLogAggregation {
    param([string]$LogPath)

    Write-Host "Setting up Docker log aggregation..." -ForegroundColor Green

    $aggregationScript = @"
# Docker Log Aggregation Script
`$LogPath = "$LogPath"
`$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
`$AggregationLog = "`$LogPath\services\docker-aggregation-`$Timestamp.log"

# Get all running containers
`$containers = docker ps --format "{{.Names}}"

foreach (`$container in `$containers) {
    try {
        `$logs = docker logs --since 24h `$container 2>&1
        if (`$logs) {
            Add-Content -Path `$AggregationLog -Value "=== Container: `$container ==="
            Add-Content -Path `$AggregationLog -Value `$logs
            Add-Content -Path `$AggregationLog -Value ""
        }
    } catch {
        Write-Warning "Failed to get logs for container `$container`: `$_"
    }
}

Write-Host "Docker log aggregation completed: `$AggregationLog"
"@

    $scriptPath = "$LogPath\docker-log-aggregation.ps1"
    $aggregationScript | Out-File -FilePath $scriptPath -Encoding UTF8

    Write-Host "Docker log aggregation script created: $scriptPath"
    return $scriptPath
}

# Main execution
New-LogDirectoryStructure -BasePath $BaseLogPath

if ($SetupRotation) {
    Set-DockerLogRotation
    New-CustomEventLogs
    $rotationScript = Set-LogRotationPolicy -LogPath $BaseLogPath -Days $RetentionDays
    Set-ComprehensiveLogging -LogPath $BaseLogPath
    $aggregationScript = Set-DockerLogAggregation -LogPath $BaseLogPath

    if ($CreateScheduledTask) {
        New-LogManagementTask -RotationScriptPath $rotationScript
    }
}

Write-Host "Log aggregation setup completed. Base log path: $BaseLogPath" -ForegroundColor Green
Write-Host "Log retention policy: $RetentionDays days"