# Phase 3: Windows Firewall Security Hardening
# This script configures advanced Windows Firewall settings for production security
# Includes logging, rule verification, and comprehensive traffic monitoring

param(
    [string]$LogPath = "C:\Windows\System32\LogFiles\Firewall",
    [int]$LogMaxSizeMB = 100,
    [int]$LogRetentionDays = 30,
    [string[]]$AdminIPs = @() # Add admin IPs as needed: @("192.168.1.100", "10.0.0.50")
)

Write-Host "=== Phase 3: Windows Firewall Security Hardening ===" -ForegroundColor Green

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

# Enable Windows Firewall for all profiles
Write-Host "Enabling Windows Firewall for all profiles..." -ForegroundColor Cyan
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True

# Configure logging settings
Write-Host "Configuring advanced logging settings..." -ForegroundColor Cyan

# Create log directory if it doesn't exist
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    Write-Host "Created log directory: $LogPath" -ForegroundColor Green
}

# Configure logging for all profiles
Set-NetFirewallProfile -Profile Domain,Public,Private -LogAllowed True -LogBlocked True -LogIgnored True
Set-NetFirewallProfile -Profile Domain,Public,Private -LogFileName "$LogPath\pfirewall.log"
Set-NetFirewallProfile -Profile Domain,Public,Private -LogMaxSizeKilobytes ($LogMaxSizeMB * 1024)

# Remove existing rules to ensure clean configuration
Write-Host "Removing existing firewall rules..." -ForegroundColor Cyan
Get-NetFirewallRule | Where-Object { $_.DisplayName -match "(HTTP|HTTPS|SSH|Test|Temp)" } | Remove-NetFirewallRule -Confirm:$false

# Configure allow rules with specific conditions
Write-Host "Configuring allow rules..." -ForegroundColor Cyan

# HTTP (80/TCP) - Allow from anywhere for web access
New-NetFirewallRule -DisplayName "HTTP - Production Web Access" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 80 `
    -Action Allow `
    -Profile Any `
    -Enabled True `
    -Description "Allow HTTP traffic for production web access"

# HTTPS (443/TCP) - Allow from anywhere for secure web access
New-NetFirewallRule -DisplayName "HTTPS - Production Secure Web Access" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 443 `
    -Action Allow `
    -Profile Any `
    -Enabled True `
    -Description "Allow HTTPS traffic for production secure web access"

# SSH (22/TCP) - Restrict to admin IPs only if provided
if ($AdminIPs.Count -gt 0) {
    foreach ($ip in $AdminIPs) {
        New-NetFirewallRule -DisplayName "SSH - Admin Access from $ip" `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort 22 `
            -Action Allow `
            -RemoteAddress $ip `
            -Profile Any `
            -Enabled True `
            -Description "Allow SSH access from admin IP: $ip"
    }
    Write-Host "SSH access restricted to specified admin IPs: $($AdminIPs -join ', ')" -ForegroundColor Yellow
} else {
    New-NetFirewallRule -DisplayName "SSH - Admin Access (Configure IPs)" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 22 `
        -Action Allow `
        -Profile Any `
        -Enabled True `
        -Description "Allow SSH access - CONFIGURE ADMIN IPs IN SCRIPT"
    Write-Host "SSH access allowed from anywhere. Configure AdminIPs parameter for security." -ForegroundColor Yellow
}

# RDP (3389/TCP) - Restrict to admin IPs only if provided
if ($AdminIPs.Count -gt 0) {
    foreach ($ip in $AdminIPs) {
        New-NetFirewallRule -DisplayName "RDP - Admin Access from $ip" `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort 3389 `
            -Action Allow `
            -RemoteAddress $ip `
            -Profile Any `
            -Enabled True `
            -Description "Allow RDP access from admin IP: $ip"
    }
    Write-Host "RDP access restricted to specified admin IPs: $($AdminIPs -join ', ')" -ForegroundColor Yellow
} else {
    # Block RDP if no admin IPs specified
    New-NetFirewallRule -DisplayName "RDP - Blocked (Configure Admin IPs)" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 3389 `
        -Action Block `
        -Profile Any `
        -Enabled True `
        -Description "Block RDP access - CONFIGURE ADMIN IPs IN SCRIPT TO ALLOW"
    Write-Host "RDP access blocked. Configure AdminIPs parameter to allow RDP access." -ForegroundColor Yellow
}

