# Phase 2: Network Security Monitoring and Verification
# This script provides comprehensive monitoring and verification
# of network security configuration for the containerized environment

# Requires administrator privileges
#Requires -RunAsAdministrator

# Configuration Variables
$HostIPAddress = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -like "*Ethernet*" -or $_.InterfaceAlias -like "*Wi-Fi*" } | Select-Object -First 1).IPAddress
$LogPath = "$env:SystemRoot\System32\LogFiles\Firewall\pfirewall.log"
$UbuntuContainerName = "ubuntu-server"
$DockerNetworkName = "localai-bridge"
$InternalNetworkName = "localai-internal"
$MonitoringInterval = 300  # 5 minutes in seconds

Write-Host "Starting network security monitoring and verification for Phase 2..." -ForegroundColor Green

# Step 1: Create Monitoring Directory Structure
Write-Host "Creating monitoring directory structure..." -ForegroundColor Yellow

$monitoringDir = "C:\Monitoring\NetworkSecurity"
$logDir = "$monitoringDir\Logs"
$reportDir = "$monitoringDir\Reports"

New-Item -ItemType Directory -Path $monitoringDir -Force
New-Item -ItemType Directory -Path $logDir -Force
New-Item -ItemType Directory -Path $reportDir -Force

# Step 2: Verify Windows Firewall Configuration
Write-Host "Verifying Windows Firewall configuration..." -ForegroundColor Yellow

function Test-FirewallConfiguration {
    param()

    $firewallStatus = @{}

    # Check firewall profiles
    $profiles = Get-NetFirewallProfile
    $firewallStatus.Profiles = $profiles

    # Check key rules
    $httpRule = Get-NetFirewallRule -DisplayName "HTTP (Port 80)" -ErrorAction SilentlyContinue
    $httpsRule = Get-NetFirewallRule -DisplayName "HTTPS (Port 443)" -ErrorAction SilentlyContinue
    $sshRule = Get-NetFirewallRule -DisplayName "SSH (Port 22) - Admin IP*" -ErrorAction SilentlyContinue
    $rdpRule = Get-NetFirewallRule -DisplayName "RDP (Port 3389) - Admin IP*" -ErrorAction SilentlyContinue

    $firewallStatus.Rules = @{
        HTTP = ($httpRule -and $httpRule.Enabled -eq "True")
        HTTPS = ($httpsRule -and $httpsRule.Enabled -eq "True")
        SSH = ($sshRule -and $sshRule.Enabled -eq "True")
        RDP = ($rdpRule -and $rdpRule.Enabled -eq "True")
    }

    # Check logging
    $firewallStatus.Logging = @{
        Enabled = ($profiles[0].LogAllowed -eq "True" -and $profiles[0].LogBlocked -eq "True")
        LogPath = $profiles[0].LogFileName
    }

    return $firewallStatus
}

$firewallTest = Test-FirewallConfiguration
Write-Host "Firewall Status:" -ForegroundColor Cyan
Write-Host "- HTTP Rule: $($firewallTest.Rules.HTTP)" -ForegroundColor $(if ($firewallTest.Rules.HTTP) { "Green" } else { "Red" })
Write-Host "- HTTPS Rule: $($firewallTest.Rules.HTTPS)" -ForegroundColor $(if ($firewallTest.Rules.HTTPS) { "Green" } else { "Red" })
Write-Host "- SSH Rule: $($firewallTest.Rules.SSH)" -ForegroundColor $(if ($firewallTest.Rules.SSH) { "Green" } else { "Red" })
Write-Host "- RDP Rule: $($firewallTest.Rules.RDP)" -ForegroundColor $(if ($firewallTest.Rules.RDP) { "Green" } else { "Red" })
Write-Host "- Logging: $($firewallTest.Logging.Enabled)" -ForegroundColor $(if ($firewallTest.Logging.Enabled) { "Green" } else { "Red" })

# Step 3: Verify Docker Network Configuration
Write-Host "Verifying Docker network configuration..." -ForegroundColor Yellow

