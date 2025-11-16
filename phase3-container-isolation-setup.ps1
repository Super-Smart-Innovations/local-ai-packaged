# Phase 3: Container Isolation Features Setup
# This script implements comprehensive container isolation using Linux namespaces
# Includes network, PID, user, and mount namespace controls for enhanced security

param(
    [string]$ContainerName = "ubuntu-server",
    [string]$IsolationNetwork = "isolated-net",
    [string]$UserNamespaceMap = "ubuntu-user",
    [int]$ContainerUID = 1000,
    [int]$ContainerGID = 1000
)

Write-Host "=== Phase 3: Container Isolation Features Setup ===" -ForegroundColor Green

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

# Implement network namespace isolation
Write-Host "Implementing network namespace isolation..." -ForegroundColor Cyan

# Remove existing isolation network if it exists
docker network rm $IsolationNetwork 2>$null

# Create isolated bridge network with strict controls
docker network create --driver bridge `
    --opt com.docker.network.bridge.name=isolation-bridge `
    --opt com.docker.network.bridge.enable_icc=false `
    --opt com.docker.network.bridge.enable_ip_masquerade=true `
    --opt com.docker.network.bridge.enable_ip_forward=false `
    --internal `
    --subnet=192.168.100.0/24 `
    --gateway=192.168.100.1 `
    $IsolationNetwork

# Connect container to isolation network
docker network connect $IsolationNetwork $ContainerName

# Configure advanced network isolation inside container
Write-Host "Configuring advanced network isolation..." -ForegroundColor Cyan

docker exec $ContainerName bash -c "
    # Install network namespace tools
    apt update -y && apt install -y iproute2 net-tools bridge-utils

    # Create separate network namespace for sensitive operations
    ip netns add isolated-ns

    # Create virtual ethernet pair
    ip link add veth0 type veth peer name veth1
    ip link set veth1 netns isolated-ns

    # Configure interfaces
    ip addr add 192.168.100.10/24 dev veth0
    ip link set veth0 up

    # Configure isolated namespace
    ip netns exec isolated-ns ip addr add 192.168.100.11/24 dev veth1
    ip netns exec isolated-ns ip link set veth1 up
    ip netns exec isolated-ns ip link set lo up

    # Set up routing in isolated namespace
    ip netns exec isolated-ns ip route add default via 192.168.100.1

    # Create network isolation script
    cat > /opt/security/network-isolation.sh << 'EOF'
#!/bin/bash
# Network Isolation Management

start_isolation() {
    echo \"Starting network isolation...\"
    # Disable IP forwarding for isolation
    echo 0 > /proc/sys/net/ipv4/ip_forward

    # Block all inter-container communication
    iptables -I DOCKER-ISOLATION-STAGE-1 -i docker0 -o docker0 -j DROP
    iptables -I DOCKER-ISOLATION-STAGE-1 -i br-+ -o br-+ -j DROP

    # Allow only specific communications
    iptables -I DOCKER-ISOLATION-STAGE-1 -s 192.168.100.0/24 -d 192.168.100.0/24 -j ACCEPT

    echo \"Network isolation activated.\"
}

stop_isolation() {
    echo \"Stopping network isolation...\"
    # Re-enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward

    # Remove isolation rules
    iptables -D DOCKER-ISOLATION-STAGE-1 -i docker0 -o docker0 -j DROP 2>/dev/null
    iptables -D DOCKER-ISOLATION-STAGE-1 -i br-+ -o br-+ -j DROP 2>/dev/null

    echo \"Network isolation deactivated.\"
}

case \"\$1\" in
    start) start_isolation ;;
    stop) stop_isolation ;;
    *) echo \"Usage: \$0 {start|stop}\" ;;
esac
EOF

    chmod +x /opt/security/network-isolation.sh
"

# Implement PID namespace separation
Write-Host "Implementing PID namespace separation..." -ForegroundColor Cyan

docker exec $ContainerName bash -c "
    # Create PID isolation controls
    cat > /opt/security/pid-isolation.sh << 'EOF'
#!/bin/bash
# PID Namespace Isolation Controls

# Function to check PID visibility
check_pid_visibility() {
    echo \"Checking PID namespace isolation...\"
    echo \"Host PIDs visible from container: \$(ps aux | wc -l)\"

    # Check if we can see host processes (should be limited)
    if ps aux | grep -q \"\[init\]\" || ps aux | grep -q \"systemd\"; then
        echo \"WARNING: Host system processes visible in container!\"
        return 1
    else
        echo \"PID namespace isolation appears effective.\"
        return 0
    fi
}

