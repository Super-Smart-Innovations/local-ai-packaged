# Phase 5: Performance Monitoring Setup
# This script implements comprehensive performance monitoring for all components

param(
    [string]$BaseLogPath = "C:\Logs\localai",
    [switch]$SetupResourceTracking,
    [switch]$SetupServiceResponseMonitoring,
    [switch]$SetupDatabasePerformanceMetrics,
    [switch]$SetupContainerHealthTracking,
    [int]$MonitoringIntervalSeconds = 30
)

# Function to create resource utilization tracking
function New-ResourceUtilizationTracking {
    param([string]$LogPath, [int]$IntervalSeconds)

    Write-Host "Creating resource utilization tracking..." -ForegroundColor Green

    $resourceTrackingScript = @"
param(
    [string]`$LogPath = "$LogPath",
    [int]`$IntervalSeconds = $IntervalSeconds
)

`$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
`$MetricsFile = "`$LogPath\performance\resource-metrics.csv"

# Create metrics directory and CSV header if not exists
if (!(Test-Path "`$LogPath\performance")) {
    New-Item -ItemType Directory -Path "`$LogPath\performance" -Force
}
if (!(Test-Path `$MetricsFile)) {
    "Timestamp,CPU_Usage,MEM_Usage,Disk_Read_MBps,Disk_Write_MBps,Network_Received_MBps,Network_Sent_MBps" | Out-File -FilePath `$MetricsFile -Encoding UTF8
}

# Get CPU usage
try {
    `$cpuCounter = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1
    `$cpuUsage = `$cpuCounter.CounterSamples.CookedValue.ToString("F2")
} catch {
    `$cpuUsage = "N/A"
}

# Get memory usage
try {
    `$memCounter = Get-Counter '\Memory\% Committed Bytes In Use' -SampleInterval 1 -MaxSamples 1
    `$memUsage = `$memCounter.CounterSamples.CookedValue.ToString("F2")
} catch {
    `$memUsage = "N/A"
}

# Get disk I/O
try {
    `$diskReadCounter = Get-Counter '\PhysicalDisk(_Total)\Disk Read Bytes/sec' -SampleInterval 1 -MaxSamples 1
    `$diskWriteCounter = Get-Counter '\PhysicalDisk(_Total)\Disk Write Bytes/sec' -SampleInterval 1 -MaxSamples 1
    `$diskReadMBps = ([double]`$diskReadCounter.CounterSamples.CookedValue / 1MB).ToString("F2")
    `$diskWriteMBps = ([double]`$diskWriteCounter.CounterSamples.CookedValue / 1MB).ToString("F2")
} catch {
    `$diskReadMBps = "N/A"
    `$diskWriteMBps = "N/A"
}

# Get network I/O
try {
    `$netRecvCounter = Get-Counter '\Network Interface(*)\Bytes Received/sec' -SampleInterval 1 -MaxSamples 1 | Select-Object -First 1
    `$netSentCounter = Get-Counter '\Network Interface(*)\Bytes Sent/sec' -SampleInterval 1 -MaxSamples 1 | Select-Object -First 1
    `$netRecvMBps = ([double]`$netRecvCounter.CounterSamples.CookedValue / 1MB).ToString("F2")
    `$netSentMBps = ([double]`$netSentCounter.CounterSamples.CookedValue / 1MB).ToString("F2")
} catch {
    `$netRecvMBps = "N/A"
    `$netSentMBps = "N/A"
}

# Write metrics to CSV
`$metricsLine = "`$Timestamp,`$cpuUsage,`$memUsage,`$diskReadMBps,`$diskWriteMBps,`$netRecvMBps,`$netSentMBps"
Add-Content -Path `$MetricsFile -Value `$metricsLine

# Write to log file for immediate viewing
Add-Content -Path "`$LogPath\performance\resource-tracking.log" -Value `$metricsLine

# Check for performance thresholds and alert if needed
if (`$cpuUsage -ne "N/A" -and [double]`$cpuUsage -gt 90) {
    Add-Content -Path "`$LogPath\alerts\performance-alerts.log" -Value "`$Timestamp - CRITICAL: CPU usage at `$cpuUsage%"
}
if (`$memUsage -ne "N/A" -and [double]`$memUsage -gt 95) {
    Add-Content -Path "`$LogPath\alerts\performance-alerts.log" -Value "`$Timestamp - CRITICAL: Memory usage at `$memUsage%"
}

Write-Host "Resource metrics collected at `$Timestamp"
"@

    $scriptPath = "$LogPath\resource-tracking.ps1"
    $resourceTrackingScript | Out-File -FilePath $scriptPath -Encoding UTF8

    Write-Host "Resource utilization tracking script created: $scriptPath"
    return $scriptPath
}

