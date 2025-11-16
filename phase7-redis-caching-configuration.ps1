# Phase 7: Redis Caching Configuration
# This script configures Redis caching strategies for session management and database query caching

Write-Host "Configuring Redis caching for performance optimization..." -ForegroundColor Green

# Create Redis configuration directory
New-Item -ItemType Directory -Path "redis-conf" -Force | Out-Null

# Create optimized Redis configuration
@"
# Redis configuration optimized for production caching
# Memory management
maxmemory 2gb
maxmemory-policy allkeys-lru
maxmemory-samples 5

# Performance optimizations
tcp-keepalive 300
timeout 300
tcp-backlog 511
databases 16

# Persistence (disabled for pure caching, enable if needed)
save ""
appendonly no

# Logging
loglevel notice
logfile ""

# Security
protected-mode yes
bind 0.0.0.0
requirepass LOCALONLYREDIS

# Performance tuning
hz 10
rdbcompression yes
rdbchecksum yes

# Connection settings
maxclients 10000
tcp-keepalive 300

# Memory defragmentation
activedefrag yes
active-defrag-ignore-bytes 100mb
active-defrag-threshold-lower 10
active-defrag-threshold-upper 100
active-defrag-cycle-min 5
active-defrag-cycle-max 75

# Latency monitoring
latency-monitor-threshold 0

# Disable unnecessary features for pure caching
cluster-enabled no
appendonly no
"@ | Out-File -FilePath "redis-conf/redis.conf" -Encoding UTF8

# Create caching strategy configuration for applications
@"
# Redis Caching Strategy Configuration
# This file defines caching strategies for different components

# Session Caching (N8N, OpenWebUI)
SESSION_CACHE_PREFIX = "session:"
SESSION_TTL = 3600  # 1 hour

# Database Query Caching
QUERY_CACHE_PREFIX = "query:"
QUERY_TTL = 300  # 5 minutes

# API Response Caching
API_CACHE_PREFIX = "api:"
API_TTL = 600  # 10 minutes

# User Data Caching
USER_CACHE_PREFIX = "user:"
USER_TTL = 1800  # 30 minutes

# Model Metadata Caching (Ollama)
MODEL_CACHE_PREFIX = "model:"
MODEL_TTL = 3600  # 1 hour

# Vector Search Results Caching (Qdrant)
VECTOR_CACHE_PREFIX = "vector:"
VECTOR_TTL = 1800  # 30 minutes

# CDN-like Caching for Static Assets
STATIC_CACHE_PREFIX = "static:"
STATIC_TTL = 86400  # 24 hours

# Rate Limiting
RATE_LIMIT_PREFIX = "ratelimit:"
RATE_LIMIT_TTL = 60  # 1 minute

# Cache Warming Script
CACHE_WARM_QUERIES = [
    "SELECT COUNT(*) FROM information_schema.tables",
    "SELECT version()",
    "SHOW DATABASES"
]
"@ | Out-File -FilePath "redis-conf/caching-strategy.conf" -Encoding UTF8

# Create cache management scripts
@"
#!/bin/bash
# Redis Cache Management Script

REDIS_CLI="docker exec -it redis redis-cli -a LOCALONLYREDIS"

echo "Redis Cache Management"
echo "======================"

case "`$1" in
    status)
        echo "Cache Status:"
        `$REDIS_CLI` INFO memory
        `$REDIS_CLI` INFO stats
        ;;
    clear)
        echo "Clearing all cache..."
        `$REDIS_CLI` FLUSHALL
        echo "Cache cleared."
        ;;
    keys)
        echo "Cache Keys:"
        `$REDIS_CLI` KEYS "*"
        ;;
    memory)
        echo "Memory Usage:"
        `$REDIS_CLI` INFO memory | grep -E "(used_memory|used_memory_human|mem_fragmentation_ratio)"
        ;;
    stats)
        echo "Cache Statistics:"
        `$REDIS_CLI` INFO stats | grep -E "(keyspace_hits|keyspace_misses|evicted_keys)"
        ;;
    *)
        echo "Usage: `$0` {status|clear|keys|memory|stats}"
        ;;
esac
"@ | Out-File -FilePath "redis-conf/cache-manager.sh" -Encoding UTF8

# Create PostgreSQL query result caching functions
@"
-- PostgreSQL Query Result Caching Functions
-- Requires pg_cron extension for automated cache invalidation

