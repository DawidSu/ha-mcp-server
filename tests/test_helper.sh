#!/bin/bash
# Test helper functions for Home Assistant MCP Server tests
# Provides common testing utilities and setup/teardown functions

# =============================================================================
# Test Configuration
# =============================================================================

# Test environment variables
export TEST_DIR="/tmp/ha-mcp-test-$$"
export TEST_CONFIG_DIR="$TEST_DIR/config"
export TEST_BACKUP_DIR="$TEST_DIR/backups"
export TEST_LOG_DIR="$TEST_DIR/logs"

# Test timeouts
export TEST_TIMEOUT=30
export TEST_RETRY_ATTEMPTS=3
export TEST_RETRY_DELAY=1

# =============================================================================
# Setup and Teardown Functions
# =============================================================================

# Setup test environment
setup_test_env() {
    echo "Setting up test environment..."
    
    # Create test directories
    mkdir -p "$TEST_CONFIG_DIR"
    mkdir -p "$TEST_BACKUP_DIR"
    mkdir -p "$TEST_LOG_DIR"
    
    # Create sample Home Assistant config files
    create_sample_config
    
    # Set test environment variables
    export HA_CONFIG_PATH="$TEST_CONFIG_DIR"
    export BACKUP_DIR="$TEST_BACKUP_DIR"
    export LOG_LEVEL="debug"
    export RATE_LIMIT_ENABLED="false"  # Disable for testing
    
    echo "Test environment ready at: $TEST_DIR"
}

# Cleanup test environment
teardown_test_env() {
    echo "Cleaning up test environment..."
    if [[ -n "$TEST_DIR" && "$TEST_DIR" != "/" ]]; then
        rm -rf "$TEST_DIR"
        echo "Test directory removed: $TEST_DIR"
    fi
}

# Create sample Home Assistant configuration
create_sample_config() {
    # configuration.yaml
    cat > "$TEST_CONFIG_DIR/configuration.yaml" << 'EOF'
# Home Assistant Test Configuration
homeassistant:
  name: Test Home
  unit_system: metric
  time_zone: UTC

# Test entities
sensor:
  - platform: template
    sensors:
      test_sensor:
        value_template: "{{ states('sensor.time') }}"

automation:
  - alias: Test Automation
    trigger:
      platform: time
      at: '12:00:00'
    action:
      service: light.turn_on
      entity_id: light.test_light
EOF

    # secrets.yaml
    cat > "$TEST_CONFIG_DIR/secrets.yaml" << 'EOF'
# Test secrets
test_password: secret123
test_api_key: abc123xyz
EOF

    # groups.yaml
    cat > "$TEST_CONFIG_DIR/groups.yaml" << 'EOF'
living_room:
  name: Living Room
  entities:
    - light.living_room_light
    - switch.living_room_fan
EOF

    # scripts.yaml
    cat > "$TEST_CONFIG_DIR/scripts.yaml" << 'EOF'
test_script:
  alias: Test Script
  sequence:
    - service: light.turn_on
      entity_id: light.test_light
EOF

    # Invalid YAML file for testing
    cat > "$TEST_CONFIG_DIR/invalid.yaml" << 'EOF'
invalid: yaml: content:
  - missing
    proper: indentation
EOF

    # Large file for size testing
    head -c 1048576 /dev/zero > "$TEST_CONFIG_DIR/large_file.txt"  # 1MB file
    
    echo "Sample configuration files created"
}

# =============================================================================
# Test Assertion Functions
# =============================================================================

# Assert that command succeeds
assert_success() {
    local command="$1"
    local message="${2:-Command should succeed}"
    
    if ! eval "$command"; then
        echo "FAIL: $message"
        echo "Command failed: $command"
        return 1
    fi
    echo "PASS: $message"
    return 0
}

# Assert that command fails
assert_failure() {
    local command="$1"
    local message="${2:-Command should fail}"
    
    if eval "$command"; then
        echo "FAIL: $message"
        echo "Command unexpectedly succeeded: $command"
        return 1
    fi
    echo "PASS: $message"
    return 0
}

# Assert that strings are equal
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"
    
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $message"
        echo "Expected: '$expected'"
        echo "Actual: '$actual'"
        return 1
    fi
    echo "PASS: $message"
    return 0
}

# Assert that string contains substring
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"
    
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "FAIL: $message"
        echo "String: '$haystack'"
        echo "Should contain: '$needle'"
        return 1
    fi
    echo "PASS: $message"
    return 0
}

# Assert that file exists
assert_file_exists() {
    local file_path="$1"
    local message="${2:-File should exist}"
    
    if [[ ! -f "$file_path" ]]; then
        echo "FAIL: $message"
        echo "File does not exist: $file_path"
        return 1
    fi
    echo "PASS: $message"
    return 0
}

# Assert that directory exists
assert_dir_exists() {
    local dir_path="$1"
    local message="${2:-Directory should exist}"
    
    if [[ ! -d "$dir_path" ]]; then
        echo "FAIL: $message"
        echo "Directory does not exist: $dir_path"
        return 1
    fi
    echo "PASS: $message"
    return 0
}

