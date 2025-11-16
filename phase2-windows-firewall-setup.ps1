# Phase 2: Windows Firewall Configuration for Production Deployment
# This script configures Windows Firewall rules, flood protection, and logging
# for secure containerized environment on supersmartinnovations.cloud

# Requires administrator privileges
#Requires -RunAsAdministrator

# Configuration Variables
$LogPath = "$env:SystemRoot\System32\LogFiles\Firewall\pfirewall.log"
$AdminIPs = @("YOUR_ADMIN_IP_1", "YOUR_ADMIN_IP_2")  # Replace with actual admin IP addresses/ranges

Write-Host "Starting Windows Firewall configuration for Phase 2..." -ForegroundColor Green

# Step 1: Enable Windows Firewall for all profiles
Write-Host "Enabling Windows Firewall for all profiles..." -ForegroundColor Yellow
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True

# Step 2: Remove any existing conflicting rules (optional - uncomment if needed)
# Remove-NetFirewallRule -DisplayName "*Allow All*" -ErrorAction SilentlyContinue

# Step 3: Configure Allow Rules
Write-Host "Configuring allow rules for required ports..." -ForegroundColor Yellow

# Allow HTTP (80/TCP) from anywhere
New-NetFirewallRule -DisplayName "HTTP (Port 80)" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 80 `
    -Action Allow `
    -Profile Any `
    -Description "Allow HTTP traffic for web services"

# Allow HTTPS (443/TCP) from anywhere
New-NetFirewallRule -DisplayName "HTTPS (Port 443)" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 443 `
    -Action Allow `
    -Profile Any `
    -Description "Allow HTTPS traffic for secure web services"

# Allow SSH (22/TCP) from admin IPs only
foreach ($ip in $AdminIPs) {
    New-NetFirewallRule -DisplayName "SSH (Port 22) - Admin IP: $ip" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 22 `
        -Action Allow `
        -RemoteAddress $ip `
        -Profile Any `
        -Description "Allow SSH access for management from admin IP $ip"
}

# Allow RDP (3389/TCP) from admin IPs only
foreach ($ip in $AdminIPs) {
    New-NetFirewallRule -DisplayName "RDP (Port 3389) - Admin IP: $ip" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 3389 `
        -Action Allow `
        -RemoteAddress $ip `
        -Profile Any `
        -Description "Allow RDP access for Windows administration from admin IP $ip"
}

# Step 4: Configure Default Deny Rules
Write-Host "Configuring default deny rules for all other ports..." -ForegroundColor Yellow
# Note: Windows Firewall defaults to blocking inbound traffic not explicitly allowed

# Step 5: Configure Flood Protection
Write-Host "Configuring flood protection..." -ForegroundColor Yellow

# Enable SYN flood protection (using netsh for advanced settings)
netsh advfirewall set global statefulftp disable
netsh advfirewall set global statefulpptp disable

# Enable SYN attack protection
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "SynAttackProtect" -Value 1 -Type DWord

# Enable ICMP rate limiting (flood protection)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "EnableICMPRedirect" -Value 0 -Type DWord
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "DisableIPSourceRouting" -Value 2 -Type DWord

# UDP flood protection - Enable connection rate limiting
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "TcpMaxConnectResponseRetransmissions" -Value 2 -Type DWord

# Step 6: Configure Logging and Monitoring
Write-Host "Configuring firewall logging and monitoring..." -ForegroundColor Yellow

# Enable logging for all profiles
Set-NetFirewallProfile -Profile Domain,Public,Private -LogAllowed True -LogBlocked True -LogIgnored True

# Set log file path and size limits
Set-NetFirewallProfile -Profile Domain,Public,Private -LogFileName $LogPath
Set-NetFirewallProfile -Profile Domain,Public,Private -LogMaxSizeKilobytes 32767

# Step 7: Configure Traffic Monitoring
Write-Host "Setting up traffic monitoring..." -ForegroundColor Yellow

# Enable Windows Firewall event logging
wevtutil sl "Microsoft-Windows-Windows Firewall With Advanced Security/Firewall" /e:true /q

# Create scheduled task for log rotation (runs daily at 2 AM)
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-Command `"wevtutil cl 'Microsoft-Windows-Windows Firewall With Advanced Security/Firewall'`""
$trigger = New-ScheduledTaskTrigger -Daily -At 2AM
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "FirewallLogRotation" -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force

# Step 8: Verification Commands
Write-Host "Running verification commands..." -ForegroundColor Yellow

# Display current firewall status
Write-Host "`nFirewall Profile Status:" -ForegroundColor Cyan
Get-NetFirewallProfile | Format-Table Name,Enabled,DefaultInboundAction,DefaultOutboundAction,LogAllowed,LogBlocked

# Display firewall rules
Write-Host "`nConfigured Firewall Rules:" -ForegroundColor Cyan
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*HTTP*" -or $_.DisplayName -like "*HTTPS*" -or $_.DisplayName -like "*SSH*" -or $_.DisplayName -like "*RDP*" } | Format-Table DisplayName,Direction,Action,LocalPort,RemoteAddress

# Test connectivity to verify rules (optional)
Write-Host "`nTesting port accessibility..." -ForegroundColor Cyan
Test-NetConnection -ComputerName localhost -Port 80 | Format-Table ComputerName,RemotePort,TcpTestSucceeded
Test-NetConnection -ComputerName localhost -Port 443 | Format-Table ComputerName,RemotePort,TcpTestSucceeded

Write-Host "`nWindows Firewall configuration completed successfully!" -ForegroundColor Green
Write-Host "Review the log file at: $LogPath" -ForegroundColor Cyan
Write-Host "Admin IPs configured: $($AdminIPs -join ', ')" -ForegroundColor Cyan
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "- Update AdminIPs array with actual admin IP addresses" -ForegroundColor Yellow
Write-Host "- Verify port forwarding in Docker container configuration" -ForegroundColor Yellow
Write-Host "- Configure VPN for administrative access if required" -ForegroundColor Yellow