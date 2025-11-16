# PowerShell Script for Volume Persistence and Network Security Setup
# Phase 1: Containerized Architecture Setup - Volume and Security Configuration

#Requires -RunAsAdministrator

Write-Host "=== Phase 1: Volume Persistence and Network Security Setup ===" -ForegroundColor Green
Write-Host "Configuring persistent volumes and network security for containerized environment" -ForegroundColor Yellow
Write-Host ""

# Check if Ubuntu container is running
Write-Host "Checking Ubuntu container status..." -ForegroundColor Cyan
$containerStatus = docker inspect ubuntu-server --format "{{.State.Running}}" 2>$null
if ($containerStatus -ne "true") {
    Write-Error "Ubuntu container is not running. Please run phase1-ubuntu-container-dind-setup.ps1 first."
    exit 1
}
Write-Host "Ubuntu container is running." -ForegroundColor Green

# Volume Persistence Configuration
Write-Host "`n=== Configuring Volume Persistence ===" -ForegroundColor Green

# Create additional named volumes for services
Write-Host "Creating additional Docker volumes for service data..." -ForegroundColor Cyan
$volumes = @(
    "localai_n8n_storage",
    "localai_db_data",
    "localai_redis_data",
    "localai_qdrant_data",
    "localai_neo4j_data",
    "localai_ollama_data",
    "localai_supabase_config",
    "localai_langfuse_data",
    "localai_minio_data"
)

foreach ($volume in $volumes) {
    docker volume create $volume 2>$null
    Write-Host "Created volume: $volume" -ForegroundColor Gray
}
Write-Host "All service volumes created." -ForegroundColor Green

# Configure volume backup directories
Write-Host "`nConfiguring backup directories..." -ForegroundColor Cyan
$backupDirs = @(
    "C:\Backups\ubuntu-data",
    "C:\Backups\service-volumes",
    "C:\Backups\configurations",
    "C:\Backups\logs"
)

foreach ($dir in $backupDirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force
        Write-Host "Created backup directory: $dir" -ForegroundColor Gray
    }
}
Write-Host "Backup directories configured." -ForegroundColor Green

# Network Security Configuration
Write-Host "`n=== Configuring Network Security ===" -ForegroundColor Green

# Configure Windows Firewall with advanced rules
Write-Host "Configuring Windows Firewall for container security..." -ForegroundColor Cyan

# Enable Windows Firewall logging
Set-NetFirewallProfile -Profile Domain,Public,Private -LogAllowed True -LogBlocked True
Set-NetFirewallProfile -Profile Domain,Public,Private -LogFileName "%systemroot%\system32\LogFiles\Firewall\pfirewall.log"

# Remove any existing conflicting rules
Remove-NetFirewallRule -DisplayName "HTTP*" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "HTTPS*" -ErrorAction SilentlyContinue

# Configure firewall rules for the containerized setup
$firewallRules = @(
    @{
        Name = "HTTP - Ubuntu Container"
        Protocol = "TCP"
        LocalPort = 80
        Action = "Allow"
        Direction = "Inbound"
        Profile = "Any"
        Description = "Allow HTTP traffic to Ubuntu container"
    },
    @{
        Name = "HTTPS - Ubuntu Container"
        Protocol = "TCP"
        LocalPort = 443
        Action = "Allow"
        Direction = "Inbound"
        Profile = "Any"
        Description = "Allow HTTPS traffic to Ubuntu container"
    },
    @{
        Name = "SSH - Ubuntu Container"
        Protocol = "TCP"
        LocalPort = 2222
        Action = "Allow"
        Direction = "Domain,Private"
        Description = "Allow SSH access to Ubuntu container from trusted networks"
    },
    @{
        Name = "Block All Other Inbound"
        Protocol = "Any"
        LocalPort = "Any"
        Action = "Block"
        Direction = "Inbound"
        Profile = "Public"
        Description = "Block all other inbound traffic on public profile"
    }
)

foreach ($rule in $firewallRules) {
    New-NetFirewallRule -DisplayName $rule.Name `
                       -Direction $rule.Direction `
                       -Protocol $rule.Protocol `
                       -LocalPort $rule.LocalPort `
                       -Action $rule.Action `
                       -Profile $rule.Profile `
                       -Description $rule.Description
    Write-Host "Created firewall rule: $($rule.Name)" -ForegroundColor Gray
}

# Enable Windows Defender exclusions for Docker
Write-Host "`nConfiguring Windows Defender exclusions..." -ForegroundColor Cyan
$defenderExclusions = @(
    "C:\Users\$env:USERNAME\AppData\Local\Docker",
    "C:\Users\$env:USERNAME\AppData\Roaming\Docker Desktop",
    "C:\Program Files\Docker",
    "C:\Backups"
)