function Test-DockerNetworks {
    param()

    $networkStatus = @{}

    # Check if Docker is running
    $dockerService = Get-Service -Name "Docker Desktop Service" -ErrorAction SilentlyContinue
    $networkStatus.DockerRunning = ($dockerService -and $dockerService.Status -eq "Running")

    if ($networkStatus.DockerRunning) {
        # Check networks
        $externalNetwork = docker network inspect $DockerNetworkName 2>$null | ConvertFrom-Json
        $internalNetwork = docker network inspect $InternalNetworkName 2>$null | ConvertFrom-Json

        $networkStatus.ExternalNetwork = ($null -ne $externalNetwork)
        $networkStatus.InternalNetwork = ($null -ne $internalNetwork)

        if ($networkStatus.ExternalNetwork) {
            $networkStatus.ExternalSubnet = $externalNetwork.IPAM.Config[0].Subnet
            $networkStatus.ExternalGateway = $externalNetwork.IPAM.Config[0].Gateway
        }

        if ($networkStatus.InternalNetwork) {
            $networkStatus.InternalSubnet = $internalNetwork.IPAM.Config[0].Subnet
            $networkStatus.InternalGateway = $internalNetwork.IPAM.Config[0].Gateway
        }
    }

    return $networkStatus
}

$dockerTest = Test-DockerNetworks
Write-Host "Docker Network Status:" -ForegroundColor Cyan
Write-Host "- Docker Running: $($dockerTest.DockerRunning)" -ForegroundColor $(if ($dockerTest.DockerRunning) { "Green" } else { "Red" })
Write-Host "- External Network: $($dockerTest.ExternalNetwork)" -ForegroundColor $(if ($dockerTest.ExternalNetwork) { "Green" } else { "Red" })
Write-Host "- Internal Network: $($dockerTest.InternalNetwork)" -ForegroundColor $(if ($dockerTest.InternalNetwork) { "Green" } else { "Red" })

if ($dockerTest.ExternalNetwork) {
    Write-Host "- External Subnet: $($dockerTest.ExternalSubnet)" -ForegroundColor Green
    Write-Host "- External Gateway: $($dockerTest.ExternalGateway)" -ForegroundColor Green
}

if ($dockerTest.InternalNetwork) {
    Write-Host "- Internal Subnet: $($dockerTest.InternalSubnet)" -ForegroundColor Green
    Write-Host "- Internal Gateway: $($dockerTest.InternalGateway)" -ForegroundColor Green
}

# Step 4: Verify Ubuntu Container and Port Forwarding
Write-Host "Verifying Ubuntu container and port forwarding..." -ForegroundColor Yellow

function Test-ContainerConfiguration {
    param()

    $containerStatus = @{}

    # Check if container exists and is running
    $containerInfo = docker ps -a --filter "name=$UbuntuContainerName" --format "{{.Names}}|{{.Status}}|{{.Ports}}" | ConvertFrom-Csv -Delimiter "|" -Header Name,Status,Ports
    $containerStatus.Exists = ($containerInfo -and $containerInfo.Name -eq $UbuntuContainerName)
    $containerStatus.Running = ($containerStatus.Exists -and $containerInfo.Status -like "*Up*")

    if ($containerStatus.Running) {
        # Test port connectivity
        $portsToTest = @(80, 443, 22, 5678, 3000, 3001, 3002, 8080, 7474, 3003)
        $containerStatus.PortTests = @{}

        foreach ($port in $portsToTest) {
            try {
                $tcpClient = New-Object System.Net.Sockets.TcpClient
                $tcpClient.Connect("localhost", $port)
                $containerStatus.PortTests[$port] = $true
                $tcpClient.Close()
            } catch {
                $containerStatus.PortTests[$port] = $false
            }
        }
    }

    return $containerStatus
}

$containerTest = Test-ContainerConfiguration
Write-Host "Ubuntu Container Status:" -ForegroundColor Cyan
Write-Host "- Container Exists: $($containerTest.Exists)" -ForegroundColor $(if ($containerTest.Exists) { "Green" } else { "Red" })
Write-Host "- Container Running: $($containerTest.Running)" -ForegroundColor $(if ($containerTest.Running) { "Green" } else { "Red" })

if ($containerTest.Running) {
    Write-Host "Port Connectivity Tests:" -ForegroundColor Cyan
    foreach ($port in $containerTest.PortTests.Keys) {
        $serviceName = switch ($port) {
            80 { "HTTP" }
            443 { "HTTPS" }
            22 { "SSH" }
            5678 { "N8N" }
            3000 { "Open WebUI" }
            3001 { "Flowise" }
            3002 { "Supabase" }
            8080 { "SearXNG" }
            7474 { "Neo4j" }
            3003 { "Langfuse" }
            default { "Unknown" }
        }
        Write-Host "- Port $port ($serviceName): $($containerTest.PortTests[$port])" -ForegroundColor $(if ($containerTest.PortTests[$port]) { "Green" } else { "Red" })
    }
}

