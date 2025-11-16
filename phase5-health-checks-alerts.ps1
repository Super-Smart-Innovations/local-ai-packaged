# Phase 5: Health Checks and Alerts Setup
# This script implements built-in Docker health checks and comprehensive alerting system

param(
    [string]$BaseLogPath = "C:\Logs\localai",
    [switch]$UpdateDockerCompose,
    [switch]$SetupEmailAlerts,
    [string]$SmtpServer = "smtp.gmail.com",
    [string]$SmtpPort = "587",
    [string]$AlertEmail = "alerts@yourdomain.com"
)

# Function to create Docker health check configurations
function New-DockerHealthChecks {
    Write-Host "Creating Docker health check configurations..." -ForegroundColor Green

    $healthChecks = @{}

    # n8n health check
    $healthChecks["n8n"] = @{
        test = @("CMD-SHELL", "curl -f http://localhost:5678/healthz || exit 1")
        interval = "30s"
        timeout = "10s"
        retries = 3
        start_period = "40s"
    }

    # Supabase health checks
    $healthChecks["supabase"] = @{
        test = @("CMD-SHELL", "curl -f http://localhost:54321/rest/v1/ || exit 1")
        interval = "30s"
        timeout = "10s"
        retries = 3
        start_period = "60s"
    }

    # Ollama health check
    $healthChecks["ollama"] = @{
        test = @("CMD", "ollama", "list")
        interval = "60s"
        timeout = "30s"
        retries = 2
        start_period = "30s"
    }

    # Open WebUI health check
    $healthChecks["openwebui"] = @{
        test = @("CMD-SHELL", "curl -f http://localhost:3000/api/health || exit 1")
        interval = "30s"
        timeout = "10s"
        retries = 3
        start_period = "40s"
    }

    # Convert to JSON for docker-compose
    $healthChecks | ConvertTo-Json -Depth 10 | Out-File -FilePath "$BaseLogPath\health-checks-config.json" -Encoding UTF8

    Write-Host "Health check configurations created."
    return $healthChecks
}

# Function to update docker-compose.yml with health checks
function Update-DockerComposeHealthChecks {
    param([hashtable]$HealthChecks)

    Write-Host "Updating docker-compose.yml with health checks..." -ForegroundColor Green

    $dockerComposePath = "docker-compose.yml"

    if (!(Test-Path $dockerComposePath)) {
        Write-Warning "docker-compose.yml not found at $dockerComposePath"
        return
    }

    # Read docker-compose content
    $composeContent = Get-Content $dockerComposePath -Raw | ConvertFrom-Yaml

    # Add health checks to services
    foreach ($serviceName in $HealthChecks.Keys) {
        if ($composeContent.services.ContainsKey($serviceName)) {
            $composeContent.services[$serviceName]["healthcheck"] = $HealthChecks[$serviceName]
            Write-Host "Added health check to service: $serviceName"
        } else {
            Write-Warning "Service $serviceName not found in docker-compose.yml"
        }
    }

    # Write back to docker-compose.yml
    $composeContent | ConvertTo-Yaml | Out-File -FilePath $dockerComposePath -Encoding UTF8

    Write-Host "docker-compose.yml updated with health checks."
}

# Function to create uptime monitoring script
function New-UptimeMonitoringScript {
    param([string]$LogPath)

    Write-Host "Creating uptime monitoring script..." -ForegroundColor Green

    $uptimeScript = @"
param(
    [string[]]`$Urls = @(
        "http://localhost:5678",  # n8n
        "http://localhost:3000",  # Open WebUI
        "http://localhost:3001",  # Flowise
        "http://localhost:54321"  # Supabase
    ),
    [string]`$LogPath = "$LogPath"
)

`$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

foreach (`$url in `$Urls) {
    try {
        `$response = Invoke-WebRequest -Uri `$url -TimeoutSec 10 -UseBasicParsing
        if (`$response.StatusCode -eq 200) {
            Write-Host "UP: `$url"
            Add-Content -Path "`$LogPath\uptime.log" -Value "`$Timestamp - UP: `$url"
        } else {
            Write-Host "DOWN: `$url (Status: `$(`$response.StatusCode))"
            Add-Content -Path "`$LogPath\alerts.log" -Value "`$Timestamp - DOWN: `$url (Status: `$(`$response.StatusCode))"
        }
    } catch {
        Write-Host "DOWN: `$url (Error: `$_)"
        Add-Content -Path "`$LogPath\alerts.log" -Value "`$Timestamp - DOWN: `$url (Error: `$_)"
    }
}
"@

    $scriptPath = "$LogPath\uptime-monitor.ps1"
    $uptimeScript | Out-File -FilePath $scriptPath -Encoding UTF8

    Write-Host "Uptime monitoring script created: $scriptPath"
    return $scriptPath
}

