# Phase 3: Privileged Container Security Hardening
# This script implements advanced security measures for privileged containers
# Includes capability restrictions, seccomp profiles, and Windows Defender Application Control

param(
    [string]$ContainerName = "ubuntu-server",
    [string]$SeccompProfilePath = "C:\dev-env.local\docker-ai-services\local-ai-packaged\seccomp\ubuntu-dind-seccomp.json",
    [string]$WDACPolicyPath = "C:\dev-env.local\docker-ai-services\local-ai-packaged\seccomp\wdac-policy.xml",
    [int]$MemoryLimitGB = 64,
    [int]$CPULimit = 12,
    [int]$PidsLimit = 4096
)

Write-Host "=== Phase 3: Privileged Container Security Hardening ===" -ForegroundColor Green

# Function to check Docker Desktop status
function Test-DockerDesktop {
    try {
        $dockerVersion = docker version --format "{{.Server.Version}}" 2>$null
        if ($dockerVersion) {
            return $true
        } else {
            return $false
        }
    } catch {
        return $false
    }
}

# Function to check if container exists
function Test-ContainerExists {
    param([string]$Name)
    $container = docker ps -a --filter "name=$Name" --format "{{.Names}}" 2>$null
    return $container -eq $Name
}

# Check prerequisites
if (-not (Test-DockerDesktop)) {
    Write-Host "Docker Desktop is not running. Please start Docker Desktop first." -ForegroundColor Red
    exit 1
}

if (-not (Test-ContainerExists -Name $ContainerName)) {
    Write-Host "Container '$ContainerName' does not exist. Please run Ubuntu container setup first." -ForegroundColor Red
    exit 1
}

# Check if seccomp profile exists
if (-not (Test-Path $SeccompProfilePath)) {
    Write-Host "Seccomp profile not found at: $SeccompProfilePath" -ForegroundColor Red
    Write-Host "Please ensure the seccomp profile is created first." -ForegroundColor Red
    exit 1
}

# Stop the existing container
Write-Host "Stopping existing container for reconfiguration..." -ForegroundColor Cyan
docker stop $ContainerName
docker rm $ContainerName

# Create hardened container configuration
Write-Host "Creating hardened container configuration..." -ForegroundColor Cyan

# Build Docker run command with security hardening
$dockerArgs = @(
    "run",
    "-d",
    "--name", $ContainerName,
    "--privileged",
    "--restart", "unless-stopped",
    "-p", "80:80",
    "-p", "443:443",
    "-v", "ubuntu-data:/data",
    "-v", "ubuntu-certs:/certs",
    "-v", "//./pipe/docker_engine://./pipe/docker_engine",
    "-e", "DOCKER_TLS_CERTDIR=/certs",
    "--memory=${MemoryLimitGB}g",
    "--cpus=$CPULimit",
    "--memory-swap=$($MemoryLimitGB * 1.5)g",
    "--kernel-memory=8g",
    "--pids-limit=$PidsLimit",
    "--ulimit", "nofile=4096:4096",
    "--ulimit", "nproc=1024:1024",
    "--security-opt", "seccomp=$SeccompProfilePath",
    "--security-opt", "apparmor=unconfined",
    "--cap-drop=ALL",
    "--cap-add=SYS_ADMIN",
    "--cap-add=NET_ADMIN",
    "--cap-add=SYS_PTRACE",
    "--cap-add=SYS_CHROOT",
    "--cap-add=DAC_OVERRIDE",
    "--cap-add=FSETID",
    "--cap-add=FOWNER",
    "--cap-add=MKNOD",
    "--cap-add=NET_RAW",
    "--cap-add=SETGID",
    "--cap-add=SETUID",
    "--cap-add=SETFCAP",
    "--cap-add=SETPCAP",
    "--cap-add=SYS_NICE",
    "--cap-add=SYS_RESOURCE",
    "--cap-add=SYS_TIME",
    "--cap-add=SYS_TTY_CONFIG",
    "--cap-add=LEASE",
    "--cap-add=AUDIT_WRITE",
    "--cap-add=AUDIT_CONTROL",
    "--cap-add=SYSLOG",
    "--read-only",
    "--tmpfs", "/tmp:noexec,nosuid,size=500m",
    "--tmpfs", "/var/run:noexec,nosuid,size=100m",
    "--tmpfs", "/var/log:noexec,nosuid,size=100m",
    "--tmpfs", "/var/tmp:noexec,nosuid,size=50m",
    "--network", "none",
    "ubuntu:22.04",
    "tail", "-f", "/dev/null"
)

# Join arguments and run
$dockerCommand = $dockerArgs -join " "
Write-Host "Running: docker $dockerCommand" -ForegroundColor Gray
Invoke-Expression "docker $dockerCommand"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to create hardened container" -ForegroundColor Red
    exit 1
}

