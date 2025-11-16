# Backup Operations and Emergency Response Guide

## Overview

This guide provides comprehensive procedures for backup operations, emergency response, and business continuity for the Local AI Services platform deployed on Windows with Docker.

## Backup Architecture

### Backup Types

1. **Configuration Backups**
   - Files: docker-compose.yml, Caddyfile, service configs
   - Frequency: Daily
   - Retention: 30 days

2. **Docker Volume Backups**
   - Volumes: n8n_storage, ollama_storage, qdrant_storage, etc.
   - Frequency: Daily
   - Method: Docker volume snapshots with tar compression

3. **Nested Service Backups**
   - Services: PostgreSQL, Redis/Valkey, Qdrant, Neo4j, Ollama
   - Frequency: Weekly
   - Method: Service-specific dump commands

4. **Ubuntu Container Backups**
   - Target: Ubuntu-based containers
   - Frequency: Daily
   - Method: Volume snapshots

### Storage Layout

```
C:\backups\
├── configurations\        # Configuration files
│   └── 20241109_020000\  # Timestamped backup directories
├── docker-volumes\       # Docker volume archives
├── nested-services\      # Service-specific backups
├── ubuntu-volumes\       # Ubuntu container data
└── reports\              # Backup reports and logs
```

## Automated Backup Operations

### Daily Backup Schedule

Run daily at 2:00 AM via Windows Task Scheduler:

```powershell
.\backup-orchestrator.ps1 -Daily -BackupRoot "C:\backups"
```

This executes:
- Configuration backup
- Ubuntu volume backup
- Docker volume backup

### Weekly Backup Schedule

Run weekly on Sunday at 3:00 AM:

```powershell
.\backup-orchestrator.ps1 -Weekly -BackupRoot "C:\backups"
```

This executes:
- Nested services backup (PostgreSQL, Redis, etc.)

### Manual Backup Execution

```powershell
# Full system backup
.\backup-orchestrator.ps1 -FullSystem -BackupRoot "C:\backups"

# Individual component backups
.\backup-configurations.ps1 -BackupPath "C:\backups\configurations"
.\backup-docker-volumes.ps1 -BackupPath "C:\backups\docker-volumes"
.\backup-ubuntu-volumes.ps1 -BackupPath "C:\backups\ubuntu-volumes"
```

## Backup Verification

### Automated Verification

Run verification weekly or after major changes:

```powershell
.\backup-verification.ps1 -TestType All -BackupRoot "C:\backups" -ReportPath "C:\reports"
```

### Manual Verification Steps

1. **Check Backup Integrity**
   ```powershell
   # Test archive integrity
   & tar -tzf "C:\backups\docker-volumes\latest\n8n_storage.tar.gz"
   ```

2. **Verify File Counts**
   ```powershell
   # Compare file counts
   $original = (Get-ChildItem "C:\docker-volumes\n8n_storage" -Recurse -File).Count
   $backup = (& tar -tzf "C:\backups\docker-volumes\latest\n8n_storage.tar.gz" | Measure-Object).Count
   ```

3. **Test Restore Capability**
   ```powershell
   # Test restore procedure (see disaster recovery section)
   ```

## Emergency Response Procedures

### Incident Classification

- **Level 1**: Single service degradation (< 1 hour impact)
- **Level 2**: Multiple service failure (1-4 hours impact)
- **Level 3**: Complete system outage (> 4 hours impact)

### Immediate Response (First 15 minutes)

1. **Assess Situation**
   - Check service status: `docker compose -p localai ps`
   - Review recent logs: `docker compose -p localai logs --tail 100`
   - Verify backup accessibility

2. **Stop Damage Propagation**
   - Stop affected services: `docker compose -p localai stop <service>`
   - Isolate failing components

3. **Notify Response Team**
   - Alert DevOps team via established channels
   - Document incident start time and symptoms

### Service-Specific Recovery

#### N8N/Open WebUI/Flowise Recovery

```bash
# Stop service
docker compose -p localai stop n8n

# Restore volume if needed
docker run --rm -v n8n_storage:/dest -v /backups:/backup alpine sh -c "cd /dest && tar xzf /backup/docker-volumes/latest/n8n_storage.tar.gz"

# Restart service
docker compose -p localai start n8n
```

#### Database Recovery (PostgreSQL)

```bash
# Stop dependent services
docker compose -p localai stop n8n langfuse-web langfuse-worker

# Restore database
gunzip < /backups/nested-services/latest/postgresql_backup.sql.gz | docker exec -i db psql -U postgres postgres

# Restart services
docker compose -p localai start n8n langfuse-web langfuse-worker
```

#### Redis/Valkey Recovery

```bash
# Stop Redis
docker compose -p localai stop redis

# Restore data
docker run --rm -v valkey-data:/data alpine sh -c "rm -rf /data/*"
docker run --rm -v valkey-data:/data -v /backups:/backup alpine sh -c "cd /data && gunzip < /backup/nested-services/latest/redis_backup.rdb.gz > dump.rdb"

# Restart Redis
docker compose -p localai start redis
```

### Complete System Recovery

#### Preparation (30 minutes)

1. **Verify Environment**
   - Ensure Docker Desktop is running
   - Confirm backup media is accessible
   - Prepare recovery workspace

2. **Stop All Services**
   ```bash
   docker compose -p localai down
   ```

#### Configuration Restoration (30 minutes)

