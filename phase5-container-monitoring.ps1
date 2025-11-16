# Phase 5: Container and Windows Server Monitoring Setup
# This script configures comprehensive monitoring for Docker containers and Windows host

param(
    [switch]$InstallTools,
    [switch]$CreateScheduledTask,
    [string]$LogPath = "C:\Logs\localai\monitoring"
)

# Ensure log directory exists
if (!(Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force
}

# Function to monitor Ubuntu container from Windows
function Monitor-UbuntuContainer {
    Write-Host "Monitoring Ubuntu container resources..." -ForegroundColor Green

    try {
        $stats = docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "$timestamp - Ubuntu Container Stats:`n$stats"
        Add-Content -Path "$LogPath\ubuntu-container-stats.log" -Value $logEntry
        Write-Host $stats
    } catch {
        Write-Error "Failed to monitor Ubuntu container: $_"
    }
}

# Function to monitor all nested containers from Windows
function Monitor-NestedContainers {
    Write-Host "Monitoring nested containers from Windows..." -ForegroundColor Green

    try {
        $stats = docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "$timestamp - All Containers Stats:`n$stats"
        Add-Content -Path "$LogPath\nested-containers-stats.log" -Value $logEntry
        Write-Host $stats
    } catch {
        Write-Error "Failed to monitor nested containers: $_"
    }
}

# Function to get Docker system info
function Get-DockerSystemInfo {
    Write-Host "Getting Docker system information..." -ForegroundColor Green

    try {
        $info = docker info
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "$timestamp - Docker System Info:`n$info"
        Add-Content -Path "$LogPath\docker-system-info.log" -Value $logEntry
        Write-Host $info
    } catch {
        Write-Error "Failed to get Docker system info: $_"
    }
}

# Function to monitor Docker events
function Monitor-DockerEvents {
    Write-Host "Monitoring Docker events..." -ForegroundColor Green

    try {
        $events = docker events --since "1m" --until "0s" --format "{{.Time}} {{.Type}} {{.Action}} {{.Actor.Attributes.name}}"
        if ($events) {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $logEntry = "$timestamp - Docker Events:`n$events"
            Add-Content -Path "$LogPath\docker-events.log" -Value $logEntry
            Write-Host $events
        }
    } catch {
        Write-Error "Failed to monitor Docker events: $_"
    }
}

# Function to monitor Windows system resources
function Monitor-WindowsResources {
    Write-Host "Monitoring Windows system resources..." -ForegroundColor Green

    try {
        $cpu = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1
        $memory = Get-Counter '\Memory\% Committed Bytes In Use' -SampleInterval 1 -MaxSamples 1
        $disk = Get-Counter '\LogicalDisk(_Total)\% Free Space' -SampleInterval 1 -MaxSamples 1

        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = @"
$timestamp - Windows Resources:
CPU Usage: $($cpu.CounterSamples.CookedValue)%
Memory Committed: $($memory.CounterSamples.CookedValue)%
Disk Free Space: $($disk.CounterSamples.CookedValue)%
"@

        Add-Content -Path "$LogPath\windows-resources.log" -Value $logEntry
        Write-Host $logEntry
    } catch {
        Write-Error "Failed to monitor Windows resources: $_"
    }
}

# Install monitoring tools if requested
if ($InstallTools) {
    Write-Host "Installing monitoring tools..." -ForegroundColor Yellow

    # Install Windows monitoring tools
    try {
        # Check if chocolatey is installed
        if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
        }

        # Install monitoring tools
        choco install sysinternals -y
        choco install procexp -y  # Process Explorer
        choco install perfmon -y # Performance Monitor

        Write-Host "Monitoring tools installed successfully." -ForegroundColor Green
    } catch {
        Write-Error "Failed to install monitoring tools: $_"
    }
}

# Create scheduled task for continuous monitoring if requested
if ($CreateScheduledTask) {
    Write-Host "Creating scheduled task for continuous monitoring..." -ForegroundColor Yellow

    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File `"$PSScriptRoot\$($MyInvocation.MyCommand.Name)`" -LogPath `"$LogPath`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 365)
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

        Register-ScheduledTask -TaskName "LocalAI-Container-Monitoring" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Monitors Docker containers and Windows resources every 5 minutes"

        Write-Host "Scheduled task created successfully." -ForegroundColor Green
    } catch {
        Write-Error "Failed to create scheduled task: $_"
    }
}

# Run monitoring functions
Monitor-UbuntuContainer
Monitor-NestedContainers
Get-DockerSystemInfo
Monitor-DockerEvents
Monitor-WindowsResources

Write-Host "Container monitoring completed. Logs saved to $LogPath" -ForegroundColor Green