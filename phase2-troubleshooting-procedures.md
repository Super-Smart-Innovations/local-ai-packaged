# Phase 2: Network Security Troubleshooting Procedures

## Executive Summary

This document provides comprehensive troubleshooting procedures for the network security configuration implemented in Phase 2 of the containerized Windows deployment. It includes diagnostic commands, common issues, and step-by-step resolution procedures.

## 1. Windows Firewall Issues

### 1.1 Firewall Rules Not Applied

**Symptoms:**
- Services not accessible from external IPs
- Connection timeouts on specific ports

**Diagnostic Commands:**
```powershell
# Check firewall profile status
Get-NetFirewallProfile | Format-Table Name,Enabled,DefaultInboundAction,DefaultOutboundAction

# List all firewall rules
Get-NetFirewallRule | Where-Object { $_.Enabled -eq $true } | Format-Table DisplayName,Direction,Action,LocalPort

# Check specific rule status
Get-NetFirewallRule -DisplayName "HTTP (Port 80)"
Get-NetFirewallRule -DisplayName "HTTPS (Port 443)"
```

**Resolution Steps:**
1. Re-run the firewall configuration script:
   ```powershell
   .\phase2-windows-firewall-setup.ps1
   ```

2. Manually enable firewall rules:
   ```powershell
   Set-NetFirewallRule -DisplayName "HTTP (Port 80)" -Enabled True
   Set-NetFirewallRule -DisplayName "HTTPS (Port 443)" -Enabled True
   ```

3. Restart Windows Firewall service:
   ```powershell
   Restart-Service -Name mpssvc
   ```

### 1.2 Flood Protection Blocking Legitimate Traffic

**Symptoms:**
- Intermittent connection drops
- High latency for legitimate connections

**Diagnostic Commands:**
```powershell
# Check flood protection settings
netsh advfirewall show allprofiles state

# View firewall logs for blocked connections
Get-Content "$env:SystemRoot\System32\LogFiles\Firewall\pfirewall.log" -Tail 50 |
    Where-Object { $_ -match "DROP" -or $_ -match "BLOCK" }
```

**Resolution Steps:**
1. Adjust flood protection settings:
   ```powershell
   # Temporarily disable SYN flood protection for testing
   Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "SynAttackProtect" -Value 0

   # Or adjust connection limits
   Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "TcpMaxConnectResponseRetransmissions" -Value 3
   ```

2. Add rate limiting exceptions for specific IPs:
   ```powershell
   New-NetFirewallRule -DisplayName "Rate Limit Exception - Admin IP" `
       -Direction Inbound `
       -Protocol TCP `
       -LocalPort 80,443 `
       -RemoteAddress "YOUR_ADMIN_IP" `
       -Action Allow `
       -ThrottleLimit 100
   ```

### 1.3 Firewall Logging Not Working

**Symptoms:**
- No entries in firewall log files
- Security monitoring not capturing events

**Diagnostic Commands:**
```powershell
# Check logging configuration
Get-NetFirewallProfile | Select-Object Name,LogAllowed,LogBlocked,LogFileName

# Check if log file exists and has content
$logPath = "$env:SystemRoot\System32\LogFiles\Firewall\pfirewall.log"
Test-Path $logPath
Get-Item $logPath | Select-Object Length,LastWriteTime
```

**Resolution Steps:**
1. Reconfigure firewall logging:
   ```powershell
   Set-NetFirewallProfile -Profile Domain,Public,Private -LogAllowed True -LogBlocked True -LogIgnored True
   Set-NetFirewallProfile -Profile Domain,Public,Private -LogFileName $logPath
   Set-NetFirewallProfile -Profile Domain,Public,Private -LogMaxSizeKilobytes 32767
   ```

2. Restart Windows Firewall service:
   ```powershell
   Restart-Service -Name mpssvc -Force
   ```

## 2. Docker Network Issues

### 2.1 Container Cannot Reach External Networks

**Symptoms:**
- Container cannot ping external hosts
- DNS resolution failures inside container

**Diagnostic Commands:**
```powershell
# Check Docker network configuration
docker network ls
docker network inspect localai-bridge
docker network inspect localai-internal

# Check container network settings
docker inspect ubuntu-server | Select-Object -ExpandProperty NetworkSettings -ExpandProperty Networks

# Test connectivity from container
docker exec ubuntu-server ping -c 3 8.8.8.8
docker exec ubuntu-server nslookup google.com
```

**Resolution Steps:**
1. Restart Docker networks:
   ```powershell
   docker network rm localai-bridge
   docker network rm localai-internal
   .\phase2-docker-network-isolation.ps1
   ```

