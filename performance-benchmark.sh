#!/bin/bash
# Performance Benchmarking Script
# Runs performance tests and generates optimization recommendations

echo "Performance Benchmarking Suite"
echo "==============================="

RESULTS_DIR="benchmark-results"
mkdir -p $RESULTS_DIR

TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
RESULT_FILE="$RESULTS_DIR/benchmark_$TIMESTAMP.txt"

echo "Benchmark Results - $TIMESTAMP" > $RESULT_FILE
echo "=================================" >> $RESULT_FILE

# Docker performance test
echo "Running Docker performance tests..."
echo "Docker Performance:" >> $RESULT_FILE
docker version >> $RESULT_FILE 2>&1
echo "" >> $RESULT_FILE

# Memory bandwidth test (if available)
if command -v sysbench &> /dev/null; then
    echo "Memory Performance:" >> $RESULT_FILE
    sysbench memory --memory-block-size=1K --memory-total-size=100G --memory-access-mode=rnd run >> $RESULT_FILE 2>&1
    echo "" >> $RESULT_FILE
fi

# Disk I/O performance test
echo "Disk I/O Performance:" >> $RESULT_FILE
dd if=/dev/zero of=/tmp/testfile bs=1M count=1000 conv=fdatasync 2>&1 | tail -1 >> $RESULT_FILE
rm -f /tmp/testfile
echo "" >> $RESULT_FILE

# Network performance test (if curl available)
if command -v curl &> /dev/null; then
    echo "Network Performance:" >> $RESULT_FILE
    curl -w "@curl-format.txt" -o /dev/null -s http://httpbin.org/get >> $RESULT_FILE 2>/dev/null || echo "Network test failed" >> $RESULT_FILE
    echo "" >> $RESULT_FILE
fi

# Container startup time test
echo "Container Startup Performance:" >> $RESULT_FILE
START_TIME=$(date +%s%N)
docker run --rm hello-world > /dev/null 2>&1
END_TIME=$(date +%s%N)
STARTUP_TIME=$(echo "scale=2; ($END_TIME - $START_TIME) / 1000000" | bc)
echo "Container startup time: $STARTUP_TIME ms" >> $RESULT_FILE
echo "" >> $RESULT_FILE

# Generate recommendations
echo "Performance Recommendations:" >> $RESULT_FILE
echo "1. If disk I/O is slow (< 500 MB/s), consider using SSD storage" >> $RESULT_FILE
echo "2. If memory bandwidth is low (< 10 GB/s), check RAM configuration" >> $RESULT_FILE
echo "3. If container startup > 500ms, optimize Docker storage driver" >> $RESULT_FILE
echo "4. Monitor network latency for API performance" >> $RESULT_FILE

echo "Benchmark completed. Results saved to: $RESULT_FILE"
echo "Review recommendations in the results file."
