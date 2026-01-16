#!/bin/bash
# Test runner for Home Assistant MCP Server
# Orchestrates unit, integration, and end-to-end tests

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source test helper
source "$SCRIPT_DIR/test_helper.sh"

# Test configuration
declare -g TOTAL_TESTS=0
declare -g PASSED_TESTS=0
declare -g FAILED_TESTS=0
declare -g SKIPPED_TESTS=0

# Test options
RUN_UNIT_TESTS=true
RUN_INTEGRATION_TESTS=true
RUN_E2E_TESTS=true
VERBOSE=false
STOP_ON_FAILURE=false

# =============================================================================
# Test Runner Functions
# =============================================================================

# Print usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Run tests for Home Assistant MCP Server

Options:
  -u, --unit-only         Run only unit tests
  -i, --integration-only  Run only integration tests
  -e, --e2e-only         Run only end-to-end tests
  -v, --verbose          Enable verbose output
  -s, --stop-on-failure  Stop on first failure
  -h, --help             Show this help message

Examples:
  $0                     # Run all tests
  $0 -u                  # Run only unit tests
  $0 -v -s               # Verbose mode, stop on failure
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--unit-only)
                RUN_UNIT_TESTS=true
                RUN_INTEGRATION_TESTS=false
                RUN_E2E_TESTS=false
                shift
                ;;
            -i|--integration-only)
                RUN_UNIT_TESTS=false
                RUN_INTEGRATION_TESTS=true
                RUN_E2E_TESTS=false
                shift
                ;;
            -e|--e2e-only)
                RUN_UNIT_TESTS=false
                RUN_INTEGRATION_TESTS=false
                RUN_E2E_TESTS=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -s|--stop-on-failure)
                STOP_ON_FAILURE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Log test result
log_test_result() {
    local test_name="$1"
    local result="$2"
    local details="${3:-}"
    
    ((TOTAL_TESTS++))
    
    case "$result" in
        "PASS")
            ((PASSED_TESTS++))
            echo "✓ PASS: $test_name"
            ;;
        "FAIL")
            ((FAILED_TESTS++))
            echo "✗ FAIL: $test_name"
            if [[ -n "$details" ]]; then
                echo "  Error: $details"
            fi
            if [[ "$STOP_ON_FAILURE" == "true" ]]; then
                echo "Stopping on failure as requested"
                exit 1
            fi
            ;;
        "SKIP")
            ((SKIPPED_TESTS++))
            echo "⊘ SKIP: $test_name"
            if [[ -n "$details" ]]; then
                echo "  Reason: $details"
            fi
            ;;
    esac
}

