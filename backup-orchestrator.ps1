# Backup Orchestration Script
# This script coordinates all backup operations and provides scheduling capabilities

param(
    [string]$BackupRoot = "C:\backups",
    [switch]$Daily,
    [switch]$Weekly,
    [switch]$FullSystem,
    [switch]$VerifyAll,
    [switch]$ScheduleTasks
)

# Configuration
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$executionLog = Join-Path $BackupRoot "orchestrator_log_$timestamp.txt"

# Function to log messages
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level]: $Message"
    Write-Host $logMessage
    Add-Content -Path $executionLog -Value $logMessage
}

Write-Log "Starting backup orchestration - $timestamp"

# Create backup directories
$dirs = @(
    (Join-Path $BackupRoot "ubuntu-volumes"),
    (Join-Path $BackupRoot "nested-services"),
    (Join-Path $BackupRoot "docker-volumes"),
    (Join-Path $BackupRoot "configurations"),
    (Join-Path $BackupRoot "reports")
)

foreach ($dir in $dirs) {
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

# Function to execute backup script
function Invoke-BackupScript {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments = @(),
        [string]$BackupType
    )

    Write-Log "Starting $BackupType backup"

    if (Test-Path $ScriptPath) {
        try {
            $argString = $Arguments -join " "
            $result = & $ScriptPath @Arguments 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Log "$BackupType backup completed successfully"
                return $true
            } else {
                Write-Log "$BackupType backup failed with exit code $LASTEXITCODE" "ERROR"
                Write-Log "Output: $result" "ERROR"
                return $false
            }
        }
        catch {
            Write-Log "$BackupType backup failed with exception: $($_.Exception.Message)" "ERROR"
            return $false
        }
    } else {
        Write-Log "Backup script not found: $ScriptPath" "ERROR"
        return $false
    }
}

# Determine backup scope
$backupSuccess = $true

if ($FullSystem -or $Daily) {
    Write-Log "Executing full system backup (daily)"

    # Configuration backup
    $backupSuccess = Invoke-BackupScript -ScriptPath ".\backup-configurations.ps1" -Arguments @("-BackupPath", (Join-Path $BackupRoot "configurations"), ($VerifyAll ? "-VerifyIntegrity" : $null)) -BackupType "Configuration"
    if (!$backupSuccess) { Write-Log "Configuration backup failed, continuing with others" "WARNING" }

    # Ubuntu volumes backup
    $backupSuccess = Invoke-BackupScript -ScriptPath ".\backup-ubuntu-volumes.ps1" -Arguments @("-BackupPath", (Join-Path $BackupRoot "ubuntu-volumes"), ($VerifyAll ? "-VerifyIntegrity" : $null)) -BackupType "Ubuntu Volumes"
    if (!$backupSuccess) { Write-Log "Ubuntu volumes backup failed, continuing with others" "WARNING" }

    # Docker volumes backup
    $backupSuccess = Invoke-BackupScript -ScriptPath ".\backup-docker-volumes.ps1" -Arguments @("-BackupPath", (Join-Path $BackupRoot "docker-volumes"), "-IncludeVolumes", "n8n_storage,ollama_storage,qdrant_storage,open-webui,flowise,valkey-data", ($VerifyAll ? "-VerifyIntegrity" : $null)) -BackupType "Docker Volumes"
    if (!$backupSuccess) { Write-Log "Docker volumes backup failed, continuing with others" "WARNING" }
}

if ($FullSystem -or $Weekly) {
    Write-Log "Executing nested services backup (weekly)"

    # Nested services backup (requires Bash script)
    $bashScript = Join-Path $PSScriptRoot "backup-nested-services.sh"

    if (Test-Path $bashScript) {
        try {
            $env:BACKUP_ROOT = Join-Path $BackupRoot "nested-services"
            $env:VERIFY_INTEGRITY = $VerifyAll.ToString().ToLower()

            if ($VerifyAll) {
                & bash.exe $bashScript
            } else {
                & bash.exe $bashScript
            }

            if ($LASTEXITCODE -eq 0) {
                Write-Log "Nested services backup completed successfully"
            } else {
                Write-Log "Nested services backup failed with exit code $LASTEXITCODE" "ERROR"
            }
        }
        catch {
            Write-Log "Nested services backup failed with exception: $($_.Exception.Message)" "ERROR"
        }
    } else {
        Write-Log "Nested services backup script not found: $bashScript" "ERROR"
    }
}

