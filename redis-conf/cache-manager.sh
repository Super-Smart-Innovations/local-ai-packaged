#!/bin/bash
# Redis Cache Management Script

REDIS_CLI="docker exec -it redis redis-cli -a LOCALONLYREDIS"

echo "Redis Cache Management"
echo "======================"

case "$1" in
    status)
        echo "Cache Status:"
        $REDIS_CLI INFO memory
        $REDIS_CLI INFO stats
        ;;
    clear)
        echo "Clearing all cache..."
        $REDIS_CLI FLUSHALL
        echo "Cache cleared."
        ;;
    keys)
        echo "Cache Keys:"
        $REDIS_CLI KEYS "*"
        ;;
    memory)
        echo "Memory Usage:"
        $REDIS_CLI INFO memory | grep -E "(used_memory|used_memory_human|mem_fragmentation_ratio)"
        ;;
    stats)
        echo "Cache Statistics:"
        $REDIS_CLI INFO stats | grep -E "(keyspace_hits|keyspace_misses|evicted_keys)"
        ;;
    *)
        echo "Usage: $0 {status|clear|keys|memory|stats}"
        ;;
esac
