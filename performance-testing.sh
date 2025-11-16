#!/bin/bash
# Automated Performance Testing Script
# Runs regular performance tests and generates reports

TEST_RESULTS_DIR="performance-test-results"
mkdir -p $TEST_RESULTS_DIR

run_performance_test() {
    TEST_NAME="$1"
    TEST_COMMAND="$2"
    EXPECTED_MAX_TIME="$3"

    START_TIME=$(date +%s%N)
    $TEST_COMMAND > /dev/null 2>&1
    END_TIME=$(date +%s%N)

    EXECUTION_TIME=$(echo "scale=2; ($END_TIME - $START_TIME) / 1000000" | bc)

    RESULT="PASS"
    if (( $(echo "$EXECUTION_TIME > $EXPECTED_MAX_TIME" | bc -l) )); then
        RESULT="FAIL"
    fi

    echo "$TEST_NAME: $EXECUTION_TIMEms - $RESULT"
    echo "$(date +'%Y-%m-%d %H:%M:%S'), $TEST_NAME, $EXECUTION_TIME, $RESULT" >> "$TEST_RESULTS_DIR/latest.csv"
}

echo "Running automated performance tests..."
echo "====================================="

# Test container startup time
run_performance_test "Container Startup" "docker run --rm hello-world" 500

# Test database connection
run_performance_test "Database Connection" "docker exec postgres pg_isready -U postgres" 100

# Test Redis connection
run_performance_test "Redis Connection" "docker exec redis redis-cli ping" 50

# Test API endpoints (if services are running)
if curl -s http://localhost:5678/health > /dev/null 2>&1; then
    run_performance_test "N8N Health Check" "curl -s http://localhost:5678/health" 200
fi

if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
    run_performance_test "OpenWebUI Health Check" "curl -s http://localhost:3000/api/health" 200
fi

echo ""
echo "Performance test completed."
echo "Results saved to: $TEST_RESULTS_DIR/latest.csv"

# Generate summary report
TOTAL_TESTS=$(wc -l < $TEST_RESULTS_DIR/latest.csv)
PASSED_TESTS=$(grep "PASS" $TEST_RESULTS_DIR/latest.csv | wc -l)
FAILED_TESTS=$((TOTAL_TESTS - PASSED_TESTS))

echo "Summary: $PASSED_TESTS passed, $FAILED_TESTS failed out of $TOTAL_TESTS tests"

if [ "$FAILED_TESTS" -gt 0 ]; then
    echo "??? Performance regression detected!"
    echo "Check the detailed results for failing tests."
else
    echo "??? All performance tests passed."
fi
