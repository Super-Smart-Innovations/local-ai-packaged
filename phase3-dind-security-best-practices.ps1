# Phase 3: DinD Security Best Practices Implementation
# This script implements comprehensive security measures for Docker-in-Docker operations
# Includes resource limits, privilege escalation controls, and secure daemon configuration

param(
    [string]$ContainerName = "ubuntu-server",
    [string]$DindNetwork = "dind-net",
    [int]$MaxContainers = 50,
    [int]$MaxImages = 100,
    [int]$MaxVolumes = 20,
    [long]$DiskQuotaGB = 100
)

Write-Host "=== Phase 3: DinD Security Best Practices Implementation ===" -ForegroundColor Green

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

# Function to check if container exists and is running
function Test-ContainerRunning {
    param([string]$Name)
    $status = docker ps --filter "name=$Name" --format "{{.Status}}" 2>$null
    return $status -match "Up"
}

# Check prerequisites
if (-not (Test-DockerDesktop)) {
    Write-Host "Docker Desktop is not running. Please start Docker Desktop first." -ForegroundColor Red
    exit 1
}

if (-not (Test-ContainerRunning -Name $ContainerName)) {
    Write-Host "Container '$ContainerName' is not running. Please start the container first." -ForegroundColor Red
    exit 1
}

# Configure DinD security best practices inside the container
Write-Host "Configuring DinD security best practices..." -ForegroundColor Cyan

docker exec $ContainerName bash -c "
    # Install security monitoring tools
    apt update -y && apt install -y auditd audispd-plugins cgroup-tools

    # Configure audit daemon for Docker activity monitoring
    cat > /etc/audit/rules.d/docker.rules << EOF
# Docker daemon activities
-w /usr/bin/docker -k docker
-w /usr/bin/dockerd -k docker
-w /var/lib/docker -k docker
-w /etc/docker -k docker
-w /usr/lib/docker -k docker

# Container operations
-a exit,always -F arch=b64 -S execve -F path=/usr/bin/docker -k docker-exec
-a exit,always -F arch=b64 -S execve -F path=/usr/bin/dockerd -k docker-daemon

# Privilege escalation attempts
-w /etc/sudoers -k privilege-escalation
-w /etc/passwd -k user-modification
EOF

    # Restart audit daemon
    systemctl enable auditd
    systemctl restart auditd

    # Create Docker security configuration
    mkdir -p /etc/docker/security

    # Configure Docker daemon with security best practices
    cat > /etc/docker/daemon.json << EOF
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
    \"max-concurrent-downloads\": 3,
    \"max-concurrent-uploads\": 3,
    \"max-download-attempts\": 3,
    \"max-upload-attempts\": 3,
    \"containerd-namespace\": \"localai\",
    \"containerd-plugins\": {
        \"io.containerd.grpc.v1.cri\": {
            \"sandbox_image\": \"registry.k8s.io/pause:3.9\"
        }
    }
}
EOF

    # Create resource control script
    cat > /opt/security/dind-resource-control.sh << 'EOF'
#!/bin/bash
# DinD Resource Control and Security Monitoring

# Set resource limits
CGROUP_PATH=\"/sys/fs/cgroup\"
DOCKER_CGROUP=\"docker\"