# Assert that file contains text
assert_file_contains() {
    local file_path="$1"
    local text="$2"
    local message="${3:-File should contain text}"
    
    if [[ ! -f "$file_path" ]]; then
        echo "FAIL: $message"
        echo "File does not exist: $file_path"
        return 1
    fi
    
    if ! grep -q "$text" "$file_path"; then
        echo "FAIL: $message"
        echo "File: $file_path"
        echo "Should contain: $text"
        return 1
    fi
    echo "PASS: $message"
    return 0
}

# =============================================================================
# Test Utility Functions
# =============================================================================

# Run test with timeout
run_with_timeout() {
    local timeout="${1:-$TEST_TIMEOUT}"
    local command="$2"
    
    timeout "$timeout" bash -c "$command"
}

# Retry command with backoff
retry_command() {
    local attempts="${1:-$TEST_RETRY_ATTEMPTS}"
    local delay="${2:-$TEST_RETRY_DELAY}"
    local command="$3"
    
    for ((i=1; i<=attempts; i++)); do
        if eval "$command"; then
            return 0
        fi
        
        if [[ $i -eq $attempts ]]; then
            echo "Command failed after $attempts attempts: $command"
            return 1
        fi
        
        echo "Attempt $i failed, retrying in ${delay}s..."
        sleep "$delay"
        delay=$((delay * 2))  # exponential backoff
    done
}

# Wait for condition to be true
wait_for_condition() {
    local condition="$1"
    local timeout="${2:-$TEST_TIMEOUT}"
    local message="${3:-Waiting for condition}"
    
    local start_time=$(date +%s)
    
    while true; do
        if eval "$condition"; then
            echo "Condition met: $message"
            return 0
        fi
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -ge $timeout ]]; then
            echo "Timeout waiting for condition: $message"
            return 1
        fi
        
        sleep 1
    done
}

# Mock external commands for testing
mock_command() {
    local command_name="$1"
    local mock_response="$2"
    local mock_exit_code="${3:-0}"
    
    # Create mock script
    local mock_script="$TEST_DIR/mock_$command_name"
    cat > "$mock_script" << EOF
#!/bin/bash
echo "$mock_response"
exit $mock_exit_code
EOF
    chmod +x "$mock_script"
    
    # Add to PATH for this test
    export PATH="$TEST_DIR:$PATH"
    
    echo "Mocked command: $command_name"
}

# Restore original command
restore_command() {
    local command_name="$1"
    local mock_script="$TEST_DIR/mock_$command_name"
    
    if [[ -f "$mock_script" ]]; then
        rm -f "$mock_script"
        echo "Restored command: $command_name"
    fi
}

# =============================================================================
# Test Logging Functions
# =============================================================================

# Log test start
test_start() {
    local test_name="$1"
    echo "===================="
    echo "TEST: $test_name"
    echo "===================="
}

# Log test end
test_end() {
    local test_name="$1"
    local result="$2"
    echo "===================="
    echo "TEST $result: $test_name"
    echo "===================="
    echo ""
}

# Log test section
test_section() {
    local section_name="$1"
    echo "--- $section_name ---"
}

# =============================================================================
# Docker Test Utilities
# =============================================================================

# Start test container
start_test_container() {
    local container_name="test-ha-mcp-server"
    local compose_file="docker-compose.test.yml"
    
    if [[ -f "$compose_file" ]]; then
        docker-compose -f "$compose_file" up -d "$container_name"
        wait_for_condition "docker inspect $container_name --format='{{.State.Running}}' | grep true" 30 "Container to start"
    else
        echo "Warning: Test compose file not found"
        return 1
    fi
}

# Stop test container
stop_test_container() {
    local container_name="test-ha-mcp-server"
    local compose_file="docker-compose.test.yml"
    
    if [[ -f "$compose_file" ]]; then
        docker-compose -f "$compose_file" down
    fi
}

# Get container logs
get_container_logs() {
    local container_name="test-ha-mcp-server"
    docker logs "$container_name" 2>&1
}

# =============================================================================
# Performance Test Utilities
# =============================================================================

# Measure execution time
measure_time() {
    local command="$1"
    local start_time=$(date +%s.%N)
    
    eval "$command"
    local exit_code=$?
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)
    
    echo "Execution time: ${duration}s"
    return $exit_code
}

# Generate load for testing
generate_load() {
    local requests="${1:-100}"
    local concurrency="${2:-10}"
    local endpoint="${3:-http://localhost:3000/health}"
    
    if command -v ab >/dev/null 2>&1; then
        ab -n "$requests" -c "$concurrency" "$endpoint"
    else
        echo "Apache Bench (ab) not available for load testing"
        return 1
    fi
}

# =============================================================================
# Export functions for tests
# =============================================================================

# This file is meant to be sourced by test files
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Export all test functions
    export -f setup_test_env teardown_test_env create_sample_config
    export -f assert_success assert_failure assert_equals assert_contains
    export -f assert_file_exists assert_dir_exists assert_file_contains
    export -f run_with_timeout retry_command wait_for_condition
    export -f mock_command restore_command
    export -f test_start test_end test_section
    export -f start_test_container stop_test_container get_container_logs
    export -f measure_time generate_load
fi

echo "Test helper functions loaded"