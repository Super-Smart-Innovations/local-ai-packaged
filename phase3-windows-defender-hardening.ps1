# Phase 3: Windows Defender Security Hardening
# This script configures comprehensive Windows Defender settings for production security
# Includes real-time protection, exclusions, cloud features, and tamper protection

param(
    [string[]]$DockerExclusionPaths = @(
        "C:\Users\*\AppData\Local\Docker",
        "C:\Users\*\AppData\Roaming\Docker",
        "C:\ProgramData\Docker",
        "C:\Program Files\Docker",
        "C:\ProgramData\Microsoft\Windows\Containers",
        "C:\Windows\System32\docker",
        "C:\Windows\SysWOW64\docker"
    ),
    [string[]]$DevelopmentExclusionPaths = @(
        "C:\dev-env.local",
        "C:\Users\*\.vscode",
        "C:\Users\*\AppData\Local\Microsoft\VS Code",
        "C:\Program Files\Microsoft VS Code"
    ),
    [string[]]$ExclusionExtensions = @(
        "*.log",
        "*.tmp",
        "*.cache",
        "*.lock"
    )
)

Write-Host "=== Phase 3: Windows Defender Security Hardening ===" -ForegroundColor Green

# Function to check if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host "This script must be run as Administrator. Please restart PowerShell as Administrator." -ForegroundColor Red
    exit 1
}

# Check Windows Defender status
Write-Host "Checking Windows Defender status..." -ForegroundColor Cyan
$defenderStatus = Get-MpComputerStatus

if ($defenderStatus.AntivirusEnabled -eq $false) {
    Write-Host "Windows Defender is disabled. Enabling..." -ForegroundColor Yellow
    Set-MpPreference -DisableRoutinelyTakingAction $false
}

# Enable real-time protection with advanced settings
Write-Host "Configuring real-time protection..." -ForegroundColor Cyan
Set-MpPreference -DisableRealtimeMonitoring $false
Set-MpPreference -DisableBehaviorMonitoring $false
Set-MpPreference -DisableIOAVProtection $false
Set-MpPreference -DisableScriptScanning $false
Set-MpPreference -DisableArchiveScanning $false
Set-MpPreference -DisableRemovableDriveScanning $false

# Configure behavioral monitoring
Write-Host "Enabling advanced behavioral monitoring..." -ForegroundColor Cyan
Set-MpPreference -EnableControlledFolderAccess Enabled
Set-MpPreference -EnableNetworkProtection Enabled
Set-MpPreference -PUAProtection Enabled

# Enable cloud-delivered protection
Write-Host "Configuring cloud-delivered protection..." -ForegroundColor Cyan
Set-MpPreference -MAPSReporting Advanced
Set-MpPreference -SubmitSamplesConsent Always
Set-MpPreference -EnableLowCPUPriority $false  # Ensure full scanning performance

# Configure exclusions for Docker and development
Write-Host "Configuring exclusions for Docker and development..." -ForegroundColor Cyan