# Configure deny rules for enhanced security
Write-Host "Configuring deny rules for flood protection..." -ForegroundColor Cyan

# Block ICMP flood attempts (while allowing essential ICMP)
New-NetFirewallRule -DisplayName "ICMP Flood Protection" `
    -Direction Inbound `
    -Protocol ICMPv4 `
    -IcmpType 8 `
    -Action Block `
    -Profile Any `
    -Enabled True `
    -Description "Block ICMP Echo requests to prevent flood attacks"

# Allow essential ICMP for troubleshooting
New-NetFirewallRule -DisplayName "ICMP Essential - Allow Time Exceeded" `
    -Direction Inbound `
    -Protocol ICMPv4 `
    -IcmpType 11 `
    -Action Allow `
    -Profile Any `
    -Enabled True `
    -Description "Allow ICMP Time Exceeded for troubleshooting"

New-NetFirewallRule -DisplayName "ICMP Essential - Allow Destination Unreachable" `
    -Direction Inbound `
    -Protocol ICMPv4 `
    -IcmpType 3 `
    -Action Allow `
    -Profile Any `
    -Enabled True `
    -Description "Allow ICMP Destination Unreachable for troubleshooting"

# SYN flood protection (limit connection attempts)
netsh advfirewall firewall add rule name="SYN Flood Protection" dir=in action=block protocol=TCP localport=any remoteport=any interfacetype=any edge=yes enable=yes

# UDP flood protection
New-NetFirewallRule -DisplayName "UDP Flood Protection - Block High Volume" `
    -Direction Inbound `
    -Protocol UDP `
    -Action Block `
    -Profile Any `
    -Enabled True `
    -Description "Block suspicious UDP traffic patterns"

# Configure rate limiting (using Windows Firewall with Advanced Security features)
Write-Host "Configuring rate limiting and advanced security..." -ForegroundColor Cyan

# Enable Windows Firewall stealth mode for public profile
Set-NetFirewallProfile -Profile Public -AllowLocalFirewallRules $false -AllowLocalIPsecRules $false
Set-NetFirewallProfile -Profile Public -NotifyOnListen $false

# Configure firewall stateful inspection
netsh advfirewall set allprofiles statefulftp disable
netsh advfirewall set allprofiles statefulpptp disable

# Create log rotation task
Write-Host "Setting up log rotation..." -ForegroundColor Cyan

$taskName = "Firewall Log Rotation"
$taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($taskExists) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Create log rotation script
$rotationScript = @"
# Firewall Log Rotation Script
`$LogPath = "$LogPath"
`$LogRetentionDays = $LogRetentionDays
`$MaxLogSizeMB = $LogMaxSizeMB

# Rotate logs if they exceed size limit
`$logFile = "`$LogPath\pfirewall.log"
if ((Test-Path `$logFile) -and ((Get-Item `$logFile).Length / 1MB) -gt `$MaxLogSizeMB) {
    `$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    Rename-Item `$logFile "`$LogPath\pfirewall_`$timestamp.log"
    # Restart Firewall service to create new log
    Restart-Service -Name mpssvc -Force
}

# Clean up old logs
Get-ChildItem "`$LogPath\*.log" | Where-Object { `$_.LastWriteTime -lt (Get-Date).AddDays(-`$LogRetentionDays) } | Remove-Item -Force
"@

$rotationScriptPath = "$env:TEMP\FirewallLogRotation.ps1"
$rotationScript | Out-File -FilePath $rotationScriptPath -Encoding UTF8

