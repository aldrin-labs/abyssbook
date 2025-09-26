#!/bin/bash

# Performance Regression CI Script
# Compares current benchmark results with baseline

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

BASELINE_FILE="benchmark_results/baseline.json"
CURRENT_FILE="benchmark_results/current.json"
TOLERANCE_PERCENT=10

print_header() {
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}   Performance Regression CI Check       ${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo
}

run_current_benchmarks() {
    echo -e "${GREEN}Running current benchmarks...${NC}"
    zig build bench > /dev/null
    
    # Find the latest benchmark result file
    LATEST_RESULT=$(find benchmark_results -name "results_*.json" | sort | tail -1)
    if [ -f "$LATEST_RESULT" ]; then
        cp "$LATEST_RESULT" "$CURRENT_FILE"
        echo "Using benchmark results from: $LATEST_RESULT"
    else
        echo -e "${RED}Error: No benchmark results found${NC}"
        exit 1
    fi
}

check_baseline() {
    if [ ! -f "$BASELINE_FILE" ]; then
        echo -e "${YELLOW}Warning: No baseline file found at $BASELINE_FILE${NC}"
        echo "Creating baseline from current results..."
        cp "$CURRENT_FILE" "$BASELINE_FILE"
        echo -e "${GREEN}Baseline created successfully${NC}"
        return 0
    fi
    return 1
}

compare_results() {
    echo -e "${GREEN}Comparing performance results...${NC}"
    echo
    
    # Use Python for JSON comparison (more reliable than manual parsing)
    cat << 'EOF' > /tmp/compare_benchmarks.py
import json
import sys

def load_results(filename):
    try:
        with open(filename, 'r') as f:
            data = json.load(f)
            return data.get('results', [])
    except Exception as e:
        print(f"Error loading {filename}: {e}")
        return []

def compare_operation(baseline_op, current_op, tolerance):
    name = baseline_op['operation']
    baseline_p99 = baseline_op['latency_p99']
    current_p99 = current_op['latency_p99']
    baseline_throughput = baseline_op['throughput']
    current_throughput = current_op['throughput']
    
    # Calculate percentage changes
    latency_change = 0
    if baseline_p99 > 0:
        latency_change = ((current_p99 - baseline_p99) / baseline_p99) * 100
    
    throughput_change = 0
    if baseline_throughput > 0:
        throughput_change = ((current_throughput - baseline_throughput) / baseline_throughput) * 100
    
    # Check if within tolerance
    latency_regression = latency_change > tolerance
    throughput_regression = throughput_change < -tolerance
    
    status = "PASS"
    if latency_regression or throughput_regression:
        status = "FAIL"
    
    return {
        'name': name,
        'baseline_p99': baseline_p99,
        'current_p99': current_p99,
        'baseline_throughput': baseline_throughput,
        'current_throughput': current_throughput,
        'latency_change': latency_change,
        'throughput_change': throughput_change,
        'status': status,
        'latency_regression': latency_regression,
        'throughput_regression': throughput_regression
    }

def main():
    baseline_file = sys.argv[1]
    current_file = sys.argv[2]
    tolerance = float(sys.argv[3])
    
    baseline_results = load_results(baseline_file)
    current_results = load_results(current_file)
    
    if not baseline_results or not current_results:
        print("Error: Could not load benchmark results")
        sys.exit(1)
    
    # Create lookup for current results
    current_lookup = {op['operation']: op for op in current_results}
    
    comparisons = []
    for baseline_op in baseline_results:
        op_name = baseline_op['operation']
        if op_name in current_lookup:
            comparison = compare_operation(baseline_op, current_lookup[op_name], tolerance)
            comparisons.append(comparison)
    
    # Print results
    print(f"{'Operation':<25} {'Status':<8} {'P99 Change':<12} {'Throughput Change':<16}")
    print("-" * 70)
    
    failed_count = 0
    for comp in comparisons:
        status_color = "🔴" if comp['status'] == 'FAIL' else "🟢"
        print(f"{comp['name']:<25} {status_color + comp['status']:<8} {comp['latency_change']:+.1f}%{'':<7} {comp['throughput_change']:+.1f}%")
        if comp['status'] == 'FAIL':
            failed_count += 1
            print(f"  P99: {comp['baseline_p99']/1000:.2f}µs -> {comp['current_p99']/1000:.2f}µs")
            print(f"  Throughput: {comp['baseline_throughput']:.0f} -> {comp['current_throughput']:.0f} ops/sec")
    
    print()
    print(f"Summary: {len(comparisons) - failed_count} passed, {failed_count} failed")
    
    if failed_count > 0:
        print("❌ Performance regression detected!")
        sys.exit(1)
    else:
        print("✅ All performance checks passed!")
        sys.exit(0)

if __name__ == "__main__":
    main()
EOF

    # Run the comparison
    python3 /tmp/compare_benchmarks.py "$BASELINE_FILE" "$CURRENT_FILE" "$TOLERANCE_PERCENT"
    comparison_result=$?
    
    # Cleanup
    rm -f /tmp/compare_benchmarks.py
    
    return $comparison_result
}

update_baseline() {
    if [ "${CI_UPDATE_BASELINE:-false}" = "true" ]; then
        echo -e "${YELLOW}Updating baseline with current results...${NC}"
        cp "$CURRENT_FILE" "$BASELINE_FILE"
        echo -e "${GREEN}Baseline updated${NC}"
    fi
}

cleanup() {
    if [ -f "$CURRENT_FILE" ]; then
        rm -f "$CURRENT_FILE"
    fi
}

# Main execution
print_header

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python3 is required for benchmark comparison${NC}"
    exit 1
fi

# Ensure benchmark results directory exists
mkdir -p benchmark_results

# Run current benchmarks
run_current_benchmarks

# Check if baseline exists, create if needed
if check_baseline; then
    echo -e "${GREEN}Using existing baseline for comparison${NC}"
    comparison_needed=false
else
    comparison_needed=true
fi

# Compare results if baseline exists
if [ "$comparison_needed" = true ]; then
    if compare_results; then
        echo -e "${GREEN}Performance regression check passed${NC}"
        exit_code=0
    else
        echo -e "${RED}Performance regression detected${NC}"
        exit_code=1
    fi
else
    echo -e "${YELLOW}No comparison performed - baseline was just created${NC}"
    exit_code=0
fi

# Update baseline if requested
update_baseline

# Cleanup temporary files
cleanup

exit $exit_code