# Run a single test script
run_test_script() {
    local test_script="$1"
    local test_name=$(basename "$test_script" .sh)
    
    echo "Running test: $test_name"
    
    # Check if test script exists and is executable
    if [[ ! -f "$test_script" ]]; then
        log_test_result "$test_name" "SKIP" "Test script not found"
        return
    fi
    
    if [[ ! -x "$test_script" ]]; then
        chmod +x "$test_script"
    fi
    
    # Run test with timeout
    local start_time=$(date +%s)
    local test_output=""
    local exit_code=0
    
    if test_output=$(timeout 300 "$test_script" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Log result
    if [[ $exit_code -eq 0 ]]; then
        log_test_result "$test_name" "PASS" "(${duration}s)"
    else
        log_test_result "$test_name" "FAIL" "Exit code $exit_code after ${duration}s"
    fi
    
    # Show output if verbose or if test failed
    if [[ "$VERBOSE" == "true" || $exit_code -ne 0 ]]; then
        echo "--- Test Output ---"
        echo "$test_output"
        echo "--- End Output ---"
    fi
}

# Run unit tests
run_unit_tests() {
    echo "=========================================="
    echo "Running Unit Tests"
    echo "=========================================="
    
    local unit_test_dir="$SCRIPT_DIR/unit"
    
    if [[ ! -d "$unit_test_dir" ]]; then
        echo "Unit test directory not found: $unit_test_dir"
        return
    fi
    
    # Find all test files
    local test_files
    mapfile -t test_files < <(find "$unit_test_dir" -name "*.sh" -type f | sort)
    
    if [[ ${#test_files[@]} -eq 0 ]]; then
        echo "No unit test files found"
        return
    fi
    
    for test_file in "${test_files[@]}"; do
        run_test_script "$test_file"
    done
}

# Run integration tests
run_integration_tests() {
    echo "=========================================="
    echo "Running Integration Tests"
    echo "=========================================="
    
    local integration_test_dir="$SCRIPT_DIR/integration"
    
    if [[ ! -d "$integration_test_dir" ]]; then
        echo "Integration test directory not found: $integration_test_dir"
        return
    fi
    
    # Setup integration test environment
    echo "Setting up integration test environment..."
    setup_test_env
    
    # Find all test files
    local test_files
    mapfile -t test_files < <(find "$integration_test_dir" -name "*.sh" -type f | sort)
    
    if [[ ${#test_files[@]} -eq 0 ]]; then
        echo "No integration test files found"
        teardown_test_env
        return
    fi
    
    for test_file in "${test_files[@]}"; do
        run_test_script "$test_file"
    done
    
    # Cleanup
    teardown_test_env
}

# Run end-to-end tests
run_e2e_tests() {
    echo "=========================================="
    echo "Running End-to-End Tests"
    echo "=========================================="
    
    local e2e_test_dir="$SCRIPT_DIR/e2e"
    
    if [[ ! -d "$e2e_test_dir" ]]; then
        echo "E2E test directory not found: $e2e_test_dir"
        return
    fi
    
    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        echo "Docker not available, skipping E2E tests"
        return
    fi
    
    # Find all test files
    local test_files
    mapfile -t test_files < <(find "$e2e_test_dir" -name "*.sh" -type f | sort)
    
    if [[ ${#test_files[@]} -eq 0 ]]; then
        echo "No E2E test files found"
        return
    fi
    
    for test_file in "${test_files[@]}"; do
        run_test_script "$test_file"
    done
}

# Check test prerequisites
check_prerequisites() {
    echo "Checking test prerequisites..."
    
    local missing_deps=()
    
    # Check for required commands
    local required_commands=("bash" "timeout" "bc")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Check for optional commands
    local optional_commands=("docker" "docker-compose" "curl")
    for cmd in "${optional_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "Warning: $cmd not found (some tests may be skipped)"
        fi
    done
    
    # Report missing dependencies
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "Error: Missing required dependencies: ${missing_deps[*]}"
        echo "Please install the missing dependencies and try again"
        exit 1
    fi
    
    echo "Prerequisites check passed"
}

# Generate test report
generate_report() {
    echo ""
    echo "=========================================="
    echo "Test Results Summary"
    echo "=========================================="
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed:      $PASSED_TESTS"
    echo "Failed:      $FAILED_TESTS"
    echo "Skipped:     $SKIPPED_TESTS"
    echo ""
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo "🎉 All tests passed!"
        return 0
    else
        echo "❌ Some tests failed"
        return 1
    fi
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    echo "Home Assistant MCP Server Test Runner"
    echo "====================================="
    
    # Parse arguments
    parse_args "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Record start time
    local start_time=$(date +%s)
    
    # Run tests based on options
    if [[ "$RUN_UNIT_TESTS" == "true" ]]; then
        run_unit_tests
    fi
    
    if [[ "$RUN_INTEGRATION_TESTS" == "true" ]]; then
        run_integration_tests
    fi
    
    if [[ "$RUN_E2E_TESTS" == "true" ]]; then
        run_e2e_tests
    fi
    
    # Calculate total time
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    
    echo ""
    echo "Total execution time: ${total_time}s"
    
    # Generate report and exit with appropriate code
    if generate_report; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"