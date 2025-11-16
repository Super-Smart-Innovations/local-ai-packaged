# Disaster Recovery Procedures

## Overview

This document outlines comprehensive disaster recovery procedures for the Local AI Services platform. The procedures are designed to minimize downtime and data loss while ensuring system integrity.

## Recovery Time Objectives (RTO) and Recovery Point Objectives (RPO)

- **RTO (Recovery Time Objective)**: 4 hours for complete service restoration
- **RPO (Recovery Point Objective)**: 24 hours maximum data loss
- **Backup Frequency**: Daily configurations/volumes, Weekly nested services
- **Retention**: 30 days rolling retention for all backups

## Emergency Response Checklist

### Immediate Actions (First 30 minutes)

1. **Assess Situation**
   - Determine scope of failure (single service vs. complete system)
   - Check backup integrity and availability
   - Notify stakeholders if outage > 1 hour expected

2. **Stop Damage Propagation**
   - Stop affected services to prevent data corruption
   - Isolate failed components if possible
   - Preserve logs and system state for analysis

3. **Activate Incident Response**
   - Follow communication plan
   - Engage appropriate recovery team members
   - Document all actions taken

## Recovery Scenarios

### Scenario 1: Single Service Failure

**Affected Services**: n8n, Open WebUI, Flowise, SearXNG, Caddy, Neo4j

**Procedure**:

1. **Stop Failed Service**
   ```bash
   docker compose -p localai stop <service_name>
   ```

2. **Restore Service Data**
   ```powershell
   # For Docker volume services
   .\backup-docker-volumes.ps1 -IncludeVolumes "<service_volume>" -Restore
   ```

3. **Restart Service**
   ```bash
   docker compose -p localai up -d <service_name>
   ```

4. **Verify Service Health**
   - Check service logs
   - Test basic functionality
   - Monitor for 30 minutes

### Scenario 2: Database Failure (PostgreSQL/Redis)

**Procedure**:

1. **Stop All Services**
   ```bash
   docker compose -p localai down
   ```

2. **Restore Database Backup**
   ```bash
   # PostgreSQL
   gunzip < postgresql_backup.sql.gz | docker exec -i db psql -U postgres postgres

   # Redis
   docker run --rm -v valkey-data:/data alpine sh -c "rm -rf /data/*"
   docker run --rm -v valkey-data:/data -v /backup:/backup alpine sh -c "cd /data && tar xzf /backup/redis_backup.rdb.gz"
   ```

3. **Restart Services**
   ```bash
   docker compose -p localai up -d
   ```

4. **Verify Data Integrity**
   - Run database health checks
   - Test application connectivity
   - Validate recent transactions

### Scenario 3: Complete System Failure

**Procedure**:

1. **Prepare Recovery Environment**
   - Ensure Docker Desktop is running
   - Verify backup media accessibility
   - Prepare recovery workspace

2. **Restore Configurations**
   ```powershell
   .\backup-configurations.ps1 -Restore -BackupPath "C:\backups\configurations\latest"
   ```

3. **Restore Docker Volumes**
   ```powershell
   .\backup-docker-volumes.ps1 -Restore -BackupPath "C:\backups\docker-volumes\latest"
   ```

4. **Restore Nested Services**
   ```bash
   # PostgreSQL
   gunzip < postgresql_backup.sql.gz | psql -U postgres -h localhost postgres

   # Redis/Valkey, Qdrant, Neo4j, Ollama
   # Use respective restore procedures from backup scripts
   ```

5. **Rebuild and Start Services**
   ```bash
   # Clean and rebuild
   docker system prune -f
   docker compose -p localai build --no-cache

   # Start services
   docker compose -p localai up -d
   ```

6. **Post-Recovery Validation**
   - Run full system health checks
   - Test all service integrations
   - Monitor for 2 hours
   - Perform load testing

## Backup Restoration Procedures

### Docker Volume Restoration