2. Reconnect container to networks:
   ```powershell
   docker network connect localai-bridge ubuntu-server
   docker network connect localai-internal ubuntu-server
   ```

3. Restart Docker service:
   ```powershell
   Restart-Service -Name "Docker Desktop Service"
   ```

### 2.2 Port Forwarding Not Working

**Symptoms:**
- Services not accessible through host ports
- Connection refused errors

**Diagnostic Commands:**
```powershell
# Test port connectivity on host
Test-NetConnection -ComputerName localhost -Port 80
Test-NetConnection -ComputerName localhost -Port 443

# Check container port mappings
docker port ubuntu-server

# Check iptables rules in container
docker exec ubuntu-server iptables -L -n

# Verify service is listening inside container
docker exec ubuntu-server netstat -tlnp | grep :80
```

**Resolution Steps:**
1. Re-run port forwarding script:
   ```powershell
   .\phase2-port-forwarding-setup.ps1
   ```

2. Manually recreate port mappings:
   ```powershell
   docker stop ubuntu-server
   docker rm ubuntu-server

   docker run -d --name ubuntu-server `
     --privileged `
     --network localai-bridge `
     -p 80:80 -p 443:443 -p 22:22 `
     ubuntu:22.04
   ```

3. Check Windows Firewall rules for blocked ports:
   ```powershell
   Get-NetFirewallRule | Where-Object { $_.LocalPort -eq "80" -or $_.LocalPort -eq "443" }
   ```

### 2.3 Inter-Container Communication Issues

**Symptoms:**
- Services cannot communicate with each other
- Database connection failures

**Diagnostic Commands:**
```powershell
# Check container connectivity on internal network
docker exec ubuntu-server ping -c 3 172.21.0.10  # N8N
docker exec ubuntu-server ping -c 3 172.21.0.11  # Open WebUI

# Check network connectivity between containers
docker exec n8n ping -c 3 qdrant
docker exec open-webui ping -c 3 supabase

# Verify DNS resolution
docker exec ubuntu-server nslookup n8n.localai
```

**Resolution Steps:**
1. Reconnect services to internal network:
   ```bash
   # Inside Ubuntu container
   docker exec ubuntu-server bash /opt/connect-services.sh
   ```

2. Restart affected services:
   ```bash
   # Inside Ubuntu container
   docker compose -p localai restart
   ```

3. Check network isolation settings:
   ```powershell
   docker network inspect localai-internal | ConvertFrom-Json | Select-Object -ExpandProperty Options
   ```

## 3. Windows Defender Issues

### 3.1 False Positive Blocking Legitimate Applications

**Symptoms:**
- Docker commands blocked
- Development tools not working

**Diagnostic Commands:**
```powershell
# Check Windows Defender exclusions
Get-MpPreference | Select-Object -ExpandProperty ExclusionPath
Get-MpPreference | Select-Object -ExpandProperty ExclusionExtension

# Check controlled folder access allowed applications
Get-MpPreference | Select-Object -ExpandProperty ControlledFolderAccessAllowedApplications

# Review Windows Defender logs
Get-MpThreat | Select-Object -Last 10
```

**Resolution Steps:**
1. Add additional exclusions:
   ```powershell
   Add-MpPreference -ExclusionPath "C:\dev-env.local"
   Add-MpPreference -ExclusionExtension ".ps1"
   ```

2. Allow specific applications:
   ```powershell
   Add-MpPreference -ControlledFolderAccessAllowedApplications "C:\Program Files\Docker\Docker\DockerCli.exe"
   ```

3. Temporarily disable real-time protection for testing:
   ```powershell
   Set-MpPreference -DisableRealtimeMonitoring $true
   # Re-enable after testing
   Set-MpPreference -DisableRealtimeMonitoring $false
   ```

### 3.2 Windows Defender Service Not Starting

**Symptoms:**
- Security Center shows Defender disabled
- Real-time protection not active

**Diagnostic Commands:**
```powershell
# Check Windows Defender service status
Get-Service -Name WinDefend,SecurityCenter

# Check Windows Defender status
Get-MpComputerStatus | Select-Object AntivirusEnabled,AMServiceEnabled

# Check for Windows Defender errors
Get-EventLog -LogName System -Source Microsoft-Windows-Windows Defender -Newest 10
```

**Resolution Steps:**
1. Restart Windows Defender services:
   ```powershell
   Restart-Service -Name WinDefend -Force
   Restart-Service -Name SecurityCenter -Force
   ```

