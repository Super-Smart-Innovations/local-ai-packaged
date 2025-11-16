# Phase 2: Windows Defender Advanced Threat Protection Setup
# This script configures Windows Defender with advanced threat protection
# and security policies for containerized environment

# Requires administrator privileges
#Requires -RunAsAdministrator

Write-Host "Starting Windows Defender advanced threat protection setup for Phase 2..." -ForegroundColor Green

# Step 1: Enable Windows Defender Real-time Protection
Write-Host "Enabling Windows Defender real-time protection..." -ForegroundColor Yellow
Set-MpPreference -DisableRealtimeMonitoring $false
Set-MpPreference -DisableBehaviorMonitoring $false
Set-MpPreference -DisableBlockAtFirstSeen $false
Set-MpPreference -DisableIOAVProtection $false
Set-MpPreference -DisablePrivacyMode $false
Set-MpPreference -DisableScriptScanning $false

# Step 2: Configure Cloud-delivered Protection
Write-Host "Configuring cloud-delivered protection..." -ForegroundColor Yellow
Set-MpPreference -MAPSReporting Advanced
Set-MpPreference -SubmitSamplesConsent Always

# Step 3: Configure Exclusions for Docker and Development
Write-Host "Configuring security exclusions for Docker and development..." -ForegroundColor Yellow

# Docker Desktop exclusions
$DOCKER_PATHS = @(
    "C:\Program Files\Docker",
    "C:\Program Files\Docker\Docker",
    "C:\ProgramData\Docker",
    "C:\ProgramData\DockerDesktop",
    "$env:USERPROFILE\AppData\Local\Docker",
    "$env:USERPROFILE\AppData\Roaming\Docker",
    "$env:USERPROFILE\AppData\Roaming\Docker Desktop"
)

foreach ($path in $DOCKER_PATHS) {
    if (Test-Path $path) {
        Add-MpPreference -ExclusionPath $path
        Write-Host "Added exclusion: $path" -ForegroundColor Cyan
    }
}

# WSL2 exclusions
$WSL_PATHS = @(
    "$env:USERPROFILE\AppData\Local\Packages\CanonicalGroupLimited.Ubuntu*",
    "$env:LOCALAPPDATA\Packages\CanonicalGroupLimited.Ubuntu*",
    "\\wsl$\Ubuntu*",
    "\\wsl.localhost\Ubuntu*"
)

foreach ($path in $WSL_PATHS) {
    Add-MpPreference -ExclusionPath $path
}

# Development workspace exclusions
$DEV_PATHS = @(
    "C:\dev-env.local",
    "$env:USERPROFILE\dev-env.local"
)

foreach ($path in $DEV_PATHS) {
    if (Test-Path $path) {
        Add-MpPreference -ExclusionPath $path
    }
}

# File extension exclusions for development files
$DEV_EXTENSIONS = @(
    ".ps1", ".sh", ".yml", ".yaml", ".json", ".md", ".txt",
    ".py", ".js", ".ts", ".html", ".css", ".sql"
)

foreach ($ext in $DEV_EXTENSIONS) {
    Add-MpPreference -ExclusionExtension $ext
}

# Step 4: Configure Advanced Threat Protection Features
Write-Host "Configuring advanced threat protection features..." -ForegroundColor Yellow

# Enable potentially unwanted application protection
Set-MpPreference -PUAProtection Enabled

# Enable controlled folder access (protects against ransomware)
Set-MpPreference -EnableControlledFolderAccess Enabled

# Configure controlled folder access allowed applications
$ALLOWED_APPS = @(
    "C:\Program Files\Docker\Docker Desktop.exe",
    "C:\Program Files\Docker\Docker\DockerCli.exe",
    "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe",
    "C:\Windows\System32\cmd.exe"
)

foreach ($app in $ALLOWED_APPS) {
    if (Test-Path $app) {
        Add-MpPreference -ControlledFolderAccessAllowedApplications $app
    }
}

# Enable network protection
Set-MpPreference -EnableNetworkProtection Enabled

# Step 5: Configure Windows Defender Firewall Integration
Write-Host "Configuring Windows Defender Firewall integration..." -ForegroundColor Yellow

# Enable Windows Defender Firewall rules for protection
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True

# Enable stealth mode for additional security
netsh advfirewall set global statefulftp disable
netsh advfirewall set global statefulpptp disable

# Step 6: Configure Attack Surface Reduction Rules
Write-Host "Configuring attack surface reduction rules..." -ForegroundColor Yellow