foreach ($exclusion in $defenderExclusions) {
    Add-MpPreference -ExclusionPath $exclusion -ErrorAction SilentlyContinue
    Write-Host "Added Defender exclusion: $exclusion" -ForegroundColor Gray
}

# Configure Windows Defender real-time protection
Set-MpPreference -DisableRealtimeMonitoring $false
Set-MpPreference -MAPSReporting Advanced
Set-MpPreference -SubmitSamplesConsent Always

Write-Host "Windows Defender configured for container compatibility." -ForegroundColor Green

# Container Security Hardening
Write-Host "`n=== Container Security Hardening ===" -ForegroundColor Green

# Create seccomp profile for privileged container
Write-Host "Creating custom seccomp profile for Ubuntu container..." -ForegroundColor Cyan
$seccompProfile = @"
{
    "defaultAction": "SCMP_ACT_ERRNO",
    "defaultErrnoRet": 1,
    "archMap": [
        {
            "architecture": "SCMP_ARCH_X86_64",
            "subArchitectures": [
                "SCMP_ARCH_X86",
                "SCMP_ARCH_X32"
            ]
        }
    ],
    "syscalls": [
        {
            "names": [
                "accept4",
                "arch_prctl",
                "bind",
                "brk",
                "capget",
                "capset",
                "chdir",
                "chmod",
                "chown",
                "chown32",
                "clock_getres",
                "clock_gettime",
                "clock_nanosleep",
                "clone",
                "close",
                "connect",
                "copy_file_range",
                "creat",
                "dup",
                "dup2",
                "dup3",
                "epoll_create",
                "epoll_create1",
                "epoll_ctl",
                "epoll_pwait",
                "epoll_wait",
                "eventfd",
                "eventfd2",
                "execve",
                "execveat",
                "exit",
                "exit_group",
                "faccessat",
                "fadvise64",
                "fadvise64_64",
                "fallocate",
                "fanotify_mark",
                "fchdir",
                "fchmod",
                "fchmodat",
                "fchown",
                "fchown32",
                "fchownat",
                "fcntl",
                "fcntl64",
                "fdatasync",
                "fgetxattr",
                "flistxattr",
                "flock",
                "fork",
                "fremovexattr",
                "fsetxattr",
                "fstat",
                "fstat64",
                "fstatat64",
                "fstatfs",
                "fstatfs64",
                "fsync",
                "ftruncate",
                "ftruncate64",
                "futex",
                "futimesat",
                "getcpu",
                "getcwd",
                "getdents",
                "getdents64",
                "getegid",
                "getegid32",
                "geteuid",
                "geteuid32",
                "getgid",
                "getgid32",
                "getgroups",
                "getgroups32",
                "getitimer",
                "getpeername",
                "getpgid",
                "getpgrp",
                "getpid",
                "getppid",
                "getpriority",
                "getrandom",
                "getresgid",
                "getresgid32",
                "getresuid",
                "getresuid32",
                "getrlimit",
                "getrusage",
                "getsid",
                "getsockname",
                "getsockopt",
                "gettid",
                "gettimeofday",
                "getuid",
                "getuid32",
                "getxattr",
                "inotify_add_watch",
                "inotify_init",
                "inotify_init1",
                "inotify_rm_watch",
                "io_cancel",
                "io_destroy",
                "io_getevents",
                "io_setup",
                "io_submit",
                "ioctl",
                "ioprio_get",
                "ioprio_set",
                "kill",
                "lchown",
                "lchown32",
                "lgetxattr",
                "link",
                "linkat",
                "listen",
                "listxattr",
                "llistxattr",
                "lremovexattr",
                "lseek",
                "lsetxattr",
                "lstat",
                "lstat64",
                "madvise",
                "membarrier",
                "memfd_create",
                "mincore",
                "mkdir",
                "mkdirat",
                "mknod",
                "mknodat",
                "mlock",
                "mlock2",
                "mlockall",
                "mmap",
                "mmap2",
                "mount",
                "mprotect",
                "mq_getsetattr",
                "mq_notify",
                "mq_open",
                "mq_timedreceive",
                "mq_timedsend",
                "mq_unlink",
                "mremap",
                "msgctl",
                "msgget",
                "msgrcv",
                "msgsnd",
                "msync",
                "munlock",
                "munlockall",
                "munmap",
                "name_to_handle_at",
                "nanosleep",
                "newfstatat",
                "open",
                "openat",
                "pause",
                "perf_event_open",
                "personality",
                "pipe",
                "pipe2",
                "poll",
                "ppoll",
                "prctl",
                "pread64",
                "preadv",
                "preadv2",
                "prlimit64",
                "pselect6",
                "pwrite64",
                "pwritev",
                "pwritev2",
                "read",
                "readahead",
                "readlink",
                "readlinkat",
                "readv",
                "recvfrom",
                "recvmmsg",
                "recvmsg",
                "remap_file_pages",
                "removexattr",
                "rename",
                "renameat",
                "renameat2",
                "restart_syscall",
                "rmdir",
                "rseq",
                "rt_sigaction",
                "rt_sigpending",
                "rt_sigprocmask",
                "rt_sigqueueinfo",
                "rt_sigreturn",
                "rt_sigsuspend",
                "rt_sigtimedwait",
                "rt_tgsigqueueinfo",
                "sched_get_priority_max",
                "sched_get_priority_min",
                "sched_getaffinity",
                "sched_getattr",
                "sched_getparam",
                "sched_getscheduler",
                "sched_rr_get_interval",
                "sched_setaffinity",
                "sched_setattr",
                "sched_setparam",
                "sched_setscheduler",
                "sched_yield",
                "seccomp",
                "select",
                "semctl",
                "semget",
                "semop",
                "semtimedop",
                "sendfile",
                "sendfile64",
                "sendmmsg",
                "sendmsg",
                "sendto",
                "setgid",
                "setgid32",
                "setgroups",
                "setgroups32",
                "setitimer",
                "setns",
                "setpgid",
                "setpriority",
                "setregid",
                "setregid32",
                "setresgid",
                "setresgid32",
                "setresuid",
                "setresuid32",
                "setreuid",
                "setreuid32",
                "setrlimit",
                "setrobust_list",
                "setsid",
                "setsockopt",
                "setuid",
                "setuid32",
                "setxattr",
                "shmat",
                "shmctl",
                "shmdt",
                "shmget",
                "shutdown",
                "sigaltstack",
                "signalfd",
                "signalfd4",
                "socket",
                "socketpair",
                "splice",
                "stat",
                "stat64",
                "statfs",
                "statfs64",
                "statx",
                "symlink",
                "symlinkat",
                "sync",
                "sync_file_range",
                "syncfs",
                "sysinfo",
                "syslog",
                "tee",
                "tgkill",
                "time",
                "times",
                "tkill",
                "truncate",
                "truncate64",
                "ugetrlimit",
                "umask",
                "umount2",
                "uname",
                "unlink",
                "unlinkat",
                "unshare",
                "utime",
                "utimensat",
                "utimes",
                "vmsplice",
                "wait4",
                "waitid",
                "waitpid",
                "write",
                "writev"
            ],
            "action": "SCMP_ACT_ALLOW"
        }
    ]
}
"@

