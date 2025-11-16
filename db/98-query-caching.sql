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
$$
DECLARE
    result JSONB;
BEGIN
    -- Update access statistics
    UPDATE query_cache
    SET access_count = access_count + 1,
        last_accessed = NOW()
    WHERE cache_key = $1 AND expires_at > NOW();

    -- Get result
    SELECT result_data INTO result
    FROM query_cache
    WHERE cache_key = $1 AND expires_at > NOW();

    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Function to set cached query result
CREATE OR REPLACE FUNCTION set_cached_query(
    cache_key TEXT,
    query_hash TEXT,
    result JSONB,
    ttl_seconds INTEGER DEFAULT 300
)
RETURNS VOID AS
$$
BEGIN
    INSERT INTO query_cache (cache_key, query_hash, result_data, expires_at)
    VALUES ($1, $2, $3, NOW() + INTERVAL '1 second' * $4)
    ON CONFLICT (cache_key)
    DO UPDATE SET
        result_data = EXCLUDED.result_data,
        expires_at = EXCLUDED.expires_at,
        access_count = 0,
        last_accessed = NOW();
END;
$$ LANGUAGE plpgsql;

-- Function to cleanup expired cache entries
CREATE OR REPLACE FUNCTION cleanup_expired_cache()
RETURNS INTEGER AS
$$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM query_cache WHERE expires_at <= NOW();
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

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