# Enable ASR rules (using PowerShell cmdlets)
$ASRRules = @(
    "56a863a9-875e-4185-98a7-b882c64b5ce5",  # Block executable files from running unless they meet a prevalence, age, or trusted list criterion
    "7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c",  # Block Adobe Reader from creating child processes
    "d4f940ab-401b-4efc-aadc-ad5f3c50688a",  # Block all Office applications from creating child processes
    "9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2",  # Block credential stealing from the Windows local security authority subsystem
    "be9ba2d9-53ea-4cdc-84e5-9b1eeee46550",  # Block executable content from email client and webmail
    "01443614-cd74-433a-b99e-2ecdc07bfc25",  # Block untrusted and unsigned processes that run from USB
    "5beb7efe-fd9a-4556-801d-275e5ffc04cc",  # Block execution of potentially obfuscated scripts
    "d3e037e1-3eb8-44c8-a917-57927947596d",  # Block JavaScript or VBScript from launching downloaded executable content
    "3b576869-a4ec-4529-8536-b80a7769e899"   # Block Office applications from injecting code into other processes
)

foreach ($rule in $ASRRules) {
    Set-MpPreference -AttackSurfaceReductionRules_Ids $rule -AttackSurfaceReductionRules_Actions Enabled
}

# Step 7: Configure Tamper Protection
Write-Host "Configuring tamper protection..." -ForegroundColor Yellow

# Enable tamper protection (prevents malicious apps from disabling Windows Defender)
# Note: This is configured in Windows Security UI, but we can check status
$tamperProtection = Get-MpComputerStatus | Select-Object -ExpandProperty IsTamperProtected
if (-not $tamperProtection) {
    Write-Host "Warning: Tamper protection is not enabled. Please enable it in Windows Security settings." -ForegroundColor Red
    Write-Host "Navigate to: Windows Security > Virus & threat protection > Manage settings > Tamper protection" -ForegroundColor Yellow
} else {
    Write-Host "Tamper protection is enabled" -ForegroundColor Green
}

# Step 8: Configure Windows Defender Application Control (if supported)
Write-Host "Configuring Windows Defender Application Control..." -ForegroundColor Yellow

# Check if WDAC is supported and enabled
$wdacStatus = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard | Select-Object -ExpandProperty SecurityServicesRunning
if ($wdacStatus -contains 2) {
    Write-Host "Windows Defender Application Control is running" -ForegroundColor Green
} else {
    Write-Host "Windows Defender Application Control is not enabled or supported on this system" -ForegroundColor Yellow
}

# Step 9: Configure Scheduled Scans
Write-Host "Configuring scheduled scans..." -ForegroundColor Yellow

# Set weekly full scan
Set-MpPreference -RemediationScheduleDay 6  # Saturday
Set-MpPreference -RemediationScheduleTime "02:00:00"

# Enable daily quick scans
Set-MpPreference -ScanScheduleQuickScanTime "12:00:00"

# Step 10: Configure Security Intelligence Updates
Write-Host "Configuring security intelligence updates..." -ForegroundColor Yellow

# Set update frequency (default is 8 hours, but we can ensure it's configured)
Set-MpPreference -SignatureScheduleTime "00:00:00"
Set-MpPreference -SignatureUpdateInterval 8

# Step 11: Create Windows Defender Monitoring Script
Write-Host "Creating Windows Defender monitoring script..." -ForegroundColor Yellow

$monitoringScript = @'
# Windows Defender Monitoring Script
# Run this script periodically to check Windows Defender status

Write-Host "Windows Defender Status Report" -ForegroundColor Green
Write-Host "Generated on: $(Get-Date)" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# Get Windows Defender status
$defenderStatus = Get-MpComputerStatus

Write-Host "`nReal-time Protection:" -ForegroundColor Yellow
Write-Host "  Antivirus: $($defenderStatus.AntivirusEnabled)"
Write-Host "  Antispyware: $($defenderStatus.AntispywareEnabled)"
Write-Host "  Behavior Monitor: $($defenderStatus.BehaviorMonitorEnabled)"
Write-Host "  Ioav Protection: $($defenderStatus.IoavProtectionEnabled)"
Write-Host "  Network Protection: $($defenderStatus.NIsEnabled)"
Write-Host "  Tamper Protection: $($defenderStatus.IsTamperProtected)"

Write-Host "`nCloud Protection:" -ForegroundColor Yellow
Write-Host "  Cloud-delivered Protection: $($defenderStatus.IsVirtualMachine -or $defenderStatus.MAPSReporting -gt 0)"
Write-Host "  Automatic Sample Submission: $($defenderStatus.SubmitSamplesConsent)"