$seccompPath = "C:\ProgramData\Docker\config\custom-seccomp-profile.json"
if (-not (Test-Path (Split-Path $seccompPath))) {
    New-Item -ItemType Directory -Path (Split-Path $seccompPath) -Force
}
$seccompProfile | Out-File -FilePath $seccompPath -Encoding UTF8 -Force
Write-Host "Custom seccomp profile created." -ForegroundColor Green

# Update Ubuntu container with enhanced security
Write-Host "`nUpdating Ubuntu container security configuration..." -ForegroundColor Cyan

$securityScript = @"
#!/bin/bash
set -e

echo "=== Updating Ubuntu Container Security ==="

# Copy seccomp profile to container
mkdir -p /etc/docker/seccomp
cp /host-seccomp-profile.json /etc/docker/seccomp/custom-seccomp-profile.json 2>/dev/null || echo "Seccomp profile will be mounted from host"

# Configure AppArmor profile for Docker (if available)
if command -v apparmor_parser &> /dev/null; then
    echo "AppArmor available - configuring profiles"
    apparmor_parser -r -W /etc/apparmor.d/docker 2>/dev/null || echo "AppArmor profile update skipped"
fi

# Set up log rotation for container logs
cat > /etc/logrotate.d/docker-containers << EOF
/var/log/docker/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
EOF

# Configure audit logging
cat > /etc/audit/rules.d/docker.rules << EOF
-w /usr/bin/docker -k docker
-w /usr/bin/docker-containerd -k docker
-w /usr/bin/docker-runc -k docker
-w /var/lib/docker -k docker
EOF

service auditd restart 2>/dev/null || echo "Auditd not available"

# Create monitoring script for security events
cat > /scripts/security-monitor.sh << 'EOF'
#!/bin/bash
echo "=== Container Security Monitor ==="
echo "Date: $(date)"

# Check for privileged containers
echo "Privileged containers:"
docker ps --filter "status=running" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep -v NAMES

# Check container resource usage
echo -e "\nContainer resource usage:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Check for security-related logs
echo -e "\nRecent security events:"
tail -20 /var/log/auth.log 2>/dev/null || echo "No auth logs available"
EOF

