#!/bin/bash
# Resource Limits Validation Script
# Validates that resource limits are properly configured and within safe bounds

echo "Validating Resource Limits Configuration"
echo "========================================"

# Define maximum safe limits (80% of host resources)
MAX_MEMORY_GB=$((128 * 80 / 100))  # 102GB
MAX_CPU_CORES=$((12 * 80 / 100))   # 9.6 cores

echo "Safe limits for this host:"
echo "- Maximum Memory: ${MAX_MEMORY_GB}GB (80% of 128GB)"
echo "- Maximum CPU: ${MAX_CPU_CORES} cores (80% of 12 cores)"
echo ""

ISSUES_FOUND=0

# Check docker-compose.yml resource limits
if [ -f "docker-compose.yml" ]; then
    echo "Checking docker-compose.yml resource limits..."

    # Check for services without resource limits
    UNLIMITED_SERVICES=$(grep -A 10 "^  [a-zA-Z].*:" docker-compose.yml | grep -B 10 -A 20 "image:" | grep "^  [a-zA-Z].*:" | xargs)

    for service in $UNLIMITED_SERVICES; do
        if ! grep -A 20 "^  $service:" docker-compose.yml | grep -q "deploy:"; then
            echo "WARNING: Service '' has no resource limits configured"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    done

    # Check for excessive memory limits
    MEMORY_LIMITS=$(grep -A 10 "memory:" docker-compose.yml | grep "memory:" | grep -o "[0-9]*G" | sed 's/G//')

    for mem in $MEMORY_LIMITS; do
        if [ "$mem" -gt "$MAX_MEMORY_GB" ]; then
            echo "ERROR: Memory limit ${mem}GB exceeds safe limit ${MAX_MEMORY_GB}GB"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    done

    # Check for excessive CPU limits
    CPU_LIMITS=$(grep -A 10 "cpus:" docker-compose.yml | grep "cpus:" | grep -o "cpus: '[0-9]*\.*[0-9]*'" | grep -o "[0-9]*\.*[0-9]*")

    for cpu in $CPU_LIMITS; do
        if (( $(echo "$cpu > $MAX_CPU_CORES" | bc -l) )); then
            echo "ERROR: CPU limit ${cpu} exceeds safe limit ${MAX_CPU_CORES}"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    done
else
    echo "ERROR: docker-compose.yml not found"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

echo ""
if [ "$ISSUES_FOUND" -eq 0 ]; then
    echo "âœ“ All resource limits are properly configured"
else
    echo "âœ— Found ${ISSUES_FOUND} resource limit issues that need attention"
    echo ""
    echo "Recommendations:"
    echo "1. Add resource limits to services without them"
    echo "2. Ensure memory limits don't exceed ${MAX_MEMORY_GB}GB"
    echo "3. Ensure CPU limits don't exceed ${MAX_CPU_CORES} cores"
    echo "4. Use reservations to guarantee minimum resources"
fi
