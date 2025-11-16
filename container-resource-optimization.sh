#!/bin/bash
# Container Resource Optimization Script
# Optimizes resource allocation for services running inside Ubuntu container

CONTAINER_NAME="ubuntu-server"
HOST_TOTAL_MEMORY_GB=128
CONTAINER_MEMORY_GB=96
CONTAINER_CPUS=16

echo "Optimizing resources for nested Ubuntu container architecture"
echo "============================================================="
echo "Host Total Memory: ${HOST_TOTAL_MEMORY_GB}GB"
echo "Container Memory: ${CONTAINER_MEMORY_GB}GB"
echo "Container CPUs: ${CONTAINER_CPUS}"
echo ""

# Calculate optimal service resource allocation within container
OLLAMA_MEMORY_MB=$((CONTAINER_MEMORY_GB * 30 * 1024 / 100))  # 30% of container memory
N8N_MEMORY_MB=$((CONTAINER_MEMORY_GB * 20 * 1024 / 100))     # 20% of container memory
SUPABASE_MEMORY_MB=$((CONTAINER_MEMORY_GB * 15 * 1024 / 100)) # 15% of container memory
OPENWEBUI_MEMORY_MB=$((CONTAINER_MEMORY_GB * 10 * 1024 / 100)) # 10% of container memory
OTHER_MEMORY_MB=$((CONTAINER_MEMORY_GB * 25 * 1024 / 100))   # 25% for other services

OLLAMA_CPUS=$(echo "scale=1; $CONTAINER_CPUS * 40 / 100" | bc)  # 40% of container CPUs
N8N_CPUS=$(echo "scale=1; $CONTAINER_CPUS * 25 / 100" | bc)     # 25% of container CPUs
SUPABASE_CPUS=$(echo "scale=1; $CONTAINER_CPUS * 20 / 100" | bc) # 20% of container CPUs
OTHER_CPUS=$(echo "scale=1; $CONTAINER_CPUS * 15 / 100" | bc)   # 15% for other services

echo "Recommended Resource Allocation within Ubuntu Container:"
echo "======================================================="
echo "Memory Allocation (MB):"
echo "- Ollama: $OLLAMA_MEMORY_MB MB"
echo "- N8N: $N8N_MEMORY_MB MB"
echo "- Supabase/PostgreSQL: $SUPABASE_MEMORY_MB MB"
echo "- OpenWebUI: $OPENWEBUI_MEMORY_MB MB"
echo "- Other services: $OTHER_MEMORY_MB MB"
echo ""
echo "CPU Allocation:"
echo "- Ollama: $OLLAMA_CPUS cores"
echo "- N8N: $N8N_CPUS cores"
echo "- Supabase/PostgreSQL: $SUPABASE_CPUS cores"
echo "- Other services: $OTHER_CPUS cores"
echo ""

# Copy optimized docker-compose.yml to container
echo "Copying optimized docker-compose.yml to Ubuntu container..."
if [ -f "docker-compose.yml" ]; then
    docker cp docker-compose.yml $CONTAINER_NAME:/app/docker-compose.yml
    echo "âœ“ docker-compose.yml copied to container"
else
    echo "âœ— docker-compose.yml not found in current directory"
    exit 1
fi

# Apply resource limits to services inside container
echo ""
echo "Applying resource limits to services inside container..."

# Stop existing services if running
docker exec $CONTAINER_NAME docker compose -f /app/docker-compose.yml down 2>/dev/null || true

# Start services with resource limits
docker exec $CONTAINER_NAME docker compose -f /app/docker-compose.yml up -d

if [ $? -eq 0 ]; then
    echo "âœ“ Services started successfully with optimized resource limits"
else
    echo "âœ— Failed to start services"
    exit 1
fi

echo ""
echo "Container Resource Optimization Complete"
echo "========================================"
echo ""
echo "Monitoring Commands:"
echo "==================="
echo "# Check container resource usage:"
echo "docker stats $CONTAINER_NAME"
echo ""
echo "# Check services inside container:"
echo "docker exec $CONTAINER_NAME docker ps"
echo ""
echo "# Monitor service resource usage:"
echo "docker exec $CONTAINER_NAME docker stats"
echo ""
echo "# Check container logs:"
echo "docker logs $CONTAINER_NAME"
echo ""
echo "# Check service logs:"
echo "docker exec $CONTAINER_NAME docker compose logs -f"