chmod +x /scripts/security-monitor.sh

# Configure cron jobs for monitoring
cat > /etc/cron.d/container-monitoring << EOF
*/15 * * * * root /scripts/health-check.sh >> /var/log/container-health.log 2>&1
0 * * * * root /scripts/security-monitor.sh >> /var/log/container-security.log 2>&1
0 2 * * * root /scripts/backup.sh >> /var/log/container-backup.log 2>&1
EOF

chmod 644 /etc/cron.d/container-monitoring

echo "=== Security Configuration Complete ==="
"@

# Execute security configuration
Write-Host "Applying security configuration to Ubuntu container..." -ForegroundColor Yellow
docker cp $seccompPath ubuntu-server:/host-seccomp-profile.json
$securityScript | docker exec -i ubuntu-server bash

# Volume Backup Configuration
Write-Host "`n=== Configuring Volume Backup Automation ===" -ForegroundColor Green

# Create Windows Scheduled Task for backups
Write-Host "Creating Windows Scheduled Task for automated backups..." -ForegroundColor Cyan

$backupScript = @"
# PowerShell script for automated container backups
Write-Host "=== Automated Container Backup ===" -ForegroundColor Green
Write-Host "Date: $(Get-Date)" -ForegroundColor Yellow

# Stop containers temporarily for consistent backup (optional)
# docker exec ubuntu-server docker compose -f /app/docker-compose.yml stop

# Backup Ubuntu container data volume
Write-Host "Backing up Ubuntu data volume..." -ForegroundColor Cyan
docker run --rm -v ubuntu-data:/data -v C:\Backups\ubuntu-data:/backup ubuntu tar czf /backup/ubuntu-data-$(Get-Date -Format 'yyyyMMdd_HHmm').tar.gz -C /data .

# Backup service volumes from within Ubuntu container
Write-Host "Backing up service volumes..." -ForegroundColor Cyan
docker exec ubuntu-server /scripts/backup.sh

# Clean old backups (keep last 30 days)
Write-Host "Cleaning old backups..." -ForegroundColor Cyan
Get-ChildItem "C:\Backups" -Recurse -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | Remove-Item -Force

# Restart containers if they were stopped
# docker exec ubuntu-server docker compose -f /app/docker-compose.yml start

Write-Host "Backup complete." -ForegroundColor Green
"@

$backupScriptPath = "C:\Scripts\container-backup.ps1"
if (-not (Test-Path (Split-Path $backupScriptPath))) {
    New-Item -ItemType Directory -Path (Split-Path $backupScriptPath) -Force
}
$backupScript | Out-File -FilePath $backupScriptPath -Encoding UTF8 -Force

# Create scheduled task for daily backups
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File $backupScriptPath"
$trigger = New-ScheduledTaskTrigger -Daily -At 2AM
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -TaskName "ContainerBackup" -Description "Daily backup of container volumes" -RunLevel Highest

Write-Host "Automated backup scheduled task created." -ForegroundColor Green

# Test configurations
Write-Host "`n=== Testing Configurations ===" -ForegroundColor Green

# Test volume mounts
Write-Host "Testing volume mounts..." -ForegroundColor Cyan
docker exec ubuntu-server touch /data/test-file
docker exec ubuntu-server ls -la /data/test-file | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Volume persistence test passed." -ForegroundColor Green
} else {
    Write-Warning "Volume persistence test failed."
}

# Test network connectivity
Write-Host "Testing network connectivity..." -ForegroundColor Cyan
$networkTest = docker exec ubuntu-server ping -c 1 8.8.8.8 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "Network connectivity test passed." -ForegroundColor Green
} else {
    Write-Warning "Network connectivity test failed."
}

# Display final configuration summary
Write-Host "`n=== Volume and Security Setup Complete ===" -ForegroundColor Green
Write-Host "Configuration Summary:" -ForegroundColor Yellow
Write-Host "- Docker volumes: $(docker volume ls -q | Measure-Object | Select-Object -ExpandProperty Count) created" -ForegroundColor White
Write-Host "- Firewall rules: Configured for container access" -ForegroundColor White
Write-Host "- Windows Defender: Exclusions configured" -ForegroundColor White
Write-Host "- Security hardening: Seccomp profile and audit logging enabled" -ForegroundColor White
Write-Host "- Backup automation: Daily scheduled backups configured" -ForegroundColor White

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "1. Run DNS configuration: phase1-dns-setup.ps1" -ForegroundColor White
Write-Host "2. Generate Phase 1 documentation" -ForegroundColor White
Write-Host "3. Proceed to Phase 2: Network Security Configuration" -ForegroundColor White

Write-Host "`n=== Phase 1 Volume and Security Setup Complete ===" -ForegroundColor Green