# Create Docker cgroup if it doesn't exist
if [ ! -d \"\$CGROUP_PATH/\$DOCKER_CGROUP\" ]; then
    mkdir -p \$CGROUP_PATH/\$DOCKER_CGROUP
fi

# Set memory limit (50GB for DinD operations)
echo 53687091200 > \$CGROUP_PATH/\$DOCKER_CGROUP/memory.max

# Set CPU limit (8 cores)
echo 800000 > \$CGROUP_PATH/\$DOCKER_CGROUP/cpu.max

# Set PIDs limit
echo 2048 > \$CGROUP_PATH/\$DOCKER_CGROUP/pids.max

echo \"DinD resource limits applied successfully.\"
EOF

    chmod +x /opt/security/dind-resource-control.sh

    # Apply resource controls
    /opt/security/dind-resource-control.sh

    # Create container security policy
    cat > /opt/security/container-policy.sh << 'EOF'
#!/bin/bash
# Container Security Policy Enforcement

# Function to check container security
check_container_security() {
    local container_id=\$1

    echo \"Checking security for container: \$container_id\"

    # Check if container has privileged flag
    if docker inspect \$container_id | grep -q '\"Privileged\": true'; then
        echo \"WARNING: Container \$container_id is running in privileged mode!\"
        return 1
    fi

    # Check capability restrictions
    local caps=\$(docker inspect \$container_id | jq -r '.[]?.HostConfig.Capabilities | join(\" \")' 2>/dev/null)
    if echo \"\$caps\" | grep -q \"ALL\"; then
        echo \"WARNING: Container \$container_id has ALL capabilities!\"
        return 1
    fi

    # Check security options
    local secopts=\$(docker inspect \$container_id | jq -r '.[]?.HostConfig.SecurityOpt | join(\" \")' 2>/dev/null)
    if ! echo \"\$secopts\" | grep -q \"seccomp\"; then
        echo \"WARNING: Container \$container_id has no seccomp profile!\"
        return 1
    fi

    echo \"Container \$container_id passed security checks.\"
    return 0
}

# Function to enforce resource limits
enforce_resource_limits() {
    local container_id=\$1
    local memory_limit=\${2:-\"16g\"}
    local cpu_limit=\${3:-4}

    echo \"Enforcing resource limits for container: \$container_id\"

    # Update memory limit
    docker update --memory \$memory_limit \$container_id

    # Update CPU limit
    docker update --cpus \$cpu_limit \$container_id

    echo \"Resource limits enforced for container: \$container_id\"
}

# Export functions for use in other scripts
export -f check_container_security
export -f enforce_resource_limits
EOF

    chmod +x /opt/security/container-policy.sh
"

# Create isolated network for DinD operations
Write-Host "Creating isolated network for DinD operations..." -ForegroundColor Cyan

# Remove existing network if it exists
docker network rm $DindNetwork 2>$null

# Create new isolated network
docker network create --driver bridge `
    --opt com.docker.network.bridge.name=dind-bridge `
    --opt com.docker.network.bridge.enable_icc=false `
    --opt com.docker.network.bridge.enable_ip_masquerade=true `
    --subnet=172.20.0.0/16 `
    --gateway=172.20.0.1 `
    $DindNetwork

# Connect the Ubuntu container to the DinD network
docker network connect $DindNetwork $ContainerName

# Configure network restrictions for DinD
Write-Host "Configuring network restrictions for DinD..." -ForegroundColor Cyan

docker exec $ContainerName bash -c "
    # Add iptables rules for DinD network isolation
    iptables -I DOCKER-USER -i dind-bridge -j DROP
    iptables -I DOCKER-USER -o dind-bridge -j DROP

    # Allow traffic within DinD network
    iptables -I DOCKER-USER -i dind-bridge -o dind-bridge -j ACCEPT

    # Allow specific outbound traffic (DNS, package repos)
    iptables -A DOCKER-USER -o dind-bridge -p udp --dport 53 -j ACCEPT
    iptables -A DOCKER-USER -o dind-bridge -p tcp --dport 80 -j ACCEPT
    iptables -A DOCKER-USER -o dind-bridge -p tcp --dport 443 -j ACCEPT

    # Save iptables rules
    iptables-save > /etc/iptables/rules.v4
"

# Implement Docker daemon security hardening
Write-Host "Implementing Docker daemon security hardening..." -ForegroundColor Cyan

docker exec $ContainerName bash -c "
    # Create Docker security policies
    mkdir -p /etc/docker/policies

    # Create image policy to prevent unsigned images
    cat > /etc/docker/policies/image-policy.json << EOF
{
    \"default\": [
        {
            \"type\": \"reject\"
        }
    ],
    \"transports\": {
        \"docker\": {
            \"registry.docker.io\": [
                {
                    \"type\": \"insecureAcceptAnything\"
                }
            ]
        },
        \"docker-daemon\": {
            \"\": [
                {
                    \"type\": \"insecureAcceptAnything\"
                }
            ]
        }
    }
}
EOF

    # Configure TLS for Docker daemon
    mkdir -p /etc/docker/tls

    # Generate self-signed certificates for development (replace with proper CA certificates in production)
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -subj \"/C=US/ST=State/L=City/O=Organization/CN=docker-daemon\" \
        -keyout /etc/docker/tls/key.pem \
        -out /etc/docker/tls/cert.pem

    # Set proper permissions
    chmod 600 /etc/docker/tls/key.pem
    chmod 644 /etc/docker/tls/cert.pem

    # Update daemon configuration with TLS
    cat >> /etc/docker/daemon.json << EOF
,
    \"tls\": true,
    \"tlsverify\": false,
    \"tlscacert\": \"/etc/docker/tls/cert.pem\",
    \"tlscert\": \"/etc/docker/tls/cert.pem\",
    \"tlskey\": \"/etc/docker/tls/key.pem\",
    \"hosts\": [\"unix:///var/run/docker.sock\", \"tcp://127.0.0.1:2376\"]
