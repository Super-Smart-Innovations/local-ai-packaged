# Phase 5: Monitoring Integration Setup
# This script creates comprehensive monitoring scripts for continuous system health checking

param(
    [string]$BaseLogPath = "C:\Logs\localai",
    [switch]$CreateScheduledTasks,
    [switch]$SetupReportGeneration,
    [switch]$ConfigureAlertNotification,
    [int]$MonitoringIntervalMinutes = 5
)

# Function to create comprehensive monitoring scripts
function New-ComprehensiveMonitoringScript {
    param([string]$LogPath, [int]$IntervalMinutes)

    Write-Host "Creating comprehensive monitoring integration script..." -ForegroundColor Green

    $monitoringScript = @"
param(
    [string]`$LogPath = "$LogPath",
    [int]`$IntervalMinutes = $IntervalMinutes
)

`$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Run all monitoring checks
& "`$PSScriptRoot\phase5-container-monitoring.ps1" -LogPath "`$LogPath"

# Run health checks
& "`$PSScriptRoot\phase5-health-checks-alerts.ps1" -LogPath "`$LogPath"

# Check for alerts and send notifications
`$alertFiles = Get-ChildItem -Path "`$LogPath\alerts" -Filter "*.log" -File
`$recentAlerts = @()

foreach (`$file in `$alertFiles) {
    `$lastWrite = `$file.LastWriteTime
    `$timeDiff = (Get-Date) - `$lastWrite
    if (`$timeDiff.TotalMinutes -le `$IntervalMinutes) {
        `$content = Get-Content `$file | Select-Object -Last 5
        `$recentAlerts += `$content
    }
}

if (`$recentAlerts.Count -gt 0) {
    # Send alert notifications
    & "`$LogPath\automated-alerts.ps1"

    # Log alert summary
    `$alertSummary = "Alert Summary - `$Timestamp : `$(`$recentAlerts.Count) recent alerts detected"
    Add-Content -Path "`$LogPath\monitoring\integration.log" -Value `$alertSummary
}

# Generate status report
New-SystemStatusReport -LogPath "`$LogPath"

Write-Host "Comprehensive monitoring cycle completed at `$Timestamp"
"@

    $scriptPath = "$LogPath\comprehensive-monitoring.ps1"
    $monitoringScript | Out-File -FilePath $scriptPath -Encoding UTF8

    Write-Host "Comprehensive monitoring script created: $scriptPath"
    return $scriptPath
}