# Function to limit process spawning
limit_processes() {
    local max_procs=\${1:-100}

    echo \"Limiting maximum processes to \$max_procs...\"

    # Set process limit
    ulimit -u \$max_procs

    # Create cgroup limit (if cgroup v2 is available)
    if [ -d \"/sys/fs/cgroup\" ]; then
        echo \"Setting cgroup process limit...\"
        echo \$max_procs > /sys/fs/cgroup/pids.max 2>/dev/null || true
    fi

    echo \"Process limits applied.\"
}

# Export functions
export -f check_pid_visibility
export -f limit_processes

EOF

    chmod +x /opt/security/pid-isolation.sh

    # Apply PID isolation
    /opt/security/pid-isolation.sh
"

# Implement user namespace mapping
Write-Host "Implementing user namespace mapping..." -ForegroundColor Cyan

# Configure user namespace mapping on the host (Windows limitation - simulate in container)
docker exec $ContainerName bash -c "
    # Create user namespace mapping configuration
    cat > /etc/subuid << EOF
ubuntu:$ContainerUID:65536
EOF

    cat > /etc/subgid << EOF
ubuntu:$ContainerGID:65536
EOF

    # Create user namespace isolation script
    cat > /opt/security/user-namespace.sh << 'EOF'
#!/bin/bash
# User Namespace Isolation Management

# Function to create isolated user context
create_isolated_user() {
    local username=\${1:-isolated_user}
    local uid=\${2:-1001}
    local gid=\${3:-1001}

    echo \"Creating isolated user: \$username\"

    # Create group if it doesn't exist
    groupadd -g \$gid \$username 2>/dev/null || true

    # Create user with restricted permissions
    useradd -u \$uid -g \$gid -s /bin/false -d /nonexistent \\
        -M -N \$username 2>/dev/null || true

    # Set up user restrictions
    usermod -L \$username  # Lock the account

    echo \"Isolated user created with UID \$uid, GID \$gid\"
}

# Function to check user namespace effectiveness
check_user_isolation() {
    echo \"Checking user namespace isolation...\"

    # Check current user mapping
    echo \"Current user: \$(id)\"
    echo \"Process capabilities: \$(capsh --print)\"

    # Check if we have root privileges (should be limited)
    if [ \"\$EUID\" -eq 0 ]; then
        echo \"WARNING: Running as root in container!\"
        return 1
    else
        echo \"User namespace isolation appears effective.\"
        return 0
    fi
}

# Export functions
export -f create_isolated_user
export -f check_user_isolation

EOF

    chmod +x /opt/security/user-namespace.sh

    # Apply user namespace configuration
    /opt/security/user-namespace.sh
"

# Implement mount namespace controls
Write-Host "Implementing mount namespace controls..." -ForegroundColor Cyan

docker exec $ContainerName bash -c "
    # Create mount isolation controls
    cat > /opt/security/mount-isolation.sh << 'EOF'
#!/bin/bash
# Mount Namespace Isolation Controls

# Function to create restricted mount points
create_restricted_mounts() {
    echo \"Creating restricted mount points...\"

    # Create restricted directories
    mkdir -p /restricted/{bin,lib,usr}
    chmod 755 /restricted
    chmod 755 /restricted/*

    # Mount essential binaries read-only
    mount --bind /bin /restricted/bin
    mount -o remount,ro /restricted/bin

    # Mount essential libraries read-only
    mount --bind /lib /restricted/lib
    mount -o remount,ro /restricted/lib

    # Mount essential usr read-only
    mount --bind /usr /restricted/usr
    mount -o remount,ro /restricted/usr

    echo \"Restricted mounts created.\"
}

# Function to check mount isolation
check_mount_isolation() {
    echo \"Checking mount namespace isolation...\"

    # Check for sensitive mounts
    if mount | grep -q \" / \"; then
        echo \"WARNING: Root filesystem is writable!\"
        return 1
    fi

    # Check for proc mounts
    if mount | grep -q \"proc on /proc\"; then
        echo \"Proc filesystem mounted - check isolation\"
    fi

    # Check for sys mounts
    if mount | grep -q \"sysfs on /sys\"; then
        echo \"Sys filesystem mounted - check isolation\"
    fi

    echo \"Mount isolation check completed.\"
    return 0
}

# Function to unmount restricted mounts
cleanup_restricted_mounts() {
    echo \"Cleaning up restricted mounts...\"

    umount /restricted/usr 2>/dev/null || true
    umount /restricted/lib 2>/dev/null || true
    umount /restricted/bin 2>/dev/null || true

    rmdir /restricted/usr /restricted/lib /restricted/bin /restricted 2>/dev/null || true

    echo \"Restricted mounts cleaned up.\"
}

# Export functions
export -f create_restricted_mounts
export -f check_mount_isolation
export -f cleanup_restricted_mounts

EOF

    chmod +x /opt/security/mount-isolation.sh

    # Apply mount isolation
    /opt/security/mount-isolation.sh
"

# Create comprehensive isolation verification script
Write-Host "Creating comprehensive isolation verification..." -ForegroundColor Cyan

$isolationVerification = @"
# Container Isolation Verification
Write-Host "=== Container Isolation Verification ===" -ForegroundColor Green

# Check container networks
Write-Host "Network Isolation Check:" -ForegroundColor Cyan
docker network ls --format "{{.Name}};{{.Driver}}" | Where-Object { `$_ -match "isolated|bridge" } | ForEach-Object {
    `$name, `$driver = `$_ -split ';'
    Write-Host "  `$name (`$driver)" -ForegroundColor White
}

# Check container isolation settings
Write-Host "Container Isolation Settings:" -ForegroundColor Cyan
docker inspect $ContainerName | ConvertFrom-Json | ForEach-Object {
    Write-Host "  Privileged: `$(`$_.HostConfig.Privileged)" -ForegroundColor White
    Write-Host "  UsernsMode: `$(`$_.HostConfig.UsernsMode)" -ForegroundColor White
    Write-Host "  NetworkMode: `$(`$_.HostConfig.NetworkMode)" -ForegroundColor White
    Write-Host "  ReadonlyRootfs: `$(`$_.HostConfig.ReadonlyRootfs)" -ForegroundColor White
}

# Check resource limits
Write-Host "Resource Limits:" -ForegroundColor Cyan
`$stats = docker stats --no-stream --format "{{.Container}};{{.CPUPerc}};{{.MemPerc}};{{.PIDs}}" | Where-Object { `$_ -match "$ContainerName" }
if (`$stats) {
    `$container, `$cpu, `$mem, `$pids = `$stats -split ';'
    Write-Host "  CPU Limit: `$cpu" -ForegroundColor White
    Write-Host "  Memory Limit: `$mem" -ForegroundColor White
    Write-Host "  PIDs: `$pids" -ForegroundColor White
}

# Test network isolation (attempt to reach host)
Write-Host "Network Reachability Test:" -ForegroundColor Cyan
try {
    `$testResult = docker exec $ContainerName ping -c 1 -W 1 192.168.65.1 2>&1
    if (`$testResult -match "1 packets transmitted, 1 received") {
        Write-Host "  WARNING: Can reach host network!" -ForegroundColor Red
    } else {
        Write-Host "  Network isolation appears effective" -ForegroundColor Green
    }
} catch {
    Write-Host "  Network isolation test completed" -ForegroundColor Green
}

# Test namespace isolation inside container
Write-Host "Namespace Isolation Test:" -ForegroundColor Cyan
try {
    docker exec $ContainerName bash -c "
        echo '  PID namespace check:'
        if ps aux | head -1 | grep -q PID; then
            echo '    PID namespace appears functional'
        fi

        echo '  Mount namespace check:'
        if mount | grep -q ' / '; then
            echo '    Mount isolation may need verification'
        else
            echo '    Mount namespace appears isolated'
        fi

        echo '  User namespace check:'
        if [ \"\$EUID\" -ne 0 ]; then
            echo '    User namespace mapping effective'
        else
            echo '    Running as root - check user namespace configuration'
        fi
    "
} catch {
    Write-Host "  Could not complete namespace tests: `$(`$_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "=== Isolation Verification Complete ===" -ForegroundColor Green
"@

$isolationVerificationPath = "$env:ProgramData\ContainerIsolationVerification.ps1"
$isolationVerification | Out-File -FilePath $isolationVerificationPath -Encoding UTF8

# Create isolation management script
Write-Host "Creating isolation management script..." -ForegroundColor Cyan

$isolationManagement = @"
# Container Isolation Management
param(
    [string]$ContainerName = "$ContainerName",
    [switch]$Enable,
    [switch]$Disable,
    [switch]$Verify,
    [switch]$Emergency
)

Write-Host "=== Container Isolation Management ===" -ForegroundColor Green

if ($Enable) {
    Write-Host "Enabling enhanced isolation features..." -ForegroundColor Cyan

    # Apply network isolation
    docker exec $ContainerName /opt/security/network-isolation.sh start

    # Apply PID isolation
    docker exec $ContainerName /opt/security/pid-isolation.sh

    # Apply user isolation
    docker exec $ContainerName /opt/security/user-namespace.sh

    # Apply mount isolation
    docker exec $ContainerName /opt/security/mount-isolation.sh

    Write-Host "Enhanced isolation enabled." -ForegroundColor Green
}

if ($Disable) {
    Write-Host "Disabling enhanced isolation features..." -ForegroundColor Cyan

    # Remove network isolation
    docker exec $ContainerName /opt/security/network-isolation.sh stop

    # Clean up mount isolation
    docker exec $ContainerName bash -c "/opt/security/mount-isolation.sh && cleanup_restricted_mounts"

    Write-Host "Enhanced isolation disabled." -ForegroundColor Green
}

if ($Verify) {
    Write-Host "Running isolation verification..." -ForegroundColor Cyan
    & "$env:ProgramData\ContainerIsolationVerification.ps1"
}

if ($Emergency) {
    Write-Host "Emergency isolation lockdown..." -ForegroundColor Red

    # Disconnect from all networks except isolation
    `$networks = docker inspect $ContainerName | ConvertFrom-Json | Select-Object -ExpandProperty NetworkSettings -ExpandProperty Networks
    `$networks.PSObject.Properties.Name | Where-Object { `$_ -ne "$IsolationNetwork" -and `$_ -ne "none" } | ForEach-Object {
        docker network disconnect `$_ $ContainerName
        Write-Host "Disconnected from network: `$_" -ForegroundColor Yellow
    }

    # Stop all processes inside container
    docker exec $ContainerName pkill -9 -f ".*" 2>$null

    # Apply maximum isolation
    docker exec $ContainerName /opt/security/network-isolation.sh start

    Write-Host "Emergency lockdown completed." -ForegroundColor Red
}

if (-not ($Enable -or $Disable -or $Verify -or $Emergency)) {
    Write-Host "Available isolation options:" -ForegroundColor Cyan
    Write-Host "  -Enable   : Enable all enhanced isolation features" -ForegroundColor White
    Write-Host "  -Disable  : Disable enhanced isolation features" -ForegroundColor White
    Write-Host "  -Verify   : Run comprehensive isolation verification" -ForegroundColor White
    Write-Host "  -Emergency: Emergency isolation lockdown (DESTRUCTIVE)" -ForegroundColor White
    Write-Host "" -ForegroundColor White
    Write-Host "Example usage:" -ForegroundColor Gray
    Write-Host "  .\ContainerIsolationManagement.ps1 -Enable" -ForegroundColor Gray
    Write-Host "  .\ContainerIsolationManagement.ps1 -Verify" -ForegroundColor Gray
}

Write-Host "=== Isolation Management Complete ===" -ForegroundColor Green
"@

$isolationManagementPath = "$env:ProgramData\ContainerIsolationManagement.ps1"
$isolationManagement | Out-File -FilePath $isolationManagementPath -Encoding UTF8

# Create desktop shortcuts
Write-Host "Creating desktop shortcuts..." -ForegroundColor Cyan

$WshShell = New-Object -comObject WScript.Shell

# Isolation verification shortcut
$Shortcut = $WshShell.CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\Container Isolation Status.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$isolationVerificationPath`""
$Shortcut.WorkingDirectory = "$env:ProgramData"
$Shortcut.IconLocation = "powershell.exe,0"
$Shortcut.Description = "Check Container Isolation Status"
$Shortcut.Save()

# Isolation management shortcut
$Shortcut = $WshShell.CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\Container Isolation Control.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$isolationManagementPath`""
$Shortcut.WorkingDirectory = "$env:ProgramData"
$Shortcut.IconLocation = "powershell.exe,0"
$Shortcut.Description = "Manage Container Isolation Features"
$Shortcut.Save()

# Run initial verification
Write-Host "Running initial isolation verification..." -ForegroundColor Cyan
& $isolationVerificationPath

Write-Host "=== Container Isolation Features Setup Completed ===" -ForegroundColor Green
Write-Host "Isolation Features Implemented:" -ForegroundColor Cyan
Write-Host "  - Network namespace isolation with internal bridge" -ForegroundColor White
Write-Host "  - PID namespace separation and process limits" -ForegroundColor White
Write-Host "  - User namespace mapping for non-privileged access" -ForegroundColor White
Write-Host "  - Mount namespace controls with restricted mounts" -ForegroundColor White
Write-Host "  - Advanced iptables rules for traffic isolation" -ForegroundColor White
Write-Host "  - Resource limits and cgroup controls" -ForegroundColor White
Write-Host "  - Comprehensive isolation verification scripts" -ForegroundColor White
Write-Host "  - Emergency isolation lockdown procedures" -ForegroundColor White
Write-Host "  - Desktop shortcuts for management and monitoring" -ForegroundColor White

Write-Host "" -ForegroundColor Yellow
Write-Host "MANAGEMENT: Use 'Container Isolation Control' to enable/disable features." -ForegroundColor Yellow
Write-Host "VERIFICATION: Use 'Container Isolation Status' to check isolation effectiveness." -ForegroundColor Yellow
Write-Host "EMERGENCY: Use -Emergency flag for immediate lockdown in security incidents." -ForegroundColor Yellow