2. Re-enable Windows Defender features:
   ```powershell
   .\phase2-windows-defender-setup.ps1
   ```

3. Run Windows Defender offline scan:
   ```powershell
   Start-MpScan -ScanType FullScan
   ```

### 3.3 Attack Surface Reduction Blocking Features

**Symptoms:**
- Office applications not working properly
- Development workflows failing

**Diagnostic Commands:**
```powershell
# Check ASR rule status
Get-MpPreference | Select-Object -ExpandProperty AttackSurfaceReductionRules_Actions

# Check ASR events
Get-EventLog -LogName Microsoft-Windows-Windows Defender/Operational -Newest 20 |
    Where-Object { $_.Id -eq 1121 -or $_.Id -eq 1122 }
```

**Resolution Steps:**
1. Adjust ASR rules:
   ```powershell
   # Disable problematic rules (example)
   Set-MpPreference -AttackSurfaceReductionRules_Ids "d4f940ab-401b-4efc-aadc-ad5f3c50688a" -AttackSurfaceReductionRules_Actions Disabled
   ```

2. Add exclusions for trusted applications:
   ```powershell
   Add-MpPreference -AttackSurfaceReductionOnlyExclusions "C:\Program Files\Microsoft Office"
   ```

## 4. Monitoring and Alert Issues

### 4.1 Monitoring Scripts Not Running

**Symptoms:**
- No monitoring logs generated
- Scheduled tasks failing

**Diagnostic Commands:**
```powershell
# Check scheduled task status
Get-ScheduledTask -TaskName "NetworkSecurityMonitoring" | Select-Object State,LastRunTime,LastTaskResult

# Check monitoring script permissions
Test-Path "C:\Monitoring\NetworkSecurity\ContinuousMonitoring.ps1"
Get-Acl "C:\Monitoring\NetworkSecurity\ContinuousMonitoring.ps1" | Select-Object Owner,Access

# Check PowerShell execution policy
Get-ExecutionPolicy -List
```

**Resolution Steps:**
1. Recreate scheduled task:
   ```powershell
   Unregister-ScheduledTask -TaskName "NetworkSecurityMonitoring" -Confirm:$false
   .\phase2-network-monitoring-verification.ps1
   ```

2. Adjust execution policy:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
   ```

3. Test monitoring script manually:
   ```powershell
   & "C:\Monitoring\NetworkSecurity\ContinuousMonitoring.ps1" -IntervalSeconds 60
   ```

### 4.2 Alert System Not Working

**Symptoms:**
- No alerts generated for security issues
- Alert logs empty

**Diagnostic Commands:**
```powershell
# Check alert script syntax
Get-Command -Syntax "C:\Monitoring\NetworkSecurity\CheckAlerts.ps1"

# Test alert script manually
& "C:\Monitoring\NetworkSecurity\CheckAlerts.ps1"

# Check alert log files
Get-ChildItem "C:\Monitoring\NetworkSecurity\Logs" | Where-Object { $_.Name -like "Alerts_*" }
```

**Resolution Steps:**
1. Update alert script with correct paths and logic
2. Configure notification integration (email, Slack, Teams)
3. Test alert conditions manually

## 5. Container Security Issues

### 5.1 Privileged Container Access Problems

**Symptoms:**
- Docker-in-Docker not working
- Volume mounting failures

**Diagnostic Commands:**
```powershell
# Check container privileges
docker inspect ubuntu-server | Select-Object -ExpandProperty HostConfig -ExpandProperty Privileged

# Check Docker daemon access
docker exec ubuntu-server docker info

# Check volume mounts
docker inspect ubuntu-server | Select-Object -ExpandProperty Mounts
```

**Resolution Steps:**
1. Recreate container with correct privileges:
   ```powershell
   .\phase2-docker-network-isolation.ps1
   ```

2. Verify Docker socket mounting:
   ```powershell
   docker run --rm -v //./pipe/docker_engine://./pipe/docker_engine ubuntu:22.04 docker info
   ```

### 5.2 iptables Rules Not Persisting

**Symptoms:**
- Network rules lost after container restart
- Intermittent connectivity issues

**Diagnostic Commands:**
```powershell
# Check current iptables rules in container
docker exec ubuntu-server iptables -L -n

# Check iptables persistence configuration
docker exec ubuntu-server systemctl status iptables-restore

