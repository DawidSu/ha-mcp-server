#!/bin/bash
# Unit tests for security utilities

# Load test helper
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_helper.sh"

# Source the module to test
source "$SCRIPT_DIR/../../scripts/security-utils.sh"

# Test suite name
TEST_SUITE="Security Utils"

# =============================================================================
# Test Functions
# =============================================================================

test_validate_config_path() {
    test_section "Config Path Validation"
    
    # Valid paths should pass
    assert_success "validate_config_path '/config'" "Valid absolute path should be accepted"
    assert_success "validate_config_path '/home/user/homeassistant'" "Valid user path should be accepted"
    assert_success "validate_config_path '/usr/share/hassio'" "Valid system path should be accepted"
    
    # Invalid paths should fail
    assert_failure "validate_config_path '../../../etc'" "Directory traversal should be blocked"
    assert_failure "validate_config_path '/config/../../../etc'" "Directory traversal in middle should be blocked"
    assert_failure "validate_config_path 'relative/path'" "Relative path should be blocked"
    assert_failure "validate_config_path '/config with spaces'" "Path with spaces should be blocked"
    assert_failure "validate_config_path '/config;rm -rf /'" "Path with shell injection should be blocked"
    
    # Edge cases
    assert_failure "validate_config_path '$(echo longpath)'" "Command substitution should be blocked"
    assert_failure "validate_config_path ''" "Empty path should be blocked"
    
    # Very long path
    local long_path="/$(printf 'a%.0s' {1..300})"
    assert_failure "validate_config_path '$long_path'" "Very long path should be blocked"
}

test_validate_log_level() {
    test_section "Log Level Validation"
    
    # Valid log levels
    assert_success "validate_log_level 'debug'" "Debug level should be valid"
    assert_success "validate_log_level 'info'" "Info level should be valid"
    assert_success "validate_log_level 'warning'" "Warning level should be valid"
    assert_success "validate_log_level 'error'" "Error level should be valid"
    
    # Case insensitive
    assert_success "validate_log_level 'DEBUG'" "Uppercase debug should be valid"
    assert_success "validate_log_level 'Info'" "Mixed case info should be valid"
    
    # Invalid log levels
    assert_failure "validate_log_level 'verbose'" "Invalid log level should be rejected"
    assert_failure "validate_log_level 'critical'" "Non-standard level should be rejected"
    assert_failure "validate_log_level ''" "Empty log level should be rejected"
    assert_failure "validate_log_level 'info; rm -rf /'" "Injection attempt should be rejected"
}

test_validate_file_extension() {
    test_section "File Extension Validation"
    
    # Valid extensions
    assert_success "validate_file_extension 'config.yaml'" "YAML extension should be valid"
    assert_success "validate_file_extension 'secrets.yml'" "YML extension should be valid"
    assert_success "validate_file_extension 'data.json'" "JSON extension should be valid"
    assert_success "validate_file_extension 'script.py'" "Python extension should be valid"
    assert_success "validate_file_extension 'readme.md'" "Markdown extension should be valid"
    assert_success "validate_file_extension 'notes.txt'" "Text extension should be valid"
    
    # Case insensitive
    assert_success "validate_file_extension 'config.YAML'" "Uppercase extension should be valid"
    assert_success "validate_file_extension 'data.Json'" "Mixed case extension should be valid"
    
    # Invalid extensions
    assert_failure "validate_file_extension 'malware.exe'" "Executable extension should be blocked"
    assert_failure "validate_file_extension 'script.sh'" "Shell script should be blocked"
    assert_failure "validate_file_extension 'file.bin'" "Binary extension should be blocked"
    
    # No extension
    assert_failure "validate_file_extension 'filename'" "File without extension should be blocked"
    assert_failure "validate_file_extension '/path/to/file'" "Path without extension should be blocked"
}

test_validate_file_size() {
    test_section "File Size Validation"
    
    # Create test files
    local small_file="$TEST_DIR/small.txt"
    local large_file="$TEST_DIR/large.txt"
    
    echo "small content" > "$small_file"
    head -c 20971520 /dev/zero > "$large_file" 2>/dev/null || {
        # Fallback for systems without /dev/zero
        dd if=/dev/urandom of="$large_file" bs=1024 count=20480 2>/dev/null || {
            echo "Could not create large file for testing, skipping size tests"
            return
        }
    }
    
    # Valid file sizes
    assert_success "validate_file_size '$small_file'" "Small file should pass"
    assert_success "validate_file_size '$small_file' 1048576" "Small file under custom limit should pass"
    
    # Invalid file sizes
    assert_failure "validate_file_size '$large_file'" "Large file should fail default limit"
    assert_failure "validate_file_size '$large_file' 1024" "Large file should fail small limit"
    
    # Non-existent file should pass (can't check size)
    assert_success "validate_file_size '/nonexistent/file.txt'" "Non-existent file should pass"
    
    # Cleanup
    rm -f "$small_file" "$large_file"
}