-- Create cache table
CREATE TABLE IF NOT EXISTS query_cache (
    cache_key TEXT PRIMARY KEY,
    query_hash TEXT NOT NULL,
    result_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE,
    access_count INTEGER DEFAULT 0,
    last_accessed TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create index for cache cleanup
CREATE INDEX IF NOT EXISTS idx_query_cache_expires ON query_cache(expires_at);
CREATE INDEX IF NOT EXISTS idx_query_cache_access ON query_cache(last_accessed);

-- Function to get cached query result
CREATE OR REPLACE FUNCTION get_cached_query(cache_key TEXT)
RETURNS JSONB AS
`$$
DECLARE
    result JSONB;
BEGIN
    -- Update access statistics
    UPDATE query_cache
    SET access_count = access_count + 1,
        last_accessed = NOW()
    WHERE cache_key = `$1` AND expires_at > NOW();

    -- Get result
    SELECT result_data INTO result
    FROM query_cache
    WHERE cache_key = `$1` AND expires_at > NOW();

    RETURN result;
END;
`$$ LANGUAGE plpgsql;

-- Function to set cached query result
CREATE OR REPLACE FUNCTION set_cached_query(
    cache_key TEXT,
    query_hash TEXT,
    result JSONB,
    ttl_seconds INTEGER DEFAULT 300
)
RETURNS VOID AS
`$$
BEGIN
    INSERT INTO query_cache (cache_key, query_hash, result_data, expires_at)
    VALUES (`$1`, `$2`, `$3`, NOW() + INTERVAL '1 second' * `$4`)
    ON CONFLICT (cache_key)
    DO UPDATE SET
        result_data = EXCLUDED.result_data,
        expires_at = EXCLUDED.expires_at,
        access_count = 0,
        last_accessed = NOW();
END;
`$$ LANGUAGE plpgsql;

-- Function to cleanup expired cache entries
CREATE OR REPLACE FUNCTION cleanup_expired_cache()
RETURNS INTEGER AS
`$$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM query_cache WHERE expires_at <= NOW();
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
`$$ LANGUAGE plpgsql;

-- Create cache statistics view
CREATE OR REPLACE VIEW cache_statistics AS
SELECT
    COUNT(*) as total_entries,
    COUNT(*) FILTER (WHERE expires_at > NOW()) as active_entries,
    COUNT(*) FILTER (WHERE expires_at <= NOW()) as expired_entries,
    AVG(access_count) as avg_access_count,
    MAX(access_count) as max_access_count,
    MIN(created_at) as oldest_entry,
    MAX(last_accessed) as newest_access
FROM query_cache;
"@ | Out-File -FilePath "db/98-query-caching.sql" -Encoding UTF8

# Create cache warming script
@"
# Redis Cache Warming Script
# Pre-populates cache with frequently accessed data

#!/bin/bash

REDIS_CLI="docker exec -it redis redis-cli -a LOCALONLYREDIS"

echo "Warming Redis cache..."

# Warm session cache with common keys
`$REDIS_CLI` SET session:warmup "initialized" EX 3600

# Warm API cache with common endpoints
`$REDIS_CLI` SET api:health "{""status"":""ok""}" EX 600
`$REDIS_CLI` SET api:version "$(date +%s)" EX 3600

# Warm user cache with system user
`$REDIS_CLI` SET user:system "{""id"":""system"",""role"":""admin""}" EX 1800

echo "Cache warming completed."
echo "Use './redis-conf/cache-manager.sh status' to monitor cache performance."
"@ | Out-File -FilePath "redis-conf/cache-warmup.sh" -Encoding UTF8

Write-Host "Redis caching configuration completed." -ForegroundColor Green
Write-Host ""
Write-Host "Key optimizations applied:" -ForegroundColor Cyan
Write-Host "- Redis memory optimized (2GB with LRU eviction)"
Write-Host "- TCP keepalive and connection pooling configured"
Write-Host "- Active memory defragmentation enabled"
Write-Host "- PostgreSQL query result caching functions created"
Write-Host "- Cache management and warming scripts provided"
Write-Host ""
Write-Host "To enable caching:" -ForegroundColor Yellow
Write-Host "1. Copy redis-conf/redis.conf to your Redis container"
Write-Host "2. Run cache warming: ./redis-conf/cache-warmup.sh"
Write-Host "3. Monitor cache: ./redis-conf/cache-manager.sh status"
Write-Host ""
Write-Host "Available cache prefixes:" -ForegroundColor Yellow
Write-Host "- session: (1h) - User sessions"
Write-Host "- query: (5m) - Database queries"
Write-Host "- api: (10m) - API responses"
Write-Host "- user: (30m) - User data"
Write-Host "- model: (1h) - AI model metadata"
Write-Host "- vector: (30m) - Vector search results"
Write-Host "- static: (24h) - Static assets"