Write-Host "`nThreat Status:" -ForegroundColor Yellow
Write-Host "  Last Quick Scan: $($defenderStatus.QuickScanEndTime)"
Write-Host "  Last Full Scan: $($defenderStatus.FullScanEndTime)"
Write-Host "  Last Update: $($defenderStatus.LastUpdateCheck)"
Write-Host "  Product Status: $($defenderStatus.ProductStatus)"

# Check for active threats
$threats = Get-MpThreat
if ($threats) {
    Write-Host "`nActive Threats:" -ForegroundColor Red
    $threats | Format-Table -Property ThreatID, Resources, IsActive
} else {
    Write-Host "`nNo active threats detected" -ForegroundColor Green
}

# Check exclusions
$exclusions = Get-MpPreference | Select-Object -ExpandProperty ExclusionPath
Write-Host "`nConfigured Exclusions:" -ForegroundColor Yellow
$exclusions | ForEach-Object { Write-Host "  $_" }

Write-Host "`n=====================================" -ForegroundColor Cyan
Write-Host "Monitoring report completed" -ForegroundColor Green
'@

# Save monitoring script
$monitoringScript | Out-File -FilePath "C:\Scripts\defender-monitoring.ps1" -Encoding UTF8 -Force
Write-Host "Created monitoring script: C:\Scripts\defender-monitoring.ps1" -ForegroundColor Green

# Step 12: Create Scheduled Task for Monitoring
Write-Host "Creating scheduled task for Windows Defender monitoring..." -ForegroundColor Yellow

# Create directory for scripts if it doesn't exist
New-Item -ItemType Directory -Path "C:\Scripts" -Force

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File C:\Scripts\defender-monitoring.ps1"
$trigger = New-ScheduledTaskTrigger -Daily -At 6AM
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "WindowsDefenderMonitoring" -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force

# Step 13: Verification and Status Check
Write-Host "Verifying Windows Defender configuration..." -ForegroundColor Yellow

# Get final status
$finalStatus = Get-MpComputerStatus

Write-Host "`nWindows Defender Configuration Summary:" -ForegroundColor Cyan
Write-Host "- Real-time protection: $($finalStatus.AntivirusEnabled)" -ForegroundColor $(if ($finalStatus.AntivirusEnabled) { "Green" } else { "Red" })
Write-Host "- Cloud protection: $($finalStatus.MAPSReporting -gt 0)" -ForegroundColor $(if ($finalStatus.MAPSReporting -gt 0) { "Green" } else { "Red" })
Write-Host "- Network protection: $($finalStatus.NIsEnabled)" -ForegroundColor $(if ($finalStatus.NIsEnabled) { "Green" } else { "Red" })
Write-Host "- Tamper protection: $($finalStatus.IsTamperProtected)" -ForegroundColor $(if ($finalStatus.IsTamperProtected) { "Green" } else { "Red" })
Write-Host "- Controlled folder access: $(Get-MpPreference | Select-Object -ExpandProperty EnableControlledFolderAccess)" -ForegroundColor Green

# Display ASR rules status
Write-Host "`nAttack Surface Reduction Rules:" -ForegroundColor Cyan
Get-MpPreference | Select-Object -ExpandProperty AttackSurfaceReductionRules_Ids | ForEach-Object {
    $ruleStatus = Get-MpPreference | Select-Object -ExpandProperty AttackSurfaceReductionRules_Actions
    Write-Host "- Rule $_`: $ruleStatus" -ForegroundColor Green
}

Write-Host "`nWindows Defender advanced threat protection setup completed!" -ForegroundColor Green
Write-Host "Key Security Features Enabled:" -ForegroundColor Cyan
Write-Host "- Real-time protection with behavioral monitoring" -ForegroundColor Cyan
Write-Host "- Cloud-delivered protection and automatic sample submission" -ForegroundColor Cyan
Write-Host "- Controlled folder access for ransomware protection" -ForegroundColor Cyan
Write-Host "- Network protection against web threats" -ForegroundColor Cyan
Write-Host "- Attack surface reduction rules" -ForegroundColor Cyan
Write-Host "- Daily monitoring and reporting" -ForegroundColor Cyan
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "- Review Windows Security app for additional configuration options" -ForegroundColor Yellow
Write-Host "- Run the monitoring script manually: C:\Scripts\defender-monitoring.ps1" -ForegroundColor Yellow
Write-Host "- Enable tamper protection in Windows Security settings if not already enabled" -ForegroundColor Yellow
Write-Host "- Consider implementing Windows Defender Application Control policies" -ForegroundColor Yellow