# Step 5: Verify Windows Defender Configuration
Write-Host "Verifying Windows Defender configuration..." -ForegroundColor Yellow

function Test-DefenderConfiguration {
    param()

    $defenderStatus = Get-MpComputerStatus

    return @{
        RealTimeProtection = $defenderStatus.AntivirusEnabled
        CloudProtection = $defenderStatus.MAPSReporting -gt 0
        NetworkProtection = $defenderStatus.NIsEnabled
        TamperProtection = $defenderStatus.IsTamperProtected
        ControlledFolderAccess = (Get-MpPreference).EnableControlledFolderAccess
        ASRRules = (Get-MpPreference).AttackSurfaceReductionRules_Actions.Count -gt 0
    }
}

$defenderTest = Test-DefenderConfiguration
Write-Host "Windows Defender Status:" -ForegroundColor Cyan
Write-Host "- Real-time Protection: $($defenderTest.RealTimeProtection)" -ForegroundColor $(if ($defenderTest.RealTimeProtection) { "Green" } else { "Red" })
Write-Host "- Cloud Protection: $($defenderTest.CloudProtection)" -ForegroundColor $(if ($defenderTest.CloudProtection) { "Green" } else { "Red" })
Write-Host "- Network Protection: $($defenderTest.NetworkProtection)" -ForegroundColor $(if ($defenderTest.NetworkProtection) { "Green" } else { "Red" })
Write-Host "- Tamper Protection: $($defenderTest.TamperProtection)" -ForegroundColor $(if ($defenderTest.TamperProtection) { "Green" } else { "Red" })
Write-Host "- Controlled Folder Access: $($defenderTest.ControlledFolderAccess)" -ForegroundColor $(if ($defenderTest.ControlledFolderAccess) { "Green" } else { "Red" })
Write-Host "- ASR Rules: $($defenderTest.ASRRules)" -ForegroundColor $(if ($defenderTest.ASRRules) { "Green" } else { "Red" })

# Step 6: Generate Security Report
Write-Host "Generating security monitoring report..." -ForegroundColor Yellow

$reportDate = Get-Date -Format "yyyyMMdd_HHmmss"
$reportFile = "$reportDir\NetworkSecurity_Report_$reportDate.txt"

$reportContent = @"
Network Security Monitoring Report
Generated: $(Get-Date)
Host IP: $HostIPAddress
=====================================

WINDOWS FIREWALL STATUS:
- Profiles Enabled: $(($firewallTest.Profiles | Where-Object { $_.Enabled -eq "True" }).Count)/$($firewallTest.Profiles.Count)
- HTTP Rule: $($firewallTest.Rules.HTTP)
- HTTPS Rule: $($firewallTest.Rules.HTTPS)
- SSH Rule: $($firewallTest.Rules.SSH)
- RDP Rule: $($firewallTest.Rules.RDP)
- Logging Enabled: $($firewallTest.Logging.Enabled)
- Log Path: $($firewallTest.Logging.LogPath)

DOCKER NETWORK STATUS:
- Docker Service Running: $($dockerTest.DockerRunning)
- External Network Exists: $($dockerTest.ExternalNetwork)
- Internal Network Exists: $($dockerTest.InternalNetwork)
- External Subnet: $($dockerTest.ExternalSubnet)
- Internal Subnet: $($dockerTest.InternalSubnet)

CONTAINER STATUS:
- Ubuntu Container Exists: $($containerTest.Exists)
- Ubuntu Container Running: $($containerTest.Running)

WINDOWS DEFENDER STATUS:
- Real-time Protection: $($defenderTest.RealTimeProtection)
- Cloud Protection: $($defenderTest.CloudProtection)
- Network Protection: $($defenderTest.NetworkProtection)
- Tamper Protection: $($defenderTest.TamperProtection)
- Controlled Folder Access: $($defenderTest.ControlledFolderAccess)
- Attack Surface Reduction: $($defenderTest.ASRRules)

PORT CONNECTIVITY:
"@