# Function to create resource monitoring and alerts
function New-ResourceMonitoringAlerts {
    param([string]$LogPath)

    Write-Host "Creating resource monitoring and alerts..." -ForegroundColor Green

    $resourceScript = @"
param(
    [string]`$LogPath = "$LogPath",
    [double]`$CpuThreshold = 80.0,
    [double]`$MemoryThreshold = 85.0,
    [double]`$DiskThreshold = 90.0
)

`$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
`$alerts = @()

# Check CPU usage
try {
    `$cpu = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1
    `$cpuValue = `$cpu.CounterSamples.CookedValue
    if (`$cpuValue -gt `$CpuThreshold) {
        `$alerts += "HIGH CPU: `$(`$cpuValue.ToString("F1"))% (Threshold: `$CpuThreshold%)"
    }
} catch {
    Write-Warning "Failed to check CPU usage: `$_"
}

# Check memory usage
try {
    `$memory = Get-Counter '\Memory\% Committed Bytes In Use' -SampleInterval 1 -MaxSamples 1
    `$memoryValue = `$memory.CounterSamples.CookedValue
    if (`$memoryValue -gt `$MemoryThreshold) {
        `$alerts += "HIGH MEMORY: `$(`$memoryValue.ToString("F1"))% (Threshold: `$MemoryThreshold%)"
    }
} catch {
    Write-Warning "Failed to check memory usage: `$_"
}

# Check disk usage
try {
    `$disk = Get-Counter '\LogicalDisk(_Total)\% Free Space' -SampleInterval 1 -MaxSamples 1
    `$diskFreeValue = `$disk.CounterSamples.CookedValue
    `$diskUsedValue = 100 - `$diskFreeValue
    if (`$diskUsedValue -gt `$DiskThreshold) {
        `$alerts += "HIGH DISK USAGE: `$(`$diskUsedValue.ToString("F1"))% (Threshold: `$DiskThreshold%)"
    }
} catch {
    Write-Warning "Failed to check disk usage: `$_"
}

# Log results
if (`$alerts.Count -gt 0) {
    foreach (`$alert in `$alerts) {
        Write-Host "ALERT: `$alert"
        Add-Content -Path "`$LogPath\alerts.log" -Value "`$Timestamp - ALERT: `$alert"
    }
} else {
    Add-Content -Path "`$LogPath\monitoring.log" -Value "`$Timestamp - Resources OK - CPU: `$(`$cpuValue.ToString("F1"))%, Memory: `$(`$memoryValue.ToString("F1"))%, Disk: `$(`$diskUsedValue.ToString("F1"))%"
}

return `$alerts.Count
"@

    $scriptPath = "$LogPath\resource-monitor.ps1"
    $resourceScript | Out-File -FilePath $scriptPath -Encoding UTF8

    Write-Host "Resource monitoring script created: $scriptPath"
    return $scriptPath
}

# Function to set up email alerting system
function New-EmailAlertSystem {
    param(
        [string]$LogPath,
        [string]$SmtpServer,
        [string]$SmtpPort,
        [string]$AlertEmail
    )

    Write-Host "Setting up email alerting system..." -ForegroundColor Green

    # Create email alert script
    $emailScript = @"
param(
    [string]`$LogPath = "$LogPath",
    [string]`$SmtpServer = "$SmtpServer",
    [string]`$SmtpPort = "$SmtpPort",
    [string]`$AlertEmail = "$AlertEmail",
    [string]`$SmtpUsername = "your-email@gmail.com",
    [string]`$SmtpPassword = "your-app-password"
)

# Read recent alerts
`$alertFile = "`$LogPath\alerts.log"
if (Test-Path `$alertFile) {
    `$recentAlerts = Get-Content `$alertFile | Select-Object -Last 10

    if (`$recentAlerts) {
        `$body = "Recent LocalAI System Alerts:`n`n" + (`$recentAlerts -join "`n")

        try {
            `$smtpClient = New-Object System.Net.Mail.SmtpClient(`$SmtpServer, `$SmtpPort)
            `$smtpClient.EnableSsl = `$true
            `$smtpClient.Credentials = New-Object System.Net.NetworkCredential(`$SmtpUsername, `$SmtpPassword)

            `$mailMessage = New-Object System.Net.Mail.MailMessage
            `$mailMessage.From = `$SmtpUsername
            `$mailMessage.To.Add(`$AlertEmail)
            `$mailMessage.Subject = "LocalAI System Alerts - " + (Get-Date -Format "yyyy-MM-dd HH:mm")
            `$mailMessage.Body = `$body

            `$smtpClient.Send(`$mailMessage)
            Write-Host "Alert email sent successfully."
        } catch {
            Write-Error "Failed to send alert email: `$_"
        }
    }
}
"@

    $scriptPath = "$LogPath\email-alert.ps1"
    $emailScript | Out-File -FilePath $scriptPath -Encoding UTF8

    Write-Host "Email alerting script created: $scriptPath"
}

# Function to create SSL certificate monitoring
function New-SSLCertificateMonitoring {
    param([string]$LogPath)

    Write-Host "Creating SSL certificate monitoring..." -ForegroundColor Green

    $sslScript = @"
param(
    [string[]]`$Domains = @("yourdomain.com", "api.yourdomain.com", "webui.yourdomain.com"),
    [string]`$LogPath = "$LogPath",
    [int]`$WarningDays = 30
)

`$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

foreach (`$domain in `$Domains) {
    try {
        `$cert = Invoke-WebRequest -Uri "https://`$domain" -TimeoutSec 10 | Select-Object -ExpandProperty Certificates | Select-Object -First 1

        if (`$cert) {
            `$expiryDate = `$cert.NotAfter
            `$daysUntilExpiry = (`$expiryDate - (Get-Date)).Days

            if (`$daysUntilExpiry -le `$WarningDays) {
                `$alert = "SSL Certificate for `$domain expires in `$daysUntilExpiry days (`$expiryDate)"
                Write-Host "ALERT: `$alert"
                Add-Content -Path "`$LogPath\alerts.log" -Value "`$Timestamp - ALERT: `$alert"
            } else {
                Write-Host "SSL OK: `$domain expires in `$daysUntilExpiry days"
                Add-Content -Path "`$LogPath\ssl-monitoring.log" -Value "`$Timestamp - SSL OK: `$domain expires in `$daysUntilExpiry days"
            }
        }
    } catch {
        `$alert = "Failed to check SSL certificate for `$domain`: `$_"
        Write-Host "ERROR: `$alert"
        Add-Content -Path "`$LogPath\alerts.log" -Value "`$Timestamp - ERROR: `$alert"
    }
}
"@

    $scriptPath = "$LogPath\ssl-monitor.ps1"
    $sslScript | Out-File -FilePath $scriptPath -Encoding UTF8

    Write-Host "SSL certificate monitoring script created: $scriptPath"
    return $scriptPath
}

# Function to create scheduled monitoring tasks
function New-ScheduledMonitoringTasks {
    param(
        [string]$UptimeScript,
        [string]$ResourceScript,
        [string]$EmailScript,
        [string]$SslScript
    )

    Write-Host "Creating scheduled monitoring tasks..." -ForegroundColor Green

    try {
        # Uptime monitoring - every 5 minutes
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File `"$UptimeScript`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 365)
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName "LocalAI-Uptime-Monitor" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Monitors service uptime every 5 minutes"

        # Resource monitoring - every 10 minutes
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File `"$ResourceScript`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 10) -RepetitionDuration (New-TimeSpan -Days 365)
        Register-ScheduledTask -TaskName "LocalAI-Resource-Monitor" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Monitors system resources every 10 minutes"

        # SSL monitoring - daily
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File `"$SslScript`""
        $trigger = New-ScheduledTaskTrigger -Daily -At "06:00"
        Register-ScheduledTask -TaskName "LocalAI-SSL-Monitor" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Monitors SSL certificates daily"

        # Email alerts - hourly
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File `"$EmailScript`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 365)
        Register-ScheduledTask -TaskName "LocalAI-Email-Alerts" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Sends alert emails hourly"

        Write-Host "Scheduled monitoring tasks created."
    } catch {
        Write-Error "Failed to create scheduled tasks: $_"
    }
}

# Main execution
$healthChecks = New-DockerHealthChecks

if ($UpdateDockerCompose) {
    Update-DockerComposeHealthChecks -HealthChecks $healthChecks
}

$uptimeScript = New-UptimeMonitoringScript -LogPath $BaseLogPath
$resourceScript = New-ResourceMonitoringAlerts -LogPath $BaseLogPath
$sslScript = New-SSLCertificateMonitoring -LogPath $BaseLogPath

if ($SetupEmailAlerts) {
    New-EmailAlertSystem -LogPath $BaseLogPath -SmtpServer $SmtpServer -SmtpPort $SmtpPort -AlertEmail $AlertEmail
    New-ScheduledMonitoringTasks -UptimeScript $uptimeScript -ResourceScript $resourceScript -EmailScript "$BaseLogPath\email-alert.ps1" -SslScript $sslScript
} else {
    New-ScheduledMonitoringTasks -UptimeScript $uptimeScript -ResourceScript $resourceScript -EmailScript "" -SslScript $sslScript
}

Write-Host "Health checks and alerts setup completed." -ForegroundColor Green
Write-Host "Log path: $BaseLogPath"