```powershell
# PowerShell restoration function
function Restore-DockerVolume {
    param(
        [string]$VolumeName,
        [string]$BackupFile
    )

    # Stop container using volume
    docker compose -p localai stop

    # Remove existing volume
    docker volume rm $VolumeName

    # Create new volume
    docker volume create $VolumeName

    # Restore data
    docker run --rm -v ${VolumeName}:/dest -v (Split-Path $BackupFile):/backup alpine sh -c "cd /dest && tar xzf /backup/${VolumeName}.tar.gz"

    # Restart services
    docker compose -p localai up -d
}
```

### Configuration Restoration

```powershell
# Restore configuration files
function Restore-Configurations {
    param([string]$BackupPath)

    $configFiles = @(
        "docker-compose.yml",
        "Caddyfile",
        "searxng/settings-base.yml"
    )

    foreach ($file in $configFiles) {
        $sourcePath = Join-Path $BackupPath $file
        if (Test-Path $sourcePath) {
            Copy-Item $sourcePath $file -Force
            Write-Host "Restored: $file"
        }
    }
}
```

### PostgreSQL Database Restoration

```bash
# Restore PostgreSQL database
BACKUP_FILE="/backups/nested-services/postgresql_backup.sql.gz"

# Stop services using database
docker compose -p localai stop n8n langfuse-web langfuse-worker

# Restore database
gunzip < $BACKUP_FILE | docker exec -i db psql -U postgres postgres

# Restart services
docker compose -p localai up -d n8n langfuse-web langfuse-worker
```

## Contingency Plans

### Cold Standby Server Setup

1. **Hardware Requirements**
   - Equivalent Windows Server with Docker Desktop
   - Sufficient storage for backups (2x primary storage)
   - Network connectivity to backup storage

2. **Preparation Steps**
   ```powershell
   # Install prerequisites
   choco install docker-desktop git

   # Clone repository
   git clone <repository-url>
   cd local-ai-services

   # Copy latest backups
   robocopy \\backup-server\backups C:\backups /MIR
   ```

3. **Activation Procedure**
   - Update DNS to point to standby server
   - Restore from latest backups
   - Start services and verify functionality
   - Update monitoring systems

### Geographic Redundancy

1. **Offsite Backup Storage**
   - Cloud storage (AWS S3, Azure Blob, Google Cloud)
   - Encrypted backup transmission
   - Geographic separation (different region)

2. **Cross-Region Failover**
   - DNS-based routing with health checks
   - Automated backup synchronization
   - Documented procedures for region switch

## Testing and Validation Procedures

### Backup Integrity Testing

```powershell
# Test backup restoration (monthly)
.\test-backup-integrity.ps1 -BackupTypes All -ReportPath "C:\reports\backup-test-$(Get-Date -Format 'yyyyMMdd').txt"
```

### Disaster Recovery Drills

**Frequency**: Quarterly
**Scope**: Full system recovery simulation
**Duration**: 4 hours maximum
**Participants**: DevOps team, stakeholders

### Recovery Metrics Tracking

- Track actual vs. target RTO/RPO
- Document lessons learned
- Update procedures based on drill results

## Communication Plan

### Internal Communication

- **Incident Start**: Slack/Teams notification to DevOps channel
- **Status Updates**: Every 30 minutes during active recovery
- **Resolution**: Detailed post-mortem within 24 hours

### External Communication

- **Customer Impact**: Notify if outage > 1 hour
- **Status Page**: Update public status page
- **Resolution Notice**: Communicate when services restored

## Continuous Improvement

### Post-Incident Review

1. **Root Cause Analysis**
   - What failed and why
   - Backup effectiveness
   - Procedure adequacy

2. **Lessons Learned**
   - Update procedures
   - Improve monitoring
   - Enhance automation

3. **Preventive Measures**
   - Implement identified improvements
   - Schedule additional training
   - Review backup strategies

---

*This document should be reviewed and updated quarterly or after any significant system changes.*