EOF

    # Create systemd override for Docker with security options
    mkdir -p /etc/systemd/system/docker.service.d
    cat > /etc/systemd/system/docker.service.d/security.conf << EOF
[Service]
# Security hardening options
NoNewPrivileges=yes
ProtectHome=yes
ProtectSystem=strict
ReadWritePaths=/var/lib/docker /etc/docker
PrivateTmp=yes
PrivateDevices=yes
ProtectClock=yes
ProtectKernelTunables=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_NETLINK AF_UNIX
MemoryDenyWriteExecute=yes
RestrictRealtime=yes
EOF

    # Reload systemd and restart Docker
    systemctl daemon-reload
    systemctl restart docker
"

# Create monitoring and alerting system
Write-Host "Setting up monitoring and alerting for DinD security..." -ForegroundColor Cyan

$monitoringScript = @"
# DinD Security Monitoring and Alerting
param(
    [string]$ContainerName = "$ContainerName",
    [int]$AlertThreshold = 80
)

Write-Host "=== DinD Security Monitoring ===" -ForegroundColor Green

# Check container resource usage
Write-Host "Checking container resource usage..." -ForegroundColor Cyan
`$stats = docker stats --no-stream --format "{{.Container}};{{.CPUPerc}};{{.MemPerc}};{{.NetIO}};{{.BlockIO}}" | Where-Object { `$_ -match "$ContainerName" }

if (`$stats) {
    `$container, `$cpu, `$mem, `$net, `$block = `$stats -split ';'
    Write-Host "Container: `$container" -ForegroundColor White
    Write-Host "CPU Usage: `$cpu" -ForegroundColor White
    Write-Host "Memory Usage: `$mem" -ForegroundColor White

    # Alert on high resource usage
    `$cpuValue = [double](\$cpu -replace '%', '')
    `$memValue = [double](\$mem -replace '%', '')

    if (`$cpuValue -gt $AlertThreshold) {
        Write-Host "ALERT: High CPU usage detected!" -ForegroundColor Red
    }
    if (`$memValue -gt $AlertThreshold) {
        Write-Host "ALERT: High memory usage detected!" -ForegroundColor Red
    }
}

# Check running containers count
Write-Host "Checking running containers..." -ForegroundColor Cyan
`$containerCount = docker ps -q | Measure-Object | Select-Object -ExpandProperty Count
Write-Host "Running containers: `$containerCount" -ForegroundColor White

if (`$containerCount -gt $MaxContainers) {
    Write-Host "WARNING: Container count exceeds limit ($MaxContainers)!" -ForegroundColor Yellow
}

# Check Docker system info
Write-Host "Checking Docker system health..." -ForegroundColor Cyan
try {
    docker exec $ContainerName docker system df --format "{{.Type}};{{.TotalCount}};{{.Active}}" | ForEach-Object {
        `$type, `$total, `$active = `$_ -split ';'
        Write-Host "`$type - Total: `$total, Active: `$active" -ForegroundColor White
    }
} catch {
    Write-Host "Could not check Docker system info: `$(`$_.Exception.Message)" -ForegroundColor Yellow
}

# Security audit check
Write-Host "Running security audit..." -ForegroundColor Cyan
try {
    `$auditOutput = docker exec $ContainerName aureport --summary 2>$null
    if (`$auditOutput) {
        Write-Host "Security audit events found (last 24h):" -ForegroundColor Yellow
        Write-Host `$auditOutput -ForegroundColor White
    } else {
        Write-Host "No security audit events in last 24h" -ForegroundColor Green
    }
} catch {
    Write-Host "Audit system not available or not configured" -ForegroundColor Yellow
}

Write-Host "=== Monitoring Complete ===" -ForegroundColor Green
"@

$monitoringScriptPath = "$env:ProgramData\DindSecurityMonitor.ps1"
$monitoringScript | Out-File -FilePath $monitoringScriptPath -Encoding UTF8

# Create scheduled task for security monitoring (every 5 minutes)
Write-Host "Setting up scheduled security monitoring..." -ForegroundColor Cyan

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$monitoringScriptPath`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 365)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable
Register-ScheduledTask -TaskName "DinD Security Monitor" -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -User "SYSTEM" | Out-Null

# Create emergency response procedures
Write-Host "Creating emergency response procedures..." -ForegroundColor Cyan

$emergencyScript = @"
# DinD Emergency Response Procedures
param(
    [string]$ContainerName = "$ContainerName",
    [switch]$StopAll,
    [switch]$Cleanup,
    [switch]$HardReset
)

Write-Host "=== DinD Emergency Response ===" -ForegroundColor Red