if ($containerTest.Running) {
    foreach ($port in $containerTest.PortTests.Keys) {
        $serviceName = switch ($port) {
            80 { "HTTP" }
            443 { "HTTPS" }
            22 { "SSH" }
            5678 { "N8N" }
            3000 { "Open WebUI" }
            3001 { "Flowise" }
            3002 { "Supabase" }
            8080 { "SearXNG" }
            7474 { "Neo4j" }
            3003 { "Langfuse" }
            default { "Unknown" }
        }
        $reportContent += "`n- Port $port ($serviceName): $($containerTest.PortTests[$port])"
    }
}

$reportContent += @"


FIREWALL LOG SAMPLE (Last 10 entries):
$((Get-Content $LogPath -Tail 10 -ErrorAction SilentlyContinue) -join "`n")

=====================================
End of Report
"@

$reportContent | Out-File -FilePath $reportFile -Encoding UTF8 -Force
Write-Host "Security report saved to: $reportFile" -ForegroundColor Green

# Step 7: Create Continuous Monitoring Script
Write-Host "Creating continuous monitoring script..." -ForegroundColor Yellow

$continuousMonitoringScript = @"
# Continuous Network Security Monitoring Script
# Run this script to monitor network security continuously

param(
    [int]`$IntervalSeconds = $MonitoringInterval
)

Write-Host "Starting continuous network security monitoring..." -ForegroundColor Green
Write-Host "Monitoring interval: `$IntervalSeconds seconds" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop monitoring" -ForegroundColor Yellow

`$logFile = "$logDir\ContinuousMonitoring_`$((Get-Date -Format 'yyyyMMdd')).log"

function Write-MonitorLog {
    param([string]`$Message)
    `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    `$logEntry = "[$timestamp] `$Message"
    Write-Host `$logEntry -ForegroundColor Cyan
    Add-Content -Path `$logFile -Value `$logEntry
}

try {
    while (`$true) {
        # Check firewall status
        `$fwProfiles = Get-NetFirewallProfile | Where-Object { `$_.Enabled -eq 'True' }
        if (`$fwProfiles.Count -lt 3) {
            Write-MonitorLog "WARNING: Not all firewall profiles are enabled"
        }

        # Check container status
        `$containerStatus = docker ps --filter "name=$UbuntuContainerName" --format "{{.Status}}" 2>`$null
        if (`$containerStatus -notlike "*Up*") {
            Write-MonitorLog "WARNING: Ubuntu container is not running"
        }

        # Check key ports
        `$ports = @(80, 443, 22)
        foreach (`$port in `$ports) {
            try {
                `$tcpClient = New-Object System.Net.Sockets.TcpClient
                `$tcpClient.Connect("localhost", `$port)
                `$tcpClient.Close()
            } catch {
                Write-MonitorLog "WARNING: Port `$port is not accessible"
            }
        }

        # Check Windows Defender status
        `$defenderStatus = Get-MpComputerStatus
        if (-not `$defenderStatus.AntivirusEnabled) {
            Write-MonitorLog "WARNING: Windows Defender real-time protection is disabled"
        }

        Start-Sleep -Seconds `$IntervalSeconds
    }
} catch {
    Write-MonitorLog "Monitoring stopped: `$_"
}
"@

$continuousMonitoringScript | Out-File -FilePath "$monitoringDir\ContinuousMonitoring.ps1" -Encoding UTF8 -Force
Write-Host "Continuous monitoring script created: $monitoringDir\ContinuousMonitoring.ps1" -ForegroundColor Green

# Step 8: Create Scheduled Task for Monitoring
Write-Host "Creating scheduled task for continuous monitoring..." -ForegroundColor Yellow

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File $monitoringDir\ContinuousMonitoring.ps1"
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartOnIdle -DontStopOnIdleEnd
Register-ScheduledTask -TaskName "NetworkSecurityMonitoring" -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force

# Step 9: Create Alert System
Write-Host "Setting up basic alert system..." -ForegroundColor Yellow

$alertScript = @'
# Network Security Alert System
# This script checks for critical security issues and sends alerts

$alerts = @()

# Check firewall status
$fwStatus = Get-NetFirewallProfile | Where-Object { $_.Enabled -eq "False" }
if ($fwStatus) {
    $alerts += "CRITICAL: Firewall profile(s) disabled: $($fwStatus.Name -join ', ')"
}