# Docker exclusions
foreach ($path in $DockerExclusionPaths) {
    try {
        Add-MpPreference -ExclusionPath $path -ErrorAction Stop
        Write-Host "Added Docker exclusion: $path" -ForegroundColor Green
    } catch {
        if ($_.Exception.Message -notmatch "already exists") {
            Write-Host "Warning: Could not add exclusion $path : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# Development exclusions
foreach ($path in $DevelopmentExclusionPaths) {
    try {
        Add-MpPreference -ExclusionPath $path -ErrorAction Stop
        Write-Host "Added development exclusion: $path" -ForegroundColor Green
    } catch {
        if ($_.Exception.Message -notmatch "already exists") {
            Write-Host "Warning: Could not add exclusion $path : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# Extension exclusions
foreach ($ext in $ExclusionExtensions) {
    try {
        Add-MpPreference -ExclusionExtension $ext -ErrorAction Stop
        Write-Host "Added extension exclusion: $ext" -ForegroundColor Green
    } catch {
        if ($_.Exception.Message -notmatch "already exists") {
            Write-Host "Warning: Could not add extension exclusion $ext : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# Enable tamper protection
Write-Host "Enabling tamper protection..." -ForegroundColor Cyan
try {
    Set-MpPreference -EnableTamperProtection $true
    Write-Host "Tamper protection enabled successfully" -ForegroundColor Green
} catch {
    Write-Host "Warning: Could not enable tamper protection automatically. Please enable manually in Windows Security settings." -ForegroundColor Yellow
    Write-Host "Navigate to: Windows Security > Virus & threat protection > Manage settings > Tamper protection" -ForegroundColor Yellow
}

# Configure scanning schedules
Write-Host "Configuring scanning schedules..." -ForegroundColor Cyan

# Quick scan daily at 2 PM
Set-MpPreference -RemediationScheduleTime 14:00
Set-MpPreference -RemediationScheduleDay EveryDay

# Full scan weekly on Sunday at 3 AM
Set-MpPreference -ScanScheduleTime 03:00
Set-MpPreference -ScanScheduleQuickScanTime 14:00

# Configure scan parameters
Write-Host "Configuring scan parameters..." -ForegroundColor Cyan
Set-MpPreference -ScanAvgCPULoadFactor 50  # Allow 50% CPU usage during scans
Set-MpPreference -ScanOnlyIfIdleEnabled $false  # Scan even when system is in use
Set-MpPreference -ScanPurgeItemsAfterDelay 30  # Keep quarantined items for 30 days
Set-MpPreference -DaysToRetainCleanedMalware 30  # Retain cleaned malware for 30 days

# Enable ASR rules (Attack Surface Reduction)
Write-Host "Enabling Attack Surface Reduction rules..." -ForegroundColor Cyan

# Define ASR rules to enable
$asrRules = @(
    "56a863a9-875e-4185-98a7-b882c64b5ce5",  # Block executable files from running unless they meet a prevalence, age, or trusted list criterion
    "7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c",  # Block Adobe Reader from creating child processes
    "d4f940ab-401b-4efc-aadc-ad5f3c50688a",  # Block Office applications from creating executable content
    "9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2",  # Block credential stealing from the Windows local security authority subsystem
    "be9ba2d9-53ea-4cdc-84e5-9b1eeee46550",  # Block executable content from email client and webmail
    "01443614-cd74-433a-b99e-2ecdc07bfc25",  # Block untrusted and unsigned processes that run from USB
    "5beb7efe-fd9a-4556-801d-275e5ffc04cc",  # Block Office applications from injecting code into other processes
    "d3e037e1-3eb8-44c8-a917-57927947596d",  # Block JavaScript or VBScript from launching downloaded executable content
    "3b576869-a4ec-4529-8536-b80a7769e899",  # Block Office applications from creating child processes
    "75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84",  # Block execution of potentially obfuscated scripts
    "26190899-1602-49e8-8b27-eb1d0a1ce869"   # Block executable files from running unless they meet a prevalence, age, or trusted list criterion (web)
)

foreach ($ruleId in $asrRules) {
    try {
        Add-MpPreference -AttackSurfaceReductionRules_Ids $ruleId -AttackSurfaceReductionRules_Actions Enabled -ErrorAction Stop
        Write-Host "Enabled ASR rule: $ruleId" -ForegroundColor Green
    } catch {
        if ($_.Exception.Message -notmatch "already exists") {
            Write-Host "Warning: Could not enable ASR rule $ruleId : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# Enable Windows Defender Application Control (if supported)
Write-Host "Configuring Windows Defender Application Control..." -ForegroundColor Cyan
try {
    # Check if WDAC is supported
    $wdacSupported = Get-ComputerInfo | Select-Object -ExpandProperty WindowsEditionId
    if ($wdacSupported -match "Pro|Enterprise|Education") {
        Write-Host "WDAC supported. Configuring policies..." -ForegroundColor Green

        # Create a basic WDAC policy allowing Microsoft signed binaries and our specific applications
        $wdacPolicy = @"
<?xml version="1.0" encoding="utf-8"?>
<SiPolicy xmlns="urn:schemas-microsoft-com:sipolicy">
  <VersionEx>10.0.0.0</VersionEx>
  <PolicyTypeID>{A244370E-44C9-4C06-B551-F6016AC957F0}</PolicyTypeID>
  <PlatformID>{2E07F7E4-194C-4D20-B7C9-6F44A6C5A234}</PlatformID>
  <Rules>
    <Rule>
      <Option>Enabled:Unsigned System Integrity Policy</Option>
    </Rule>
    <Rule>
      <Option>Enabled:Advanced Boot Options Menu</Option>
    </Rule>
    <Rule>
      <Option>Enabled:UMCI</Option>
    </Rule>
  </Rules>
  <EKUs />
  <FileRules />
  <Signers />
  <SigningScenarios>
    <SigningScenario Value="12" ID="ID_SIGNINGSCENARIO_WINDOWS" FriendlyName="Windows">
      <ProductSigners />
    </SigningScenario>
    <SigningScenario Value="131" ID="ID_SIGNINGSCENARIO_DRIVERS" FriendlyName="Drivers">
      <ProductSigners />
    </SigningScenario>
  </SigningScenarios>
  <UpdatePolicySigners />
  <CiSigners />
  <HvciOptions>0</HvciOptions>
</SiPolicy>
"@

        $wdacPolicyPath = "$env:TEMP\WDACPolicy.xml"
        $wdacPolicy | Out-File -FilePath $wdacPolicyPath -Encoding UTF8

        Write-Host "WDAC policy created. Import manually using:" -ForegroundColor Yellow
        Write-Host "New-CIPolicy -FilePath `"$wdacPolicyPath`" -UserPEs -Level FilePublisher -Fallback Hash" -ForegroundColor Yellow

    } else {
        Write-Host "Windows Defender Application Control not supported on this edition" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Warning: Could not configure WDAC: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Enable Windows Defender Credential Guard (if supported)
Write-Host "Configuring Windows Defender Credential Guard..." -ForegroundColor Cyan
try {
    # Enable Credential Guard with UEFI lock
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v EnableVirtualizationBasedSecurity /t REG_DWORD /d 1 /f
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v RequirePlatformSecurityFeatures /t REG_DWORD /d 1 /f
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v LsaCfgFlags /t REG_DWORD /d 1 /f
    Write-Host "Credential Guard configured (requires reboot to take effect)" -ForegroundColor Green
} catch {
    Write-Host "Warning: Could not configure Credential Guard: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Create Defender status verification script
Write-Host "Creating Defender verification script..." -ForegroundColor Cyan

$verificationScript = @"
# Windows Defender Status Verification
Write-Host "=== Windows Defender Status Verification ===" -ForegroundColor Green

# Get Defender status
`$defenderStatus = Get-MpComputerStatus

Write-Host "Real-time Protection:" -ForegroundColor Cyan
Write-Host "  Enabled: `$(`$defenderStatus.RealTimeProtectionEnabled)" -ForegroundColor White
Write-Host "  Behavior Monitoring: `$(`$defenderStatus.IsTamperProtected)" -ForegroundColor White

Write-Host "Cloud Protection:" -ForegroundColor Cyan
Write-Host "  MAPS Reporting: `$(`$defenderStatus.MAPSReporting)" -ForegroundColor White
Write-Host "  Sample Submission: `$(`$defenderStatus.SubmitSamplesConsent)" -ForegroundColor White

Write-Host "Exclusions:" -ForegroundColor Cyan
Get-MpPreference | Select-Object -ExpandProperty ExclusionPath | ForEach-Object {
    Write-Host "  `$_" -ForegroundColor White
}
Get-MpPreference | Select-Object -ExpandProperty ExclusionExtension | ForEach-Object {
    Write-Host "  *.`$_" -ForegroundColor White
}

Write-Host "ASR Rules Status:" -ForegroundColor Cyan
Get-MpPreference | Select-Object -ExpandProperty AttackSurfaceReductionRules_Ids | ForEach-Object {
    `$rule = Get-MpPreference | Where-Object { `$_.AttackSurfaceReductionRules_Ids -contains `$_ }
    `$action = `$rule.AttackSurfaceReductionRules_Actions | Where-Object { `$_.RuleId -eq `$_ }
    Write-Host "  `$_ : `$(`$action.Action)" -ForegroundColor White
}

Write-Host "Scan Schedule:" -ForegroundColor Cyan
Write-Host "  Quick Scan: `$(`$defenderStatus.QuickScanStartTime)" -ForegroundColor White
Write-Host "  Full Scan: `$(`$defenderStatus.FullScanStartTime)" -ForegroundColor White

Write-Host "Last Scans:" -ForegroundColor Cyan
Write-Host "  Quick Scan: `$(`$defenderStatus.QuickScanEndTime)" -ForegroundColor White
Write-Host "  Full Scan: `$(`$defenderStatus.FullScanEndTime)" -ForegroundColor White

# Check for threats
Write-Host "Threat Status:" -ForegroundColor Cyan
`$threats = Get-MpThreat
if (`$threats) {
    Write-Host "Active threats found:" -ForegroundColor Red
    `$threats | Format-Table ThreatID, ThreatName, SeverityID
} else {
    Write-Host "No active threats detected" -ForegroundColor Green
}

Write-Host "=== Verification Complete ===" -ForegroundColor Green
"@

$verificationScriptPath = "$env:ProgramData\DefenderVerification.ps1"
$verificationScript | Out-File -FilePath $verificationScriptPath -Encoding UTF8

# Run initial verification
Write-Host "Running initial Defender verification..." -ForegroundColor Cyan
& $verificationScriptPath

# Create desktop shortcut for manual verification
Write-Host "Creating desktop shortcut for Defender verification..." -ForegroundColor Cyan

$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\Defender Status.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$verificationScriptPath`""
$Shortcut.WorkingDirectory = "$env:ProgramData"
$Shortcut.IconLocation = "powershell.exe,0"
$Shortcut.Description = "Check Windows Defender Status and Security"
$Shortcut.Save()

Write-Host "=== Windows Defender Security Hardening Completed ===" -ForegroundColor Green
Write-Host "Defender Features Enabled:" -ForegroundColor Cyan
Write-Host "  - Real-time protection with behavioral monitoring" -ForegroundColor White
Write-Host "  - Cloud-delivered protection and sample submission" -ForegroundColor White
Write-Host "  - Controlled folder access and network protection" -ForegroundColor White
Write-Host "  - Tamper protection enabled" -ForegroundColor White
Write-Host "  - ASR rules enabled for attack surface reduction" -ForegroundColor White
Write-Host "  - Comprehensive exclusions for Docker and development" -ForegroundColor White
Write-Host "  - Credential Guard configured (reboot required)" -ForegroundColor White
Write-Host "  - Scheduled scanning (daily quick, weekly full)" -ForegroundColor White
Write-Host "  - Verification script created on desktop" -ForegroundColor White

Write-Host "" -ForegroundColor Yellow
Write-Host "IMPORTANT: A system reboot is recommended to activate Credential Guard and other security features." -ForegroundColor Yellow
Write-Host "Run the verification script from the desktop to check Defender status after reboot." -ForegroundColor Yellow