```powershell
# Restore configuration files
$configFiles = @(
    "docker-compose.yml",
    "Caddyfile",
    "searxng/settings-base.yml"
)

foreach ($file in $configFiles) {
    Copy-Item "C:\backups\configurations\latest\$file" . -Force
}
```

#### Volume Restoration (60 minutes)

```powershell
# Restore Docker volumes
$volumes = @("n8n_storage", "ollama_storage", "qdrant_storage", "open-webui", "flowise")

foreach ($volume in $volumes) {
    # Remove existing volume
    docker volume rm $volume 2>$null

    # Create new volume
    docker volume create $volume

    # Restore data
    $backupFile = "C:\backups\docker-volumes\latest\$volume.tar.gz"
    if (Test-Path $backupFile) {
        docker run --rm -v ${volume}:/dest -v (Split-Path $backupFile -Parent):/backup alpine sh -c "cd /dest && tar xzf /backup/$([System.IO.Path]::GetFileName($backupFile))"
    }
}
```

#### Database Restoration (30 minutes)

```bash
# Restore PostgreSQL
gunzip < /backups/nested-services/latest/postgresql_backup.sql.gz | docker exec -i db psql -U postgres postgres

# Restore Redis
docker run --rm -v valkey-data:/data alpine sh -c "rm -rf /data/*"
docker run --rm -v valkey-data:/data -v /backups:/backup alpine sh -c "cd /data && gunzip < /backup/nested-services/latest/redis_backup.rdb.gz > dump.rdb"
```

#### Service Restart and Validation (60 minutes)

```bash
# Rebuild and start services
docker compose -p localai build --no-cache
docker compose -p localai up -d

# Wait for services to start
sleep 300

# Validate services
docker compose -p localai ps
docker compose -p localai logs --tail 50
```

## Monitoring and Alerting

### Health Checks

```powershell
# Service health check script
function Test-ServiceHealth {
    $services = @(
        @{Name="n8n"; Port=5678},
        @{Name="open-webui"; Port=3000},
        @{Name="caddy"; Port=80}
    )

    foreach ($service in $services) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$($service.Port)" -TimeoutSec 10
            Write-Host "$($service.Name): Healthy" -ForegroundColor Green
        }
        catch {
            Write-Host "$($service.Name): Unhealthy" -ForegroundColor Red
        }
    }
}
```

### Backup Monitoring

- Check backup job completion daily
- Review backup logs for errors
- Monitor backup storage usage
- Verify backup integrity weekly

## Contingency Plans

### Cold Standby Setup

1. **Hardware Provisioning**
   - Equivalent Windows Server with Docker Desktop
   - Storage capacity: 2x production requirements

2. **Software Configuration**
   - Install Docker Desktop and prerequisites
   - Clone repository and configure environment
   - Set up backup synchronization

3. **Activation Procedure**
   - Update DNS routing to standby server
   - Restore from latest backups
   - Start services and validate functionality

### Geographic Redundancy

1. **Offsite Backup Storage**
   - Cloud storage (AWS S3, Azure Blob Storage)
   - Encrypted transmission using rsync or rclone
   - Geographic separation (different availability zone)

2. **Cross-Region Failover**
   - DNS-based routing with health check monitoring
   - Automated backup replication
   - Documented procedures for region switching

## Maintenance Procedures

### Monthly Tasks

1. **Backup Verification**
   ```powershell
   .\backup-verification.ps1 -TestType All -ReportPath "C:\reports\monthly-$(Get-Date -Format 'yyyyMM')"
   ```

2. **Storage Capacity Review**
   - Check backup storage utilization
   - Plan for capacity expansion if needed

3. **Retention Policy Audit**
   - Verify old backups are properly cleaned up
   - Ensure compliance with retention requirements

### Quarterly Tasks

1. **Disaster Recovery Drill**
   - Execute full system recovery simulation
   - Time and document recovery process
   - Identify areas for improvement

2. **Backup Strategy Review**
   - Assess backup effectiveness
   - Update procedures based on system changes
   - Review RTO/RPO objectives

### Annual Tasks

1. **Technology Refresh**
   - Evaluate new backup tools and methods
   - Update hardware and software components

2. **Compliance Audit**
   - Review against regulatory requirements
   - Update documentation and procedures

## Communication Templates

### Incident Notification

```
Subject: [INCIDENT] Local AI Services - $SEVERITY_LEVEL Incident Started

Impact: $IMPACT_DESCRIPTION
Status: Investigating
Estimated Resolution: $TIME_ESTIMATE
Updates: Every 30 minutes

Incident Details:
- Started: $START_TIME
- Affected Services: $SERVICE_LIST
- Current Status: $STATUS_DESCRIPTION
```

### Resolution Notification

```
Subject: [RESOLVED] Local AI Services - Incident Resolved

Resolution Summary:
- Duration: $DURATION
- Root Cause: $ROOT_CAUSE
- Resolution: $RESOLUTION_DESCRIPTION
- Preventive Measures: $PREVENTION_ACTIONS

Post-Incident Review:
- Scheduled for: $REVIEW_TIME
- Attendees: DevOps Team
```

## Contact Information

- **Primary On-Call**: DevOps Lead
- **Secondary On-Call**: Systems Administrator
- **Vendor Support**: Docker, Microsoft Support
- **Stakeholder Notification**: Product Manager, Business Leadership

---

*This guide should be reviewed quarterly and updated after any significant system changes or incident responses.*