# Check container status
$containerStatus = docker ps --filter "name=ubuntu-server" --format "{{.Status}}" 2>$null
if ($containerStatus -notlike "*Up*") {
    $alerts += "CRITICAL: Ubuntu container is not running"
}

# Check Windows Defender
$defenderStatus = Get-MpComputerStatus
if (-not $defenderStatus.AntivirusEnabled) {
    $alerts += "CRITICAL: Windows Defender real-time protection disabled"
}

# Check for suspicious network activity (basic check)
$recentLogs = Get-Content "C:\Windows\System32\LogFiles\Firewall\pfirewall.log" -Tail 50 -ErrorAction SilentlyContinue
$suspiciousActivity = $recentLogs | Where-Object { $_ -match "DROP" -or $_ -match "BLOCK" }
if ($suspiciousActivity.Count -gt 10) {
    $alerts += "WARNING: High number of blocked connections detected ($($suspiciousActivity.Count) in recent logs)"
}

# Send alerts (placeholder - integrate with your notification system)
if ($alerts.Count -gt 0) {
    Write-Host "Security Alerts Detected:" -ForegroundColor Red
    foreach ($alert in $alerts) {
        Write-Host "- $alert" -ForegroundColor Red

        # TODO: Integrate with your notification system
        # Send-MailMessage, Slack webhook, Teams webhook, etc.
    }

    # Log alerts
    $alertLog = "C:\Monitoring\NetworkSecurity\Logs\Alerts_$(Get-Date -Format 'yyyyMMdd').log"
    $alerts | Out-File -FilePath $alertLog -Append -Encoding UTF8
} else {
    Write-Host "No security alerts detected" -ForegroundColor Green
}
'@

$alertScript | Out-File -FilePath "$monitoringDir\CheckAlerts.ps1" -Encoding UTF8 -Force
Write-Host "Alert system script created: $monitoringDir\CheckAlerts.ps1" -ForegroundColor Green

# Step 10: Final Summary and Recommendations
Write-Host "`nNetwork Security Monitoring Setup Complete!" -ForegroundColor Green
Write-Host "Components Configured:" -ForegroundColor Cyan
Write-Host "- Firewall monitoring and verification" -ForegroundColor Cyan
Write-Host "- Docker network configuration checks" -ForegroundColor Cyan
Write-Host "- Container status and port connectivity tests" -ForegroundColor Cyan
Write-Host "- Windows Defender security status monitoring" -ForegroundColor Cyan
Write-Host "- Automated security reporting" -ForegroundColor Cyan
Write-Host "- Continuous monitoring with scheduled tasks" -ForegroundColor Cyan
Write-Host "- Basic alert system framework" -ForegroundColor Cyan

Write-Host "`nMonitoring Files Created:" -ForegroundColor Yellow
Write-Host "- $monitoringDir\ContinuousMonitoring.ps1" -ForegroundColor Yellow
Write-Host "- $monitoringDir\CheckAlerts.ps1" -ForegroundColor Yellow
Write-Host "- $reportDir\NetworkSecurity_Report_*.txt" -ForegroundColor Yellow
Write-Host "- $logDir\ContinuousMonitoring_*.log" -ForegroundColor Yellow

Write-Host "`nNext Steps and Recommendations:" -ForegroundColor Yellow
Write-Host "- Review the generated security report: $reportFile" -ForegroundColor Yellow
Write-Host "- Configure email/Slack/Teams notifications in the alert script" -ForegroundColor Yellow
Write-Host "- Set up log aggregation and analysis tools" -ForegroundColor Yellow
Write-Host "- Configure VPN access for administrative tasks" -ForegroundColor Yellow
Write-Host "- Implement DMZ placement for additional network segmentation" -ForegroundColor Yellow
Write-Host "- Schedule regular security audits and penetration testing" -ForegroundColor Yellow

Write-Host "`nTo start continuous monitoring:" -ForegroundColor Cyan
Write-Host "powershell.exe -ExecutionPolicy Bypass -File $monitoringDir\ContinuousMonitoring.ps1" -ForegroundColor Cyan

Write-Host "`nTo check for alerts:" -ForegroundColor Cyan
Write-Host "powershell.exe -ExecutionPolicy Bypass -File $monitoringDir\CheckAlerts.ps1" -ForegroundColor Cyan