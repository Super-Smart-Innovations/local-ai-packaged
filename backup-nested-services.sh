#!/bin/bash
# Nested Service Volume Backup Script
# This script creates backups of PostgreSQL, Redis/Valkey, Qdrant, Neo4j, and Ollama volumes

set -euo pipefail

# Configuration
BACKUP_ROOT="${BACKUP_ROOT:-/backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_ROOT}/nested-services-${TIMESTAMP}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
VERIFY_INTEGRITY="${VERIFY_INTEGRITY:-true}"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" | tee -a "${BACKUP_ROOT}/backup_log_${TIMESTAMP}.txt"
}

# Create backup directory
mkdir -p "$BACKUP_DIR"

log "Starting nested services backup to $BACKUP_DIR"

# PostgreSQL Backup (using pg_dump)
backup_postgresql() {
    log "Starting PostgreSQL backup"

    local db_host="localhost"
    local db_port="5432"
    local db_user="postgres"
    local db_name="postgres"
    local backup_file="${BACKUP_DIR}/postgresql_${TIMESTAMP}.sql.gz"

    # Check if PostgreSQL container is running
    if docker ps --format "{{.Names}}" | grep -q "^db$"; then
        log "Using Docker container 'db' for PostgreSQL backup"
        docker exec db pg_dump -U postgres -h localhost postgres | gzip > "$backup_file"
    else
        log "PostgreSQL container not found, attempting direct connection"
        PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump -h "$db_host" -p "$db_port" -U "$db_user" -d "$db_name" | gzip > "$backup_file"
    fi

    if [ -f "$backup_file" ] && [ -s "$backup_file" ]; then
        log "PostgreSQL backup completed: $backup_file"
        if [ "$VERIFY_INTEGRITY" = "true" ]; then
            log "Verifying PostgreSQL backup integrity"
            gzip -t "$backup_file" && log "PostgreSQL backup integrity verified" || log "ERROR: PostgreSQL backup integrity check failed"
        fi
    else
        log "ERROR: PostgreSQL backup failed"
        return 1
    fi
}

# Redis/Valkey Backup
backup_redis() {
    log "Starting Redis/Valkey backup"

    local backup_file="${BACKUP_DIR}/redis_${TIMESTAMP}.rdb.gz"

    # Check for Redis container
    if docker ps --format "{{.Names}}" | grep -q "^redis$"; then
        log "Using Docker container 'redis' for backup"
        docker exec redis redis-cli SAVE
        docker cp redis:/data/dump.rdb "${BACKUP_DIR}/dump.rdb"
        gzip "${BACKUP_DIR}/dump.rdb"
        mv "${BACKUP_DIR}/dump.rdb.gz" "$backup_file"
    else
        log "Redis container not found"
        return 1
    fi

    if [ -f "$backup_file" ]; then
        log "Redis backup completed: $backup_file"
    else
        log "ERROR: Redis backup failed"
    fi
}

# Qdrant Backup
backup_qdrant() {
    log "Starting Qdrant backup"

    local backup_file="${BACKUP_DIR}/qdrant_${TIMESTAMP}.tar.gz"

    if docker ps --format "{{.Names}}" | grep -q "^qdrant$"; then
        log "Creating Qdrant volume snapshot"
        docker run --rm \
            -v qdrant_storage:/source:ro \
            -v "$BACKUP_DIR:/backup" \
            alpine tar czf "/backup/qdrant_${TIMESTAMP}.tar.gz" -C /source .
    fi

    if [ -f "$backup_file" ]; then
        log "Qdrant backup completed: $backup_file"
        if [ "$VERIFY_INTEGRITY" = "true" ]; then
            tar -tzf "$backup_file" >/dev/null && log "Qdrant backup integrity verified" || log "ERROR: Qdrant backup integrity check failed"
        fi
    else
        log "ERROR: Qdrant backup failed"
    fi
}

# Neo4j Backup
backup_neo4j() {
    log "Starting Neo4j backup"

    local backup_file="${BACKUP_DIR}/neo4j_${TIMESTAMP}.tar.gz"

    if docker ps --format "{{.Names}}" | grep -q "^neo4j$"; then
        log "Creating Neo4j data backup"
        docker run --rm \
            -v "$(pwd)/neo4j:/source:ro" \
            -v "$BACKUP_DIR:/backup" \
            alpine tar czf "/backup/neo4j_${TIMESTAMP}.tar.gz" -C /source .
    fi

    if [ -f "$backup_file" ]; then
        log "Neo4j backup completed: $backup_file"
        if [ "$VERIFY_INTEGRITY" = "true" ]; then
            tar -tzf "$backup_file" >/dev/null && log "Neo4j backup integrity verified" || log "ERROR: Neo4j backup integrity check failed"
        fi
    else
        log "ERROR: Neo4j backup failed"
    fi
}

# Ollama Backup
backup_ollama() {
    log "Starting Ollama backup"

    local backup_file="${BACKUP_DIR}/ollama_${TIMESTAMP}.tar.gz"

    if docker volume ls --format "{{.Name}}" | grep -q "^ollama_storage$"; then
        log "Creating Ollama models backup"
        docker run --rm \
            -v ollama_storage:/source:ro \
            -v "$BACKUP_DIR:/backup" \
            alpine tar czf "/backup/ollama_${TIMESTAMP}.tar.gz" -C /source .
    fi

    if [ -f "$backup_file" ]; then
        log "Ollama backup completed: $backup_file"
        if [ "$VERIFY_INTEGRITY" = "true" ]; then
            tar -tzf "$backup_file" >/dev/null && log "Ollama backup integrity verified" || log "ERROR: Ollama backup integrity check failed"
        fi
    else
        log "ERROR: Ollama backup failed"
    fi
}

# Execute backups
backup_postgresql
backup_redis
backup_qdrant
backup_neo4j
backup_ollama

# Cleanup old backups
log "Cleaning up backups older than $RETENTION_DAYS days"
find "$BACKUP_ROOT" -name "nested-services-*" -type d -mtime +"$RETENTION_DAYS" -exec rm -rf {} \;

log "Nested services backup completed successfully"