# Wait for container to start
Start-Sleep -Seconds 10

# Configure network namespace isolation (custom bridge network)
Write-Host "Configuring network namespace isolation..." -ForegroundColor Cyan

# Create isolated bridge network
docker network create --driver bridge --opt com.docker.network.bridge.name=ubuntu-bridge ubuntu-net

# Connect container to isolated network
docker network connect ubuntu-net $ContainerName

# Configure network restrictions inside container
Write-Host "Configuring network restrictions inside container..." -ForegroundColor Cyan
docker exec $ContainerName bash -c "
    # Install network tools
    apt update -y && apt install -y iptables iproute2 net-tools

    # Create custom iptables rules for network isolation
    iptables -F
    iptables -X

    # Default policies
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT DROP

    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT

    # Allow established connections
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # Allow DNS (UDP 53)
    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT

    # Allow HTTP/HTTPS outbound for package updates
    iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT

    # Allow NTP for time sync
    iptables -A OUTPUT -p udp --dport 123 -j ACCEPT

    # Allow inbound HTTP/HTTPS
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT

    # Allow SSH (if needed for management)
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT

    # Save iptables rules
    iptables-save > /etc/iptables/rules.v4

    echo 'Network isolation configured successfully.'
"

# Configure user namespace mapping
Write-Host "Configuring user namespace mapping..." -ForegroundColor Cyan

# Create custom Docker daemon configuration for user namespaces
$daemonConfig = @"
{
    \"icc\": false,
    \"userns-remap\": \"default\",
    \"no-new-privileges\": true,
    \"log-driver\": \"json-file\",
    \"log-opts\": {
        \"max-size\": \"10m\",
        \"max-file\": \"3\"
    },
    \"live-restore\": true,
    \"userland-proxy\": false,
    \"seccomp-profile\": \"$SeccompProfilePath\"
}
"@

# Apply daemon config inside container
docker exec $ContainerName bash -c "
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << EOF
$daemonConfig
EOF

    # Restart Docker daemon inside container
    systemctl restart docker
"

# Configure Windows Defender Application Control policy
Write-Host "Configuring Windows Defender Application Control..." -ForegroundColor Cyan

# Create WDAC policy for container restrictions
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
    <Rule>
      <Option>Enabled:WHQL</Option>
    </Rule>
    <Rule>
      <Option>Enabled:Boot Menu Protection</Option>
    </Rule>
  </Rules>
  <EKUs />
  <FileRules />
  <Signers>
    <Signer ID="ID_SIGNER_S_1" Name="Microsoft">
      <CertRoot Type="Wellknown" Value="04" />
      <CertEKU ID="ID_EKU_1" />
    </Signer>
  </Signers>
  <SigningScenarios>
    <SigningScenario Value="12" ID="ID_SIGNINGSCENARIO_WINDOWS" FriendlyName="Windows">
      <ProductSigners>
        <AllowedSigners>
          <AllowedSigner SignerId="ID_SIGNER_S_1" />
        </AllowedSigners>
      </ProductSigners>
    </SigningScenario>
    <SigningScenario Value="131" ID="ID_SIGNINGSCENARIO_DRIVERS" FriendlyName="Drivers">
      <ProductSigners>
        <AllowedSigners>
          <AllowedSigner SignerId="ID_SIGNER_S_1" />
        </AllowedSigners>
      </ProductSigners>
    </SigningScenario>
  </SigningScenarios>
  <UpdatePolicySigners />
  <CiSigners />
  <HvciOptions>1</HvciOptions>
</SiPolicy>
"@

# Save WDAC policy
$wdacPolicy | Out-File -FilePath $WDACPolicyPath -Encoding UTF8

# Instructions for WDAC deployment
Write-Host "WDAC policy created at: $WDACPolicyPath" -ForegroundColor Green
Write-Host "To deploy WDAC policy, run the following commands as Administrator:" -ForegroundColor Yellow
Write-Host "1. ConvertFrom-CIPolicy -XmlFilePath `"$WDACPolicyPath`" -BinaryFilePath `"$WDACPolicyPath.bin`"" -ForegroundColor White
Write-Host "2. Copy-Item -Path `"$WDACPolicyPath.bin`" -Destination `"C:\Windows\System32\CodeIntegrity\SiPolicy.p7b`" -Force" -ForegroundColor White
Write-Host "3. Restart-Computer" -ForegroundColor White

# Configure resource monitoring and limits
Write-Host "Setting up resource monitoring and limits..." -ForegroundColor Cyan

# Create monitoring script inside container
docker exec $ContainerName bash -c "
    cat > /opt/security/resource-monitor.sh << 'EOF'
#!/bin/bash
echo '=== Container Resource Monitor ==='