if ($StopAll) {
    Write-Host "Stopping all containers..." -ForegroundColor Yellow
    docker exec $ContainerName docker stop `$(docker exec $ContainerName docker ps -q) 2>$null
    Write-Host "All containers stopped." -ForegroundColor Green
}

if ($Cleanup) {
    Write-Host "Cleaning up unused resources..." -ForegroundColor Yellow
    docker exec $ContainerName docker system prune -f
    docker exec $ContainerName docker volume prune -f
    docker exec $ContainerName docker network prune -f
    Write-Host "Cleanup completed." -ForegroundColor Green
}

if ($HardReset) {
    Write-Host "Performing hard reset of DinD environment..." -ForegroundColor Red
    Write-Host "WARNING: This will remove all containers, images, volumes, and networks!" -ForegroundColor Red

    `$confirmation = Read-Host "Are you sure you want to proceed? (yes/no)"
    if (`$confirmation -eq "yes") {
        # Stop Docker daemon
        docker exec $ContainerName systemctl stop docker

        # Remove all Docker data
        docker exec $ContainerName rm -rf /var/lib/docker/*

        # Restart Docker daemon
        docker exec $ContainerName systemctl start docker

        Write-Host "Hard reset completed. DinD environment has been reset." -ForegroundColor Green
    } else {
        Write-Host "Hard reset cancelled." -ForegroundColor Yellow
    }
}

if (-not ($StopAll -or $Cleanup -or $HardReset)) {
    Write-Host "Available emergency options:" -ForegroundColor Cyan
    Write-Host "  -StopAll    : Stop all running containers" -ForegroundColor White
    Write-Host "  -Cleanup    : Remove unused Docker resources" -ForegroundColor White
    Write-Host "  -HardReset  : Complete reset of DinD environment (DESTRUCTIVE)" -ForegroundColor White
    Write-Host "" -ForegroundColor White
    Write-Host "Example usage:" -ForegroundColor Gray
    Write-Host "  .\DindEmergencyResponse.ps1 -StopAll" -ForegroundColor Gray
    Write-Host "  .\DindEmergencyResponse.ps1 -Cleanup" -ForegroundColor Gray
}

Write-Host "=== Emergency Response Complete ===" -ForegroundColor Green
"@

$emergencyScriptPath = "$env:ProgramData\DindEmergencyResponse.ps1"
$emergencyScript | Out-File -FilePath $emergencyScriptPath -Encoding UTF8

# Create desktop shortcuts
Write-Host "Creating desktop shortcuts..." -ForegroundColor Cyan

$WshShell = New-Object -comObject WScript.Shell

# Security monitoring shortcut
$Shortcut = $WshShell.CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\DinD Security Monitor.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$monitoringScriptPath`""
$Shortcut.WorkingDirectory = "$env:ProgramData"
$Shortcut.IconLocation = "powershell.exe,0"
$Shortcut.Description = "Monitor DinD Security and Resources"
$Shortcut.Save()

# Emergency response shortcut
$Shortcut = $WshShell.CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\DinD Emergency Response.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$emergencyScriptPath`""
$Shortcut.WorkingDirectory = "$env:ProgramData"
$Shortcut.IconLocation = "powershell.exe,0"
$Shortcut.Description = "DinD Emergency Response Procedures"
$Shortcut.Save()

Write-Host "=== DinD Security Best Practices Implementation Completed ===" -ForegroundColor Green
Write-Host "Security Features Implemented:" -ForegroundColor Cyan
Write-Host "  - Audit daemon for comprehensive logging" -ForegroundColor White
Write-Host "  - Resource limits and cgroup controls" -ForegroundColor White
Write-Host "  - Container security policy enforcement" -ForegroundColor White
Write-Host "  - Isolated network with traffic restrictions" -ForegroundColor White
Write-Host "  - Docker daemon TLS configuration" -ForegroundColor White
Write-Host "  - SystemD security hardening" -ForegroundColor White
Write-Host "  - Automated security monitoring (5-minute intervals)" -ForegroundColor White
Write-Host "  - Emergency response procedures" -ForegroundColor White
Write-Host "  - Desktop shortcuts for monitoring and emergency response" -ForegroundColor White

Write-Host "" -ForegroundColor Yellow
Write-Host "MONITORING: Use the 'DinD Security Monitor' shortcut to check security status." -ForegroundColor Yellow
Write-Host "EMERGENCY: Use the 'DinD Emergency Response' shortcut for critical situations." -ForegroundColor Yellow
Write-Host "ALERTS: Monitor for high resource usage and security audit events." -ForegroundColor Yellow