# Backup Scheduling Setup Script
# This script sets up Windows Task Scheduler tasks for automated backups

param(
    [string]$BackupRoot = "C:\backups",
    [string]$ScriptsPath = $PSScriptRoot,
    [switch]$RemoveExisting
)

# Configuration
$logFile = Join-Path $BackupRoot "scheduling_setup_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# Function to log messages
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level]: $Message"
    Write-Host $logMessage
    Add-Content -Path $logFile -Value $logMessage
}

Write-Log "Starting backup scheduling setup"

# Create backup directories
$dirs = @($BackupRoot, (Join-Path $BackupRoot "reports"))
foreach ($dir in $dirs) {
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
        Write-Log "Created directory: $dir"
    }
}

# Remove existing tasks if requested
if ($RemoveExisting) {
    Write-Log "Removing existing backup tasks"
    $existingTasks = @("LocalAI-DailyBackup", "LocalAI-WeeklyBackup", "LocalAI-BackupVerification", "LocalAI-MonthlyReport")

    foreach ($task in $existingTasks) {
        try {
            schtasks /delete /tn $task /f 2>$null
            Write-Log "Removed existing task: $task"
        }
        catch {
            Write-Log "Task $task not found or already removed"
        }
    }
}

# Create daily backup task
Write-Log "Creating daily backup task"

$dailyTaskCommand = "powershell.exe -ExecutionPolicy Bypass -File `"$ScriptsPath\backup-orchestrator.ps1`" -BackupRoot `"$BackupRoot`" -Daily"
$dailyTaskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mitask">
  <RegistrationInfo>
    <Description>Daily backup of Local AI Services configurations, Docker volumes, and Ubuntu containers</Description>
    <Author>SYSTEM</Author>
  </RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>2024-01-01T02:00:00</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT4H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-ExecutionPolicy Bypass -File "$ScriptsPath\backup-orchestrator.ps1" -BackupRoot "$BackupRoot" -Daily</Arguments>
    </Exec>
  </Actions>
</Task>
"@

# Save and import daily task
$dailyTaskXmlPath = Join-Path $env:TEMP "LocalAI-DailyBackup.xml"
$dailyTaskXml | Out-File -FilePath $dailyTaskXmlPath -Encoding Unicode

try {
    schtasks /create /tn "LocalAI-DailyBackup" /xml $dailyTaskXmlPath /f
    Write-Log "Created daily backup task successfully"
}
catch {
    Write-Log "Failed to create daily backup task: $($_.Exception.Message)" "ERROR"
}

# Create weekly backup task
Write-Log "Creating weekly backup task"

$weeklyTaskCommand = "powershell.exe -ExecutionPolicy Bypass -File `"$ScriptsPath\backup-orchestrator.ps1`" -BackupRoot `"$BackupRoot`" -Weekly"
$weeklyTaskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mitask">
  <RegistrationInfo>
    <Description>Weekly backup of Local AI Services nested services (PostgreSQL, Redis, etc.)</Description>
    <Author>SYSTEM</Author>
  </RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>2024-01-01T03:00:00</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByWeek>
        <WeeksInterval>1</WeeksInterval>
        <DaysOfWeek>
          <Sunday />
        </DaysOfWeek>
      </ScheduleByWeek>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT8H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-ExecutionPolicy Bypass -File "$ScriptsPath\backup-orchestrator.ps1" -BackupRoot "$BackupRoot" -Weekly</Arguments>
    </Exec>
  </Actions>
</Task>
"@

# Save and import weekly task
$weeklyTaskXmlPath = Join-Path $env:TEMP "LocalAI-WeeklyBackup.xml"
$weeklyTaskXml | Out-File -FilePath $weeklyTaskXmlPath -Encoding Unicode

try {
    schtasks /create /tn "LocalAI-WeeklyBackup" /xml $weeklyTaskXmlPath /f
    Write-Log "Created weekly backup task successfully"
}
catch {
    Write-Log "Failed to create weekly backup task: $($_.Exception.Message)" "ERROR"
}

# Create weekly backup verification task
Write-Log "Creating backup verification task"

$verificationTaskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mitask">
  <RegistrationInfo>
    <Description>Weekly verification of Local AI Services backups</Description>
    <Author>SYSTEM</Author>
  </RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>2024-01-01T04:00:00</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByWeek>
        <WeeksInterval>1</WeeksInterval>
        <DaysOfWeek>
          <Monday />
        </DaysOfWeek>
      </ScheduleByWeek>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT2H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-ExecutionPolicy Bypass -File "$ScriptsPath\backup-verification.ps1" -TestType All -BackupRoot "$BackupRoot" -ReportPath "$(Join-Path $BackupRoot "reports")"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

# Save and import verification task
$verificationTaskXmlPath = Join-Path $env:TEMP "LocalAI-BackupVerification.xml"
$verificationTaskXml | Out-File -FilePath $verificationTaskXmlPath -Encoding Unicode

try {
    schtasks /create /tn "LocalAI-BackupVerification" /xml $verificationTaskXmlPath /f
    Write-Log "Created backup verification task successfully"
}
catch {
    Write-Log "Failed to create backup verification task: $($_.Exception.Message)" "ERROR"
}

# Clean up temporary files
Remove-Item $dailyTaskXmlPath, $weeklyTaskXmlPath, $verificationTaskXmlPath -ErrorAction SilentlyContinue

# Verify tasks were created
Write-Log "Verifying scheduled tasks"
$createdTasks = schtasks /query /fo csv | ConvertFrom-Csv | Where-Object { $_.TaskName -like "*LocalAI*" }

if ($createdTasks.Count -ge 3) {
    Write-Log "All scheduled tasks created successfully"
    foreach ($task in $createdTasks) {
        Write-Log "Task: $($task.TaskName) - Status: $($task.Status)"
    }
} else {
    Write-Log "Warning: Some tasks may not have been created successfully" "WARNING"
}

# Create summary report
$summaryFile = Join-Path $BackupRoot "backup_scheduling_summary_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$summaryContent = @"
Backup Scheduling Setup Summary
Generated: $(Get-Date)
Backup Root: $BackupRoot
Scripts Path: $ScriptsPath

Scheduled Tasks Created:
======================

1. LocalAI-DailyBackup
   - Schedule: Daily at 2:00 AM
   - Action: Full daily backup (configurations, Docker volumes, Ubuntu containers)
   - Execution Limit: 4 hours

2. LocalAI-WeeklyBackup
   - Schedule: Weekly on Sunday at 3:00 AM
   - Action: Nested services backup (PostgreSQL, Redis, etc.)
   - Execution Limit: 8 hours

3. LocalAI-BackupVerification
   - Schedule: Weekly on Monday at 4:00 AM
   - Action: Verify integrity of all backups
   - Execution Limit: 2 hours

Backup Storage Layout:
===================
$BackupRoot\
├── configurations\    # Daily configuration backups
├── docker-volumes\    # Daily Docker volume backups
├── ubuntu-volumes\    # Daily Ubuntu container backups
├── nested-services\   # Weekly nested service backups
└── reports\           # Backup reports and logs

Monitoring:
==========
- Check Task Scheduler for task execution status
- Review backup logs in reports directory
- Monitor storage usage and retention compliance
- Run manual verification: .\backup-verification.ps1

Maintenance:
===========
- Review task execution monthly
- Update scripts as system changes
- Monitor backup storage capacity
- Test disaster recovery procedures quarterly

Log Files:
=========
Setup Log: $logFile
Summary: $summaryFile
"@

$summaryContent | Out-File -FilePath $summaryFile -Encoding UTF8

Write-Log "Backup scheduling setup completed successfully"
Write-Log "Summary report: $summaryFile"

# Display final status
Write-Host "Backup scheduling setup completed!" -ForegroundColor Green
Write-Host "Summary: $summaryFile" -ForegroundColor Cyan
Write-Host "Log: $logFile" -ForegroundColor Cyan

# Display next steps
Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "1. Verify tasks in Task Scheduler" -ForegroundColor White
Write-Host "2. Run a test backup: .\backup-orchestrator.ps1 -Daily" -ForegroundColor White
Write-Host "3. Check backup logs and reports" -ForegroundColor White
Write-Host "4. Schedule quarterly disaster recovery testing" -ForegroundColor White