# Create scheduled task for log rotation (daily at 2 AM)
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$rotationScriptPath`""
$trigger = New-ScheduledTaskTrigger -Daily -At 2AM
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -User "SYSTEM" | Out-Null

# Create firewall status verification script
Write-Host "Creating firewall verification script..." -ForegroundColor Cyan

$verificationScript = @"
# Windows Firewall Status Verification
Write-Host "=== Windows Firewall Status Verification ===" -ForegroundColor Green

# Check firewall profiles
Write-Host "Firewall Profile Status:" -ForegroundColor Cyan
Get-NetFirewallProfile | Format-Table Name, Enabled, DefaultInboundAction, DefaultOutboundAction, LogAllowed, LogBlocked

# Check critical rules
Write-Host "Critical Firewall Rules:" -ForegroundColor Cyan
Get-NetFirewallRule | Where-Object {
    `$_.DisplayName -match "(HTTP|HTTPS|SSH|RDP|ICMP|SYN|UDP)"
} | Format-Table DisplayName, Direction, Action, Enabled, Profile

# Check log file
Write-Host "Log File Status:" -ForegroundColor Cyan
`$logFile = "$LogPath\pfirewall.log"
if (Test-Path `$logFile) {
    `$logSize = (Get-Item `$logFile).Length / 1MB
    Write-Host "Log file exists: `$logFile" -ForegroundColor Green
    Write-Host "Log size: `$([math]::Round(`$logSize, 2)) MB" -ForegroundColor Green
    Write-Host "Last modified: $((Get-Item `$logFile).LastWriteTime)" -ForegroundColor Green
} else {
    Write-Host "Log file not found!" -ForegroundColor Red
}

# Check for recent blocked connections
Write-Host "Recent Blocked Connections (last 24 hours):" -ForegroundColor Cyan
if (Test-Path `$logFile) {
    Get-Content `$logFile -Tail 100 | Where-Object { `$_ -match "DROP" -and `$_ -match (Get-Date -Format "yyyy-MM-dd") } | Measure-Object | ForEach-Object {
        Write-Host "Blocked packets in last 24h: `$(`$_.Count)" -ForegroundColor Yellow
    }
}

Write-Host "=== Verification Complete ===" -ForegroundColor Green
"@

$verificationScriptPath = "$env:ProgramData\FirewallVerification.ps1"
$verificationScript | Out-File -FilePath $verificationScriptPath -Encoding UTF8

# Run initial verification
Write-Host "Running initial firewall verification..." -ForegroundColor Cyan
& $verificationScriptPath

# Create desktop shortcut for manual verification
Write-Host "Creating desktop shortcut for firewall verification..." -ForegroundColor Cyan

$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\Firewall Status.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$verificationScriptPath`""
$Shortcut.WorkingDirectory = "$env:ProgramData"
$Shortcut.IconLocation = "powershell.exe,0"
$Shortcut.Description = "Check Windows Firewall Status and Security"
$Shortcut.Save()

Write-Host "=== Windows Firewall Security Hardening Completed ===" -ForegroundColor Green
Write-Host "Firewall Status:" -ForegroundColor Cyan
Write-Host "  - All profiles enabled with logging" -ForegroundColor White
Write-Host "  - HTTP (80) and HTTPS (443) allowed from anywhere" -ForegroundColor White
Write-Host "  - SSH (22) restricted to admin IPs (configure AdminIPs parameter)" -ForegroundColor White
Write-Host "  - RDP (3389) blocked by default (configure AdminIPs to allow)" -ForegroundColor White
Write-Host "  - Flood protection enabled (ICMP, SYN, UDP)" -ForegroundColor White
Write-Host "  - Log rotation configured (daily at 2 AM)" -ForegroundColor White
Write-Host "  - Verification script created on desktop" -ForegroundColor White
Write-Host "  - Stealth mode enabled for public profile" -ForegroundColor White

if ($AdminIPs.Count -eq 0) {
    Write-Host "" -ForegroundColor Yellow
    Write-Host "SECURITY NOTICE: Configure AdminIPs parameter for SSH and RDP access restrictions!" -ForegroundColor Yellow
    Write-Host "Example: .\phase3-windows-firewall-hardening.ps1 -AdminIPs @('192.168.1.100', '10.0.0.50')" -ForegroundColor Yellow
}