# Function to create service response time monitoring
function New-ServiceResponseTimeMonitoring {
    param([string]$LogPath, [int]$IntervalSeconds)

    Write-Host "Creating service response time monitoring..." -ForegroundColor Green

    $responseMonitoringScript = @"
param(
    [string]`$LogPath = "$LogPath",
    [int]`$IntervalSeconds = $IntervalSeconds
)

`$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
`$ResponseMetricsFile = "`$LogPath\performance\response-times.csv"

# Create metrics directory and CSV header if not exists
if (!(Test-Path "`$LogPath\performance")) {
    New-Item -ItemType Directory -Path "`$LogPath\performance" -Force
}
if (!(Test-Path `$ResponseMetricsFile)) {
    "Timestamp,n8n_Response_ms,OpenWebUI_Response_ms,Supabase_Response_ms,Qdrant_Response_ms,Neo4j_Response_ms" | Out-File -FilePath `$ResponseMetricsFile -Encoding UTF8
}

# Function to measure response time
function Measure-ResponseTime {
    param([string]`$Url, [string]`$ServiceName)

    try {
        `$startTime = Get-Date
        `$response = Invoke-WebRequest -Uri `$Url -TimeoutSec 10 -UseBasicParsing
        `$endTime = Get-Date
        `$responseTime = [math]::Round((`$endTime - `$startTime).TotalMilliseconds, 2)
        return `$responseTime
    } catch {
        return "ERROR"
    }
}

# Test service response times
`$n8nResponse = Measure-ResponseTime -Url "http://localhost:5678/healthz" -ServiceName "n8n"
`$openwebuiResponse = Measure-ResponseTime -Url "http://localhost:3000/api/health" -ServiceName "OpenWebUI"
`$supabaseResponse = Measure-ResponseTime -Url "http://localhost:54321/rest/v1/" -ServiceName "Supabase"
`$qdrantResponse = Measure-ResponseTime -Url "http://localhost:6333/health" -ServiceName "Qdrant"
`$neo4jResponse = Measure-ResponseTime -Url "http://localhost:7474/" -ServiceName "Neo4j"

# Write metrics to CSV
`$responseLine = "`$Timestamp,`$n8nResponse,`$openwebuiResponse,`$supabaseResponse,`$qdrantResponse,`$neo4jResponse"
Add-Content -Path `$ResponseMetricsFile -Value `$responseLine

# Write to log file
Add-Content -Path "`$LogPath\performance\response-monitoring.log" -Value `$responseLine

# Check for slow responses and alert
`$services = @(
    @{Name="n8n"; Response=`$n8nResponse; Threshold=5000},
    @{Name="OpenWebUI"; Response=`$openwebuiResponse; Threshold=3000},
    @{Name="Supabase"; Response=`$supabaseResponse; Threshold=2000},
    @{Name="Qdrant"; Response=`$qdrantResponse; Threshold=1000},
    @{Name="Neo4j"; Response=`$neo4jResponse; Threshold=2000}
)

foreach (`$service in `$services) {
    if (`$service.Response -ne "ERROR" -and [double]`$service.Response -gt `$service.Threshold) {
        Add-Content -Path "`$LogPath\alerts\performance-alerts.log" -Value "`$Timestamp - WARNING: `$(`$service.Name) response time `$(`$service.Response)ms exceeds threshold `$(`$service.Threshold)ms"
    } elseif (`$service.Response -eq "ERROR") {
        Add-Content -Path "`$LogPath\alerts\performance-alerts.log" -Value "`$Timestamp - ERROR: `$(`$service.Name) is not responding"
    }
}

Write-Host "Service response times measured at `$Timestamp"
"@

    $scriptPath = "$LogPath\response-monitoring.ps1"
    $responseMonitoringScript | Out-File -FilePath $scriptPath -Encoding UTF8

    Write-Host "Service response time monitoring script created: $scriptPath"
    return $scriptPath
}

# Function to create database performance metrics
function New-DatabasePerformanceMetrics {
    param([string]$LogPath, [int]$IntervalSeconds)

    Write-Host "Creating database performance metrics..." -ForegroundColor Green

    $dbMetricsScript = @"
param(
    [string]`$LogPath = "$LogPath",
    [int]`$IntervalSeconds = $IntervalSeconds
)

`$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
`$DbMetricsFile = "`$LogPath\performance\database-metrics.csv"

# Create metrics directory and CSV header if not exists
if (!(Test-Path "`$LogPath\performance")) {
    New-Item -ItemType Directory -Path "`$LogPath\performance" -Force
}
if (!(Test-Path `$DbMetricsFile)) {
    "Timestamp,Supabase_Connections,Supabase_Active_Queries,Neo4j_Heap_Used_MB,Neo4j_Heap_Committed_MB" | Out-File -FilePath `$DbMetricsFile -Encoding UTF8
}

# Function to get Supabase metrics (if accessible)
function Get-SupabaseMetrics {
    try {
        # This would need to be customized based on your Supabase setup
        # For now, return placeholder values
        return @{
            Connections = "N/A"
            ActiveQueries = "N/A"
        }
    } catch {
        return @{
            Connections = "ERROR"
            ActiveQueries = "ERROR"
        }
    }
}

# Function to get Neo4j metrics (if accessible)
function Get-Neo4jMetrics {
    try {
        `$neo4jResponse = Invoke-WebRequest -Uri "http://localhost:7474/db/data/" -UseBasicParsing -Credential (Get-Credential -Message "Neo4j credentials")
        # Parse heap information - this is a simplified example
        return @{
            HeapUsed = "N/A"
            HeapCommitted = "N/A"
        }
    } catch {
        return @{
            HeapUsed = "ERROR"
            HeapCommitted = "ERROR"
        }
    }
}

# Collect database metrics
`$supabaseMetrics = Get-SupabaseMetrics
`$neo4jMetrics = Get-Neo4jMetrics

# Write metrics to CSV
`$dbLine = "`$Timestamp,`$(`$supabaseMetrics.Connections),`$(`$supabaseMetrics.ActiveQueries),`$(`$neo4jMetrics.HeapUsed),`$(`$neo4jMetrics.HeapCommitted)"
Add-Content -Path `$DbMetricsFile -Value `$dbLine

# Write to log file
Add-Content -Path "`$LogPath\performance\database-monitoring.log" -Value `$dbLine

# Basic alerting for database issues
if (`$supabaseMetrics.Connections -eq "ERROR") {
    Add-Content -Path "`$LogPath\alerts\performance-alerts.log" -Value "`$Timestamp - ERROR: Cannot monitor Supabase connections"
}
if (`$neo4jMetrics.HeapUsed -eq "ERROR") {
    Add-Content -Path "`$LogPath\alerts\performance-alerts.log" -Value "`$Timestamp - ERROR: Cannot monitor Neo4j heap usage"
}

Write-Host "Database performance metrics collected at `$Timestamp"
"@

    $scriptPath = "$LogPath\database-monitoring.ps1"
    $dbMetricsScript | Out-File -FilePath $scriptPath -Encoding UTF8

    Write-Host "Database performance metrics script created: $scriptPath"
    return $scriptPath
}

# Function to create container health and restart tracking
function New-ContainerHealthTracking {
    param([string]$LogPath, [int]$IntervalSeconds)

    Write-Host "Creating container health and restart tracking..." -ForegroundColor Green

    $containerTrackingScript = @"
param(
    [string]`$LogPath = "$LogPath",
    [int]`$IntervalSeconds = $IntervalSeconds
)

`$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
`$ContainerMetricsFile = "`$LogPath\performance\container-metrics.csv"

# Create metrics directory and CSV header if not exists
if (!(Test-Path "`$LogPath\performance")) {
    New-Item -ItemType Directory -Path "`$LogPath\performance" -Force
}
if (!(Test-Path `$ContainerMetricsFile)) {
    "Timestamp,Container_Name,Status,CPU_Usage,Memory_Usage,Restart_Count,Uptime_Seconds" | Out-File -FilePath `$ContainerMetricsFile -Encoding UTF8
}

# Get container stats
try {
    `$stats = docker stats --no-stream --format "{{.Container}},{{.CPUPerc}},{{.MemUsage}}"
    `$containers = docker ps -a --format "{{.Names}},{{.Status}},{{.Restarts}}"

    foreach (`$container in (`$containers -split "`n")) {
        if (`$container -match "(.+),(.+),(.+)") {
            `$containerName = `$matches[1]
            `$status = `$matches[2]
            `$restarts = `$matches[3]

            # Get corresponding stats
            `$containerStat = `$stats | Where-Object { `$_ -match "^`$containerName," }
            if (`$containerStat) {
                `$cpu = ($containerStat -split ",")[1]
                `$mem = ($containerStat -split ",")[2]
            } else {
                `$cpu = "N/A"
                `$mem = "N/A"
            }

            # Calculate uptime in seconds (simplified)
            `$uptime = "N/A"
            if (`$status -match "Up (.+)") {
                `$uptimeMatch = `$matches[1]
                # This is a simplified calculation - could be improved
                `$uptime = "N/A"
            }

            # Write metrics to CSV
            `$containerLine = "`$Timestamp,`$containerName,`$status,`$cpu,`$mem,`$restarts,`$uptime"
            Add-Content -Path `$ContainerMetricsFile -Value `$containerLine
        }
    }

    # Write to log file
    Add-Content -Path "`$LogPath\performance\container-monitoring.log" -Value "Container metrics collected for all containers"

    # Alert on container restarts
    foreach (`$container in (`$containers -split "`n")) {
        if (`$container -match "(.+),(.+),([1-9][0-9]*)") {
            `$containerName = `$matches[1]
            `$status = `$matches[2]
            `$restarts = [int]`$matches[3]

            if (`$restarts -gt 0) {
                Add-Content -Path "`$LogPath\alerts\performance-alerts.log" -Value "`$Timestamp - WARNING: Container `$containerName has restarted `$restarts times"
            }
        }
    }

} catch {
    Add-Content -Path "`$LogPath\alerts\performance-alerts.log" -Value "`$Timestamp - ERROR: Failed to collect container metrics: `$_"
}

Write-Host "Container health metrics collected at `$Timestamp"
"@

    $scriptPath = "$LogPath\container-monitoring.ps1"
    $containerTrackingScript | Out-File -FilePath $scriptPath -Encoding UTF8

    Write-Host "Container health tracking script created: $scriptPath"
    return $scriptPath
}

# Function to create comprehensive performance monitoring script
function New-ComprehensivePerformanceMonitoring {
    param(
        [string]$LogPath,
        [int]$IntervalSeconds,
        [string[]]$ScriptPaths
    )

    Write-Host "Creating comprehensive performance monitoring script..." -ForegroundColor Green

    $comprehensiveScript = @"
param(
    [string]`$LogPath = "$LogPath",
    [int]`$IntervalSeconds = $IntervalSeconds
)

Write-Host "Starting comprehensive performance monitoring..."

# Run all performance monitoring scripts
`$scripts = @(
$(($ScriptPaths | ForEach-Object { "    `"$_`"" }) -join ",`n")
)

foreach (`$script in `$scripts) {
    if (Test-Path `$script) {
        try {
            & `$script
        } catch {
            Write-Error "Failed to run performance script `$script`: `$_"
        }
    }
}

Write-Host "Comprehensive performance monitoring cycle completed."
"@

    $scriptPath = "$LogPath\comprehensive-performance-monitoring.ps1"
    $comprehensiveScript | Out-File -FilePath $scriptPath -Encoding UTF8

    Write-Host "Comprehensive performance monitoring script created: $scriptPath"
    return $scriptPath
}

# Function to set up scheduled performance monitoring tasks
function New-ScheduledPerformanceTasks {
    param([string]$ComprehensiveScript, [int]$IntervalSeconds)

    Write-Host "Setting up scheduled performance monitoring tasks..." -ForegroundColor Green

    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File `"$ComprehensiveScript`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Seconds $IntervalSeconds) -RepetitionDuration (New-TimeSpan -Days 365)
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName "LocalAI-Performance-Monitoring" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Runs comprehensive performance monitoring every $IntervalSeconds seconds"

        Write-Host "Scheduled performance monitoring task created."
    } catch {
        Write-Error "Failed to create scheduled performance task: $_"
    }
}

# Main execution
$scriptPaths = @()

if ($SetupResourceTracking) {
    $resourceScript = New-ResourceUtilizationTracking -LogPath $BaseLogPath -IntervalSeconds $MonitoringIntervalSeconds
    $scriptPaths += $resourceScript
}

if ($SetupServiceResponseMonitoring) {
    $responseScript = New-ServiceResponseTimeMonitoring -LogPath $BaseLogPath -IntervalSeconds $MonitoringIntervalSeconds
    $scriptPaths += $responseScript
}

if ($SetupDatabasePerformanceMetrics) {
    $dbScript = New-DatabasePerformanceMetrics -LogPath $BaseLogPath -IntervalSeconds $MonitoringIntervalSeconds
    $scriptPaths += $dbScript
}

if ($SetupContainerHealthTracking) {
    $containerScript = New-ContainerHealthTracking -LogPath $BaseLogPath -IntervalSeconds $MonitoringIntervalSeconds
    $scriptPaths += $containerScript
}

if ($scriptPaths.Count -gt 0) {
    $comprehensiveScript = New-ComprehensivePerformanceMonitoring -LogPath $BaseLogPath -IntervalSeconds $MonitoringIntervalSeconds -ScriptPaths $scriptPaths
    New-ScheduledPerformanceTasks -ComprehensiveScript $comprehensiveScript -IntervalSeconds $MonitoringIntervalSeconds
}

Write-Host "Performance monitoring setup completed." -ForegroundColor Green
Write-Host "Monitoring interval: $MonitoringIntervalSeconds seconds"
Write-Host "Log path: $BaseLogPath"