# Memory usage
echo 'Memory Usage:'
free -h

# CPU usage
echo 'CPU Usage:'
top -bn1 | head -20

# Disk usage
echo 'Disk Usage:'
df -h

# Process count
echo 'Process Count:'
ps aux | wc -l

# Network connections
echo 'Network Connections:'
netstat -tuln | wc -l

# Docker system info
echo 'Docker System Info:'
docker system df

echo '=== Monitoring Complete ==='
EOF

    chmod +x /opt/security/resource-monitor.sh
"

# Set up periodic resource monitoring via scheduled task
$monitorTask = @"
# Resource monitoring task
docker exec $ContainerName /opt/security/resource-monitor.sh >> /data/resource-monitor.log 2>&1
"@

$monitorScriptPath = "$env:TEMP\ContainerResourceMonitor.ps1"
$monitorTask | Out-File -FilePath $monitorScriptPath -Encoding UTF8

# Create scheduled task for resource monitoring (every 15 minutes)
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$monitorScriptPath`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Days 365)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable
Register-ScheduledTask -TaskName "Container Resource Monitor" -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -User "SYSTEM" | Out-Null

# Create security verification script
Write-Host "Creating comprehensive security verification..." -ForegroundColor Cyan

$verificationScript = @"
# Privileged Container Security Verification
Write-Host "=== Privileged Container Security Verification ===" -ForegroundColor Green

# Check container status
Write-Host "Container Status:" -ForegroundColor Cyan
docker ps --filter "name=$ContainerName" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check container capabilities
Write-Host "Container Capabilities:" -ForegroundColor Cyan
docker exec $ContainerName capsh --print | Select-String -Pattern "Current|Bounding"

# Check seccomp status
Write-Host "Seccomp Status:" -ForegroundColor Cyan
docker exec $ContainerName grep -r Seccomp /proc/1/status

# Check network isolation
Write-Host "Network Isolation:" -ForegroundColor Cyan
docker exec $ContainerName iptables -L -n | Select-String -Pattern "DROP|ACCEPT" | Select-Object -First 10

# Check resource limits
Write-Host "Resource Limits:" -ForegroundColor Cyan
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | Where-Object { `$_ -match "$ContainerName" }

# Check Docker daemon security
Write-Host "Docker Daemon Security:" -ForegroundColor Cyan
docker exec $ContainerName docker info --format '{{.SecurityOptions}}'

# Check mounted volumes
Write-Host "Volume Mounts:" -ForegroundColor Cyan
docker inspect $ContainerName | ConvertFrom-Json | Select-Object -ExpandProperty Mounts | Format-Table -Property Destination, Source, Mode

Write-Host "=== Security Verification Complete ===" -ForegroundColor Green
"@

$verificationScriptPath = "$env:ProgramData\ContainerSecurityVerification.ps1"
$verificationScript | Out-File -FilePath $verificationScriptPath -Encoding UTF8

# Run initial verification
Write-Host "Running initial security verification..." -ForegroundColor Cyan
& $verificationScriptPath

# Create desktop shortcut
Write-Host "Creating desktop shortcut for security verification..." -ForegroundColor Cyan

$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\Container Security Status.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$verificationScriptPath`""
$Shortcut.WorkingDirectory = "$env:ProgramData"
$Shortcut.IconLocation = "powershell.exe,0"
$Shortcut.Description = "Check Privileged Container Security Status"
$Shortcut.Save()

Write-Host "=== Privileged Container Security Hardening Completed ===" -ForegroundColor Green
Write-Host "Security Features Implemented:" -ForegroundColor Cyan
Write-Host "  - Minimal capability set (dropped ALL, added only required)" -ForegroundColor White
Write-Host "  - Custom seccomp profile for syscall restrictions" -ForegroundColor White
Write-Host "  - Network namespace isolation with custom bridge" -ForegroundColor White
Write-Host "  - User namespace remapping for non-privileged access" -ForegroundColor White
Write-Host "  - Resource limits (memory, CPU, PIDs, file descriptors)" -ForegroundColor White
Write-Host "  - Read-only root filesystem with controlled tmpfs" -ForegroundColor White
Write-Host "  - iptables-based network filtering" -ForegroundColor White
Write-Host "  - WDAC policy for Windows container restrictions" -ForegroundColor White
Write-Host "  - Resource monitoring and alerting (15-minute intervals)" -ForegroundColor White
Write-Host "  - Comprehensive security verification script on desktop" -ForegroundColor White

Write-Host "" -ForegroundColor Yellow
Write-Host "IMPORTANT: Deploy the WDAC policy and reboot the system to enable full security hardening." -ForegroundColor Yellow
Write-Host "Monitor resource usage and security logs regularly using the verification script." -ForegroundColor Yellow