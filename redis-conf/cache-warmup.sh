# Redis Cache Warming Script
# Pre-populates cache with frequently accessed data

#!/bin/bash

REDIS_CLI="docker exec -it redis redis-cli -a LOCALONLYREDIS"

echo "Warming Redis cache..."

# Warm session cache with common keys
$REDIS_CLI SET session:warmup "initialized" EX 3600

# Warm API cache with common endpoints
$REDIS_CLI SET api:health "{""status"":""ok""}" EX 600
$REDIS_CLI SET api:version "1762689444" EX 3600

# Warm user cache with system user
$REDIS_CLI SET user:system "{""id"":""system"",""role"":""admin""}" EX 1800

echo "Cache warming completed."
echo "Use './redis-conf/cache-manager.sh status' to monitor cache performance."