# Generate comprehensive backup report
Write-Log "Generating backup report"

$reportFile = Join-Path $BackupRoot "reports\backup_report_$timestamp.txt"
$reportContent = @"
Backup Orchestration Report
Generated: $(Get-Date)
Execution Log: $executionLog

Backup Summary:
===============

Configuration Backups:
$(Get-ChildItem (Join-Path $BackupRoot "configurations") -Directory | Where-Object { $_.Name -match '^\d{8}_\d{6}$' } | Sort-Object Name -Descending | Select-Object -First 1 | ForEach-Object {
    "Latest: $($_.Name) - Size: $((Get-ChildItem $_.FullName -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB) MB"
})

Ubuntu Volume Backups:
$(Get-ChildItem (Join-Path $BackupRoot "ubuntu-volumes") -Directory | Where-Object { $_.Name -match '^\d{8}_\d{6}$' } | Sort-Object Name -Descending | Select-Object -First 1 | ForEach-Object {
    "Latest: $($_.Name) - Size: $((Get-ChildItem $_.FullName -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB) MB"
})

Docker Volume Backups:
$(Get-ChildItem (Join-Path $BackupRoot "docker-volumes") -Directory | Where-Object { $_.Name -match '^\d{8}_\d{6}$' } | Sort-Object Name -Descending | Select-Object -First 1 | ForEach-Object {
    "Latest: $($_.Name) - Size: $((Get-ChildItem $_.FullName -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB) MB"
})

Nested Services Backups:
$(Get-ChildItem (Join-Path $BackupRoot "nested-services") -Directory | Where-Object { $_.Name -match '^\d{8}_\d{6}$' } | Sort-Object Name -Descending | Select-Object -First 1 | ForEach-Object {
    "Latest: $($_.Name) - Size: $((Get-ChildItem $_.FullName -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB) MB"
})

Storage Usage:
Total Backup Size: $((Get-ChildItem $BackupRoot -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1GB) GB
Free Space on $(Split-Path $BackupRoot -Qualifier): $((Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType=3" | Where-Object { $_.DeviceID -eq (Split-Path $BackupRoot -Qualifier) }).FreeSpace / 1GB) GB

Next Scheduled Backups:
- Daily: 2:00 AM
- Weekly: Sunday 3:00 AM
"@

$reportContent | Out-File -FilePath $reportFile -Encoding UTF8

# Schedule tasks if requested
if ($ScheduleTasks) {
    Write-Log "Setting up scheduled tasks"

    # Remove existing tasks
    try {
        schtasks /delete /tn "LocalAI-DailyBackup" /f 2>$null
        schtasks /delete /tn "LocalAI-WeeklyBackup" /f 2>$null
    } catch {}

    # Create daily backup task
    $dailyTaskCommand = "powershell.exe -ExecutionPolicy Bypass -File `"$PSScriptRoot\backup-orchestrator.ps1`" -BackupRoot `"$BackupRoot`" -Daily"
    schtasks /create /tn "LocalAI-DailyBackup" /tr $dailyTaskCommand /sc daily /st 02:00 /ru System /rl highest /f

    # Create weekly backup task
    $weeklyTaskCommand = "powershell.exe -ExecutionPolicy Bypass -File `"$PSScriptRoot\backup-orchestrator.ps1`" -BackupRoot `"$BackupRoot`" -Weekly"
    schtasks /create /tn "LocalAI-WeeklyBackup" /tr $weeklyTaskCommand /sc weekly /d SUN /st 03:00 /ru System /rl highest /f

    Write-Log "Scheduled tasks created successfully"
}

# Send notification (placeholder for email/Slack integration)
Write-Log "Backup orchestration completed. Report: $reportFile"

# Cleanup old logs (keep last 30 days)
$oldLogs = Get-ChildItem $BackupRoot -File -Filter "orchestrator_log_*.txt" | Where-Object {
    (Get-Date) - $_.CreationTime -gt (New-TimeSpan -Days 30)
}
foreach ($oldLog in $oldLogs) {
    Remove-Item $oldLog.FullName -Force
}

Write-Log "Backup orchestration finished successfully"