# Check rules file
docker exec ubuntu-server cat /etc/iptables/rules.v4
```

**Resolution Steps:**
1. Reapply iptables rules:
   ```bash
   docker exec ubuntu-server bash /opt/network-setup.sh
   ```

2. Ensure systemd service is enabled:
   ```bash
   docker exec ubuntu-server systemctl enable iptables-restore
   ```

## 6. Performance Issues

### 6.1 High Network Latency

**Symptoms:**
- Slow response times
- Connection timeouts

**Diagnostic Commands:**
```powershell
# Test network latency
Test-NetConnection -ComputerName localhost -Port 80 -InformationLevel Detailed

# Check Windows Firewall performance
Get-NetFirewallProfile | Select-Object Name,LogMaxSizeKilobytes,LogAllowed,LogBlocked

# Monitor network traffic
Get-NetAdapterStatistics | Select-Object Name,ReceivedBytes,SentBytes
```

**Resolution Steps:**
1. Disable unnecessary logging:
   ```powershell
   Set-NetFirewallProfile -Profile Domain,Public,Private -LogAllowed False -LogBlocked False
   ```

2. Optimize firewall rules:
   ```powershell
   # Remove redundant rules
   Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*Duplicate*" } | Remove-NetFirewallRule
   ```

### 6.2 Memory Usage High

**Symptoms:**
- System slowdowns
- Container restarts

**Diagnostic Commands:**
```powershell
# Check container memory usage
docker stats --no-stream

# Check Windows Defender memory usage
Get-Process -Name MsMpEng | Select-Object PM,VirtualMemorySize

# Check firewall memory usage
Get-Process -Name MpsSvc | Select-Object PM,VirtualMemorySize
```

**Resolution Steps:**
1. Adjust container resource limits:
   ```powershell
   docker update --memory=32g --cpus=8 ubuntu-server
   ```

2. Optimize Windows Defender exclusions:
   ```powershell
   # Add more specific exclusions
   Add-MpPreference -ExclusionPath "C:\ProgramData\Docker"
   ```

## 7. Emergency Procedures

### 7.1 Complete Security Reset

**Critical Situation:** Complete security compromise suspected

**Immediate Actions:**
1. Disconnect from network
2. Stop all containers:
   ```powershell
   docker compose -p localai down
   docker stop ubuntu-server
   ```

3. Disable Windows Firewall temporarily:
   ```powershell
   Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
   ```

4. Perform full security scan:
   ```powershell
   Start-MpScan -ScanType FullScan
   ```

5. Rebuild from known good state

### 7.2 Service Unavailability Recovery

**Critical Situation:** All services down

**Immediate Actions:**
1. Check host system health:
   ```powershell
   Get-Service | Where-Object { $_.Status -ne "Running" }
   ```

2. Restart Docker service:
   ```powershell
   Restart-Service -Name "Docker Desktop Service"
   ```

3. Restart containers:
   ```powershell
   .\phase2-port-forwarding-setup.ps1
   ```

4. Verify monitoring is active

## 8. Common Error Codes and Solutions

### Windows Firewall Errors
- **0x80070422**: Firewall service not running
  - Solution: `Start-Service mpssvc`

- **0x800706D9**: Firewall rules corrupted
  - Solution: Reset firewall rules and reapply configuration

### Docker Network Errors
- **network not found**: Network was removed
  - Solution: Recreate networks using network isolation script

- **port already in use**: Conflicting port mappings
  - Solution: Check existing containers and remove conflicts

### Windows Defender Errors
- **0x80070643**: Defender update failed
  - Solution: Manual update or restart service

- **0x80508023**: ASR rule conflict
  - Solution: Adjust conflicting ASR rules

## 9. Prevention and Best Practices

### Regular Maintenance
- Weekly: Review firewall logs and blocked connections
- Monthly: Update Windows Defender signatures
- Quarterly: Full security audit and rule review

### Monitoring Thresholds
- Alert on >100 blocked connections per hour
- Alert on container restart >5 times per day
- Alert on Windows Defender service failures

### Backup Procedures
- Daily: Export firewall rules and container configurations
- Weekly: Full container backup (Phase 6)
- Monthly: Complete system backup

## 10. Contact and Escalation

### Support Contacts
- **Network Security Issues**: Security Team
- **Container Issues**: DevOps Team
- **Windows Host Issues**: System Administration
- **Emergency**: On-call Engineer (24/7)

### Escalation Procedures
1. Document the issue with diagnostic outputs
2. Attempt resolution using this guide
3. Escalate to appropriate team if unresolved within 1 hour
4. Emergency escalation for production outages

---

**Document Version**: 1.0
**Last Updated**: November 2025
**Review Schedule**: Monthly
**Next Review**: December 2025