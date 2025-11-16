#!/bin/bash

# Phase 7: PostgreSQL Performance Tuning and PgBouncer Configuration
# This script configures PostgreSQL performance tuning and PgBouncer for production workloads

set -e

echo "Configuring PostgreSQL performance tuning and PgBouncer..."

# Create PgBouncer configuration directory
mkdir -p pgbouncer

# Create PgBouncer configuration file
cat > pgbouncer/pgbouncer.ini << 'EOF'
[databases]
* = host=postgres port=5432

[pgbouncer]
listen_port = 6432
listen_addr = *
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
logfile = /var/log/pgbouncer/pgbouncer.log
pidfile = /var/run/pgbouncer/pgbouncer.pid
admin_users = postgres
stats_users = postgres

# Connection pooling settings
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 20
min_pool_size = 5
reserve_pool_size = 5
reserve_pool_timeout = 5
max_db_connections = 100
max_user_connections = 100

# Performance settings
server_reset_query = DISCARD ALL
server_reset_query_always = 1
server_check_delay = 30
server_check_query = select 1
tcp_keepalive = 1
tcp_keepcnt = 5
tcp_keepidle = 7200
tcp_keepintvl = 75

# Timeout settings
server_connect_timeout = 15
server_login_timeout = 15
query_timeout = 0
query_wait_timeout = 120
client_idle_timeout = 0
client_login_timeout = 60
autodb_idle_timeout = 3600
suspend_timeout = 10

# Logging
syslog = 0
syslog_ident = pgbouncer
syslog_facility = daemon
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
verbose = 0
EOF

# Create PgBouncer userlist
cat > pgbouncer/userlist.txt << 'EOF'
"postgres" "md5$(echo -n 'postgres'"$POSTGRES_PASSWORD" | md5sum | cut -d' ' -f1)"
EOF

# Create PostgreSQL configuration overlay
mkdir -p postgres-conf

# Create postgresql.conf custom configuration
cat > postgres-conf/postgresql.conf << 'EOF'
# Performance tuning for 128GB RAM host, 8 CPU cores

# Memory Configuration
shared_buffers = 2GB
effective_cache_size = 6GB
work_mem = 10485kB
maintenance_work_mem = 512MB
wal_buffers = 16MB

# Checkpoint Configuration
checkpoint_completion_target = 0.9
wal_level = replica
max_wal_senders = 3
wal_keep_size = 1GB
min_wal_size = 1GB
max_wal_size = 4GB

# Query Planning
random_page_cost = 1.1
effective_io_concurrency = 200
default_statistics_target = 100

# Connection Configuration
max_connections = 200
superuser_reserved_connections = 3

# Logging Configuration
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_statement = 'ddl'
log_duration = on
log_lock_waits = on
log_temp_files = 0
log_checkpoints = on

# Autovacuum Configuration
autovacuum = on
autovacuum_max_workers = 3
autovacuum_naptime = 20s
autovacuum_vacuum_threshold = 50
autovacuum_analyze_threshold = 50
autovacuum_vacuum_scale_factor = 0.02
autovacuum_analyze_scale_factor = 0.01

# Extension Configuration
shared_preload_libraries = 'pg_stat_statements,pg_buffercache'

# Performance Monitoring
track_activities = on
track_counts = on
track_functions = all
track_io_timing = on

# Background Writer
bgwriter_delay = 200ms
bgwriter_lru_maxpages = 100
bgwriter_lru_multiplier = 2.0

# Asynchronous Behavior
max_worker_processes = 8
max_parallel_workers_per_gather = 4
max_parallel_workers = 8
max_parallel_maintenance_workers = 4
EOF

# Create PgBouncer docker-compose service
cat > docker-compose.pgbouncer.yml << 'EOF'
services:
  pgbouncer:
    image: edoburu/pgbouncer:latest
    container_name: pgbouncer
    restart: unless-stopped
    ports:
      - "6432:6432"
    volumes:
      - ./pgbouncer/pgbouncer.ini:/etc/pgbouncer/pgbouncer.ini:ro
      - ./pgbouncer/userlist.txt:/etc/pgbouncer/userlist.txt:ro
    environment:
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    depends_on:
      postgres:
        condition: service_healthy
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "3"
    healthcheck:
      test: ["CMD", "pg_isready", "-h", "localhost", "-p", "6432", "-U", "postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
EOF

# Create PostgreSQL initialization scripts for performance tuning
cat > db/99-performance-tuning.sql << 'EOF'
-- Performance tuning and monitoring extensions
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pg_buffercache;
CREATE EXTENSION IF NOT EXISTS pg_prewarm;

-- Create performance monitoring views
CREATE OR REPLACE VIEW performance_stats AS
SELECT
    schemaname,
    tablename,
    n_tup_ins,
    n_tup_upd,
    n_tup_del,
    n_live_tup,
    n_dead_tup,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze,
    vacuum_count,
    autovacuum_count,
    analyze_count,
    autoanalyze_count
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;

-- Create index usage statistics view
CREATE OR REPLACE VIEW index_usage_stats AS
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- Grant permissions for monitoring
GRANT pg_read_all_stats TO postgres;
EOF

echo "PostgreSQL performance tuning and PgBouncer configuration completed."
echo ""
echo "Key optimizations applied:"
echo "- PostgreSQL memory settings optimized for 128GB host"
echo "- Connection pooling with PgBouncer (max 1000 clients)"
echo "- WAL and checkpoint tuning for better performance"
echo "- Autovacuum optimized for high-throughput workloads"
echo "- Performance monitoring extensions enabled"
echo "- Query planning optimized for SSD storage"
echo ""
echo "To enable PgBouncer, add the pgbouncer service to your docker-compose.yml:"
echo "include:"
echo "  - ./docker-compose.pgbouncer.yml"
echo ""
echo "Update your database connections to use:"
echo "Host: localhost"
echo "Port: 6432 (instead of 5432)"
echo "Database: your_database_name"