test_sanitize_filename() {
    test_section "Filename Sanitization"
    
    # Test sanitization
    local result
    
    result=$(sanitize_filename "normal_file.txt")
    assert_equals "normal_file.txt" "$result" "Normal filename should remain unchanged"
    
    result=$(sanitize_filename "file with spaces.txt")
    assert_equals "file_with_spaces.txt" "$result" "Spaces should be replaced with underscores"
    
    result=$(sanitize_filename "file;with&dangerous*chars.txt")
    assert_equals "file_with_dangerous_chars.txt" "Dangerous characters should be replaced"
    
    result=$(sanitize_filename ".hidden_file.txt")
    assert_equals "hidden_file.txt" "$result" "Leading dots should be removed"
    
    result=$(sanitize_filename "...")
    assert_equals "sanitized_file" "$result" "Only dots should become default name"
    
    # Very long filename
    local long_name="$(printf 'a%.0s' {1..150}).txt"
    result=$(sanitize_filename "$long_name")
    assert_contains "$result" "..." "Very long filename should be truncated"
}

test_check_rate_limit() {
    test_section "Rate Limiting"
    
    # Enable rate limiting for testing
    export RATE_LIMIT_ENABLED="true"
    export RATE_LIMIT_MAX="3"
    export RATE_LIMIT_WINDOW="10"
    
    # Clear any existing rate limit data
    unset REQUEST_COUNTS
    declare -A REQUEST_COUNTS
    
    # First few requests should pass
    assert_success "check_rate_limit 'test_client'" "First request should pass"
    assert_success "check_rate_limit 'test_client'" "Second request should pass"
    assert_success "check_rate_limit 'test_client'" "Third request should pass"
    
    # Rate limit should now be exceeded
    assert_failure "check_rate_limit 'test_client'" "Fourth request should be rate limited"
    
    # Different client should not be affected
    assert_success "check_rate_limit 'other_client'" "Different client should pass"
    
    # Disable rate limiting
    export RATE_LIMIT_ENABLED="false"
    assert_success "check_rate_limit 'test_client'" "Rate limiting disabled should pass"
}

test_check_file_in_allowed_path() {
    test_section "File Path Security Check"
    
    # Valid paths within allowed directory
    assert_success "check_file_in_allowed_path '/config/configuration.yaml' '/config'" "File in allowed path should pass"
    assert_success "check_file_in_allowed_path '/config/subdir/file.yaml' '/config'" "File in subdirectory should pass"
    
    # Invalid paths outside allowed directory
    assert_failure "check_file_in_allowed_path '/etc/passwd' '/config'" "System file should be blocked"
    assert_failure "check_file_in_allowed_path '/home/user/secrets.txt' '/config'" "File outside path should be blocked"
    assert_failure "check_file_in_allowed_path '/config/../etc/passwd' '/config'" "Directory traversal should be blocked"
}

test_check_suspicious_patterns() {
    test_section "Suspicious Pattern Detection"
    
    # Normal files should pass
    assert_success "check_suspicious_patterns '/config/configuration.yaml'" "Normal config file should pass"
    assert_success "check_suspicious_patterns '/config/scripts.yaml'" "Scripts config should pass"
    
    # Suspicious patterns should be blocked
    assert_failure "check_suspicious_patterns '/config/../etc/passwd'" "Directory traversal should be detected"
    assert_failure "check_suspicious_patterns '/config/password.txt'" "Password file should be detected"
    assert_failure "check_suspicious_patterns '/config/secret.key'" "Secret file should be detected"
    assert_failure "check_suspicious_patterns '/home/user/.ssh/id_rsa'" "SSH key should be detected"
    assert_failure "check_suspicious_patterns '/etc/passwd'" "System password file should be detected"
}

test_validate_file_access_comprehensive() {
    test_section "Comprehensive File Access Validation"
    
    # Create test file
    local test_file="$TEST_CONFIG_DIR/test.yaml"
    echo "test: content" > "$test_file"
    
    # Valid file access
    assert_success "validate_file_access '$test_file' '$TEST_CONFIG_DIR'" "Valid file access should pass"
    
    # Invalid extension
    local bad_ext_file="$TEST_CONFIG_DIR/malware.exe"
    touch "$bad_ext_file"
    assert_failure "validate_file_access '$bad_ext_file' '$TEST_CONFIG_DIR'" "Bad extension should be blocked"
    
    # File outside allowed path
    local outside_file="/tmp/outside.yaml"
    echo "test: content" > "$outside_file"
    assert_failure "validate_file_access '$outside_file' '$TEST_CONFIG_DIR'" "File outside path should be blocked"
    
    # Cleanup
    rm -f "$test_file" "$bad_ext_file" "$outside_file"
}

# =============================================================================
# Test Runner
# =============================================================================

run_all_tests() {
    test_start "$TEST_SUITE"
    
    local failed_tests=0
    
    # Setup test environment
    setup_test_env
    
    # Run individual test functions
    test_validate_config_path || ((failed_tests++))
    test_validate_log_level || ((failed_tests++))
    test_validate_file_extension || ((failed_tests++))
    test_validate_file_size || ((failed_tests++))
    test_sanitize_filename || ((failed_tests++))
    test_check_rate_limit || ((failed_tests++))
    test_check_file_in_allowed_path || ((failed_tests++))
    test_check_suspicious_patterns || ((failed_tests++))
    test_validate_file_access_comprehensive || ((failed_tests++))
    
    # Cleanup
    teardown_test_env
    
    # Report results
    if [[ $failed_tests -eq 0 ]]; then
        test_end "$TEST_SUITE" "PASSED"
        echo "All security utility tests passed!"
        exit 0
    else
        test_end "$TEST_SUITE" "FAILED"
        echo "$failed_tests test function(s) failed"
        exit 1
    fi
}

# Run tests
run_all_tests