# Function to create system status report generation
function New-SystemStatusReport {
    param([string]$LogPath)

    Write-Host "Creating system status report generation..." -ForegroundColor Green

    $reportScript = @"
param([string]`$LogPath = "$LogPath")

`$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
`$ReportPath = "`$LogPath\reports\system-status-`$Timestamp.html"

# Create reports directory
if (!(Test-Path "`$LogPath\reports")) {
    New-Item -ItemType Directory -Path "`$LogPath\reports" -Force
}

# Gather system information
`$cpuUsage = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1
`$memoryUsage = Get-Counter '\Memory\% Committed Bytes In Use' -SampleInterval 1 -MaxSamples 1
`$diskUsage = Get-Counter '\LogicalDisk(_Total)\% Free Space' -SampleInterval 1 -MaxSamples 1

# Get container status
try {
    `$containers = docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | Out-String
} catch {
    `$containers = "Docker not available or no containers running"
}

# Get recent alerts
`$recentAlerts = Get-ChildItem -Path "`$LogPath\alerts" -Filter "*.log" -File | 
    Where-Object { `$_.LastWriteTime -gt (Get-Date).AddHours(-24) } |
    ForEach-Object { Get-Content `$_.FullName | Select-Object -Last 3 } |
    Out-String

# Generate HTML report
`$htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>LocalAI System Status Report - `$Timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .header { background: #2c3e50; color: white; padding: 20px; border-radius: 5px; }
        .section { background: white; margin: 20px 0; padding: 20px; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .metric { display: flex; justify-content: space-between; padding: 10px; border-bottom: 1px solid #eee; }
        .metric:last-child { border-bottom: none; }
        .value { font-weight: bold; }
        .healthy { color: #27ae60; }
        .warning { color: #f39c12; }
        .critical { color: #e74c3c; }
        .container-status { font-family: monospace; white-space: pre; background: #f8f9fa; padding: 10px; border-radius: 3px; }
        .alerts { background: #fff5f5; border-left: 4px solid #e74c3c; padding: 10px; margin: 10px 0; }
    </style>
</head>
<body>
    <div class="header">
        <h1>LocalAI System Status Report</h1>
        <p>Generated: `$Timestamp</p>
    </div>

    <div class="section">
        <h2>System Resources</h2>
        <div class="metric">
            <span>CPU Usage:</span>
            <span class="value">`$(`$cpuUsage.CounterSamples.CookedValue.ToString("F1"))%</span>
        </div>
        <div class="metric">
            <span>Memory Usage:</span>
            <span class="value">`$(`$memoryUsage.CounterSamples.CookedValue.ToString("F1"))%</span>
        </div>
        <div class="metric">
            <span>Disk Free Space:</span>
            <span class="value">`$(`$diskUsage.CounterSamples.CookedValue.ToString("F1"))%</span>
        </div>
    </div>

    <div class="section">
        <h2>Container Status</h2>
        <div class="container-status">`$containers</div>
    </div>

    <div class="section">
        <h2>Recent Alerts (Last 24h)</h2>
        <div class="alerts">
            <pre>`$recentAlerts</pre>
        </div>
    </div>

    <div class="section">
        <h2>Monitoring Status</h2>
        <div class="metric">
            <span>Monitoring Interval:</span>
            <span class="value">$IntervalMinutes minutes</span>
        </div>
        <div class="metric">
            <span>Last Check:</span>
            <span class="value healthy">`$Timestamp</span>
        </div>
    </div>
</body>
</html>
"@

`$htmlReport | Out-File -FilePath `$ReportPath -Encoding UTF8
Write-Host "System status report generated: `$ReportPath"
return `$ReportPath
"@

    $scriptPath = "$LogPath\generate-status-report.ps1"
    $reportScript | Out-File -FilePath $scriptPath -Encoding UTF8

    Write-Host "Status report generation script created: $scriptPath"
    return $scriptPath
}

# Function to create alert notification system
function New-AlertNotificationSystem {
    param([string]$LogPath)

    Write-Host "Creating alert notification system..." -ForegroundColor Green

    $notificationScript = @"
param(
    [string]`$LogPath = "$LogPath",
    [string[]]`$EmailRecipients = @("admin@yourdomain.com"),
    [string]`$SmtpServer = "smtp.gmail.com",
    [int]`$SmtpPort = 587,
    [string]`$SlackWebhookUrl = "",
    [string]`$SmsGateway = ""
)

# Check for recent alerts
`$alertFiles = Get-ChildItem -Path "`$LogPath\alerts" -Filter "*.log" -File
`$criticalAlerts = @()
`$warningAlerts = @()

foreach (`$file in `$alertFiles) {
    `$content = Get-Content `$file | Select-Object -Last 10
    `$criticalContent = `$content | Where-Object { `$_ -match "CRITICAL|FATAL" }
    `$warningContent = `$content | Where-Object { `$_ -match "WARNING|ERROR" -and `$_ -notmatch "CRITICAL|FATAL" }

    `$criticalAlerts += `$criticalContent
    `$warningAlerts += `$warningContent
}

if (`$criticalAlerts.Count -gt 0 -or `$warningAlerts.Count -gt 0) {
    `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    `$subject = "LocalAI System Alerts - `$timestamp"
    `$body = @"
LocalAI System Alert Notification

Critical Alerts: `$(`$criticalAlerts.Count)
Warning Alerts: `$(`$warningAlerts.Count)

Critical Issues:
`$(`$criticalAlerts -join "`n")

Warning Issues:
`$(`$warningAlerts -join "`n")

Time: `$timestamp
"@

    # Send email notifications
    try {
        `$smtpClient = New-Object System.Net.Mail.SmtpClient(`$SmtpServer, `$SmtpPort)
        `$smtpClient.EnableSsl = `$true
        `$smtpClient.Credentials = New-Object System.Net.NetworkCredential("your-email@gmail.com", "your-app-password")

        `$mailMessage = New-Object System.Net.Mail.MailMessage
        `$mailMessage.From = "alerts@yourdomain.com"
        `$mailMessage.Subject = `$subject
        `$mailMessage.Body = `$body

        foreach (`$recipient in `$EmailRecipients) {
            `$mailMessage.To.Add(`$recipient)
        }

        `$smtpClient.Send(`$mailMessage)
        Write-Host "Alert email sent to `$(`$EmailRecipients.Count) recipients."
    } catch {
        Write-Error "Failed to send alert email: `$_"
    }

    # Send Slack notification if webhook configured
    if (`$SlackWebhookUrl) {
        try {
            `$slackMessage = @{
                text = `$subject
                attachments = @(
                    @{
                        color = "danger"
                        text = `$body
                    }
                )
            } | ConvertTo-Json

            Invoke-RestMethod -Uri `$SlackWebhookUrl -Method Post -Body `$slackMessage -ContentType "application/json"
            Write-Host "Slack notification sent."
        } catch {
            Write-Error "Failed to send Slack notification: `$_"
        }
    }

    # Send SMS if gateway configured
    if (`$SmsGateway) {
        try {
            `$smsBody = "LocalAI Alert: `$(`$criticalAlerts.Count) critical, `$(`$warningAlerts.Count) warnings"
            # Note: Implement SMS sending logic based on your SMS gateway
            Write-Host "SMS notification would be sent to `$SmsGateway"
        } catch {
            Write-Error "Failed to send SMS notification: `$_"
        }
    }

    # Log notification
    Add-Content -Path "`$LogPath\alerts\notifications.log" -Value "`$timestamp - Notifications sent: Email(`$(`$EmailRecipients.Count)), Slack(`$(if(`$SlackWebhookUrl){"Yes"}else{"No"})), SMS(`$(if(`$SmsGateway){"Yes"}else{"No"}))"
}

Write-Host "Alert notification check completed."
"@

    $scriptPath = "$LogPath\send-alert-notifications.ps1"
    $notificationScript | Out-File -FilePath $scriptPath -Encoding UTF8

    Write-Host "Alert notification system created: $scriptPath"
    return $scriptPath
}

# Function to create monitoring dashboard creation script
function New-MonitoringDashboardCreation {
    param([string]$LogPath)

    Write-Host "Creating monitoring dashboard creation script..." -ForegroundColor Green

    $dashboardScript = @"
param([string]`$LogPath = "$LogPath")

# Create Grafana dashboard JSON
`$dashboardJson = @{
    dashboard = @{
        title = "LocalAI Comprehensive Monitoring"
        tags = @("localai", "monitoring", "comprehensive")
        timezone = "browser"
        panels = @(
            # CPU Usage Panel
            @{
                title = "CPU Usage"
                type = "graph"
                gridPos = @{ h = 8; w = 12; x = 0; y = 0 }
                targets = @(
                    @{
                        expr = "100 - (avg by(instance) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)"
                        legendFormat = "CPU Usage %"
                    }
                )
            }
            # Memory Usage Panel
            @{
                title = "Memory Usage"
                type = "graph"
                gridPos = @{ h = 8; w = 12; x = 12; y = 0 }
                targets = @(
                    @{
                        expr = "100 - ((node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100)"
                        legendFormat = "Memory Usage %"
                    }
                )
            }
            # Disk Usage Panel
            @{
                title = "Disk Usage"
                type = "graph"
                gridPos = @{ h = 8; w = 12; x = 0; y = 8 }
                targets = @(
                    @{
                        expr = "(node_filesystem_size_bytes - node_filesystem_free_bytes) / node_filesystem_size_bytes * 100"
                        legendFormat = "Disk Usage %"
                    }
                )
            }
            # Container CPU Panel
            @{
                title = "Container CPU Usage"
                type = "graph"
                gridPos = @{ h = 8; w = 12; x = 12; y = 8 }
                targets = @(
                    @{
                        expr = "rate(container_cpu_usage_seconds_total[5m]) * 100"
                        legendFormat = "{{name}} CPU %"
                    }
                )
            }
        )
        time = @{ from = "now-1h"; to = "now" }
        refresh = "5m"
    }
} | ConvertTo-Json -Depth 10

# Save dashboard to file
`$dashboardPath = "`$LogPath\grafana-dashboard.json"
`$dashboardJson | Out-File -FilePath `$dashboardPath -Encoding UTF8

Write-Host "Grafana dashboard JSON created: `$dashboardPath"
Write-Host "Import this file into Grafana to create the monitoring dashboard."

return `$dashboardPath
"@

    $scriptPath = "$LogPath\create-monitoring-dashboard.ps1"
    $dashboardScript | Out-File -FilePath $scriptPath -Encoding UTF8

    Write-Host "Monitoring dashboard creation script created: $scriptPath"
    return $scriptPath
}

# Function to set up scheduled monitoring tasks
function New-ScheduledMonitoringTasks {
    param([string]$MonitoringScript, [string]$ReportScript, [string]$NotificationScript, [int]$IntervalMinutes)

    Write-Host "Setting up scheduled monitoring tasks..." -ForegroundColor Green

    try {
        # Comprehensive monitoring task
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File `"$MonitoringScript`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 365)
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName "LocalAI-Comprehensive-Monitoring" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Runs comprehensive LocalAI monitoring every $IntervalMinutes minutes"

        # Report generation task (hourly)
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File `"$ReportScript`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 365)
        Register-ScheduledTask -TaskName "LocalAI-Status-Reports" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Generates LocalAI status reports hourly"

        # Alert notifications (every 15 minutes)
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File `"$NotificationScript`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Days 365)
        Register-ScheduledTask -TaskName "LocalAI-Alert-Notifications" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Sends LocalAI alert notifications every 15 minutes"

        Write-Host "Scheduled monitoring tasks created."
    } catch {
        Write-Error "Failed to create scheduled tasks: $_"
    }
}

# Main execution
$monitoringScript = New-ComprehensiveMonitoringScript -LogPath $BaseLogPath -IntervalMinutes $MonitoringIntervalMinutes

if ($SetupReportGeneration) {
    $reportScript = New-SystemStatusReport -LogPath $BaseLogPath
}

if ($ConfigureAlertNotification) {
    $notificationScript = New-AlertNotificationSystem -LogPath $BaseLogPath
}

$dashboardScript = New-MonitoringDashboardCreation -LogPath $BaseLogPath

if ($CreateScheduledTasks) {
    if ($SetupReportGeneration -and $ConfigureAlertNotification) {
        New-ScheduledMonitoringTasks -MonitoringScript $monitoringScript -ReportScript $reportScript -NotificationScript $notificationScript -IntervalMinutes $MonitoringIntervalMinutes
    }
}

Write-Host "Monitoring integration setup completed." -ForegroundColor Green
Write-Host "Monitoring interval: $MonitoringIntervalMinutes minutes"
Write-Host "Log path: $BaseLogPath"