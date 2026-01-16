#!/bin/bash

# Configuration validation script for Home Assistant
# Validates YAML syntax and HA configuration before Claude makes changes

set -e

# Configuration
HA_CONFIG_PATH=${HA_CONFIG_PATH:-/config}
STRICT_MODE=${STRICT_MODE:-false}

# Source logger if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/logger.sh" ]; then
    source "$SCRIPT_DIR/logger.sh"
else
    # Fallback logging
    log_info() { echo "[INFO] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
    log_warning() { echo "[WARNING] $1"; }
    log_debug() { echo "[DEBUG] $1"; }
    log_audit() { echo "[AUDIT] $1"; }
fi

# Track validation results
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0

# Function to check if required tools are installed
check_dependencies() {
    local missing_deps=()
    
    # Check for Python
    if ! command -v python3 &> /dev/null; then
        missing_deps+=("python3")
    fi
    
    # Check for yamllint
    if ! command -v yamllint &> /dev/null; then
        log_warning "yamllint not found, trying to install..."
        if command -v pip3 &> /dev/null; then
            pip3 install yamllint --quiet 2>/dev/null || missing_deps+=("yamllint")
        else
            missing_deps+=("yamllint")
        fi
    fi
    
    # Check for jq (for JSON validation)
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Install with: apt-get install ${missing_deps[*]} OR pip3 install yamllint"
        return 1
    fi
    
    return 0
}

# Function to validate YAML syntax
validate_yaml_syntax() {
    local file=$1
    local errors=""
    
    log_debug "Validating YAML syntax: $file"
    
    # First, try Python YAML parser
    if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
        log_debug "✓ Valid YAML syntax (Python check)"
    else
        errors=$(python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>&1)
        log_error "✗ Invalid YAML syntax in $file"
        log_error "$errors"
        ((VALIDATION_ERRORS++))
        return 1
    fi
    
    # Then use yamllint for style issues
    if command -v yamllint &> /dev/null; then
        # Create yamllint config
        local yamllint_config="/tmp/yamllint.conf"
        cat > "$yamllint_config" <<EOF
extends: relaxed
rules:
  line-length:
    max: 200
  comments:
    min-spaces-from-content: 1
  indentation:
    spaces: 2
EOF
        
        local lint_output
        if lint_output=$(yamllint -c "$yamllint_config" "$file" 2>&1); then
            log_debug "✓ No style issues (yamllint)"
        else
            if [ "$STRICT_MODE" = "true" ]; then
                log_error "Style issues in $file:"
                echo "$lint_output"
                ((VALIDATION_WARNINGS++))
            else
                log_debug "Style issues found (non-strict mode): $file"
            fi
        fi
        rm -f "$yamllint_config"
    fi
    
    return 0
}

# Function to validate Home Assistant specific configuration
validate_ha_config() {
    local config_file="$HA_CONFIG_PATH/configuration.yaml"
    
    log_info "Validating Home Assistant configuration..."
    
    if [ ! -f "$config_file" ]; then
        log_warning "configuration.yaml not found at $config_file"
        return 1
    fi
    
    # Validate main configuration file
    validate_yaml_syntax "$config_file"
    
    # Check for required HA keys
    log_debug "Checking for required Home Assistant keys..."
    
    if python3 <<EOF
import yaml
with open('$config_file', 'r') as f:
    config = yaml.safe_load(f)
    
    # Check for homeassistant key (optional but recommended)
    if 'homeassistant' not in config:
        print("WARNING: 'homeassistant' key not found in configuration")
    
    # Check for problematic configurations
    if 'default_config' not in config and not any(k in config for k in ['frontend', 'api', 'http']):
        print("WARNING: Neither default_config nor essential components configured")
    
    # Check for secrets usage
    if 'secrets.yaml' in str(config):
        print("INFO: Configuration uses secrets.yaml")
EOF
    then
        log_debug "Basic HA structure validation passed"
    else
        log_warning "Issues found in HA configuration structure"
        ((VALIDATION_WARNINGS++))
    fi
}

# Function to validate automations
validate_automations() {
    local automation_file="$HA_CONFIG_PATH/automations.yaml"
    
    if [ -f "$automation_file" ]; then
        log_info "Validating automations..."
        
        if validate_yaml_syntax "$automation_file"; then
            # Check automation structure
            python3 <<EOF 2>/dev/null || log_warning "Could not validate automation structure"
import yaml
with open('$automation_file', 'r') as f:
    automations = yaml.safe_load(f) or []
    
    if not isinstance(automations, list):
        print("ERROR: automations.yaml should contain a list")
        exit(1)
    
    for i, automation in enumerate(automations):
        if not isinstance(automation, dict):
            print(f"ERROR: Automation {i} is not a dictionary")
            continue
            
        # Check required fields
        if 'trigger' not in automation:
            print(f"WARNING: Automation {i} missing 'trigger'")
        if 'action' not in automation:
            print(f"WARNING: Automation {i} missing 'action'")
        
        # Check for ID (recommended)
        if 'id' not in automation and 'alias' in automation:
            print(f"INFO: Automation '{automation.get('alias')}' has no ID")
            
print(f"Validated {len(automations)} automations")
EOF
        fi
    else
        log_debug "No automations.yaml file found"
    fi
}

# Function to validate scripts
validate_scripts() {
    local scripts_file="$HA_CONFIG_PATH/scripts.yaml"
    
    if [ -f "$scripts_file" ]; then
        log_info "Validating scripts..."
        
        if validate_yaml_syntax "$scripts_file"; then
            # Check script structure
            python3 <<EOF 2>/dev/null || log_warning "Could not validate script structure"
import yaml
with open('$scripts_file', 'r') as f:
    scripts = yaml.safe_load(f) or {}
    
    if not isinstance(scripts, dict):
        print("ERROR: scripts.yaml should contain a dictionary")
        exit(1)
    
    for script_name, script_config in scripts.items():
        if not isinstance(script_config, dict):
            print(f"ERROR: Script '{script_name}' configuration is not a dictionary")
            continue
            
        # Check for sequence or single action
        if 'sequence' not in script_config and not any(k in script_config for k in ['service', 'delay', 'wait_template']):
            print(f"WARNING: Script '{script_name}' has no sequence or action defined")
            
print(f"Validated {len(scripts)} scripts")
EOF
        fi
    else
        log_debug "No scripts.yaml file found"
    fi
}

# Function to validate scenes
validate_scenes() {
    local scenes_file="$HA_CONFIG_PATH/scenes.yaml"
    
    if [ -f "$scenes_file" ]; then
        log_info "Validating scenes..."
        
        if validate_yaml_syntax "$scenes_file"; then
            # Check scene structure
            python3 <<EOF 2>/dev/null || log_warning "Could not validate scene structure"
import yaml
with open('$scenes_file', 'r') as f:
    scenes = yaml.safe_load(f) or []
    
    if not isinstance(scenes, list):
        print("ERROR: scenes.yaml should contain a list")
        exit(1)
    
    for i, scene in enumerate(scenes):
        if not isinstance(scene, dict):
            print(f"ERROR: Scene {i} is not a dictionary")
            continue
            
        # Check required fields
        if 'name' not in scene:
            print(f"WARNING: Scene {i} missing 'name'")
        if 'entities' not in scene:
            print(f"WARNING: Scene {i} missing 'entities'")
            
print(f"Validated {len(scenes)} scenes")
EOF
        fi
    else
        log_debug "No scenes.yaml file found"
    fi
}

# Function to validate Lovelace dashboards
validate_lovelace() {
    local lovelace_dir="$HA_CONFIG_PATH/.storage"
    local lovelace_file="$lovelace_dir/lovelace"
    
    if [ -f "$lovelace_file" ]; then
        log_info "Validating Lovelace dashboard configuration..."
        
        # Validate JSON structure
        if jq empty "$lovelace_file" 2>/dev/null; then
            log_debug "✓ Valid JSON structure in Lovelace config"
            
            # Check basic structure
            local version=$(jq -r '.version' "$lovelace_file" 2>/dev/null)
            local views=$(jq -r '.data.config.views | length' "$lovelace_file" 2>/dev/null)
            
            if [ ! -z "$version" ] && [ ! -z "$views" ]; then
                log_info "Lovelace config version: $version, Views: $views"
            fi
        else
            log_error "✗ Invalid JSON in Lovelace configuration"
            ((VALIDATION_ERRORS++))
        fi
    else
        log_debug "No Lovelace configuration found"
    fi
    
    # Check for YAML mode dashboards
    local yaml_dashboards="$HA_CONFIG_PATH/ui-lovelace.yaml"
    if [ -f "$yaml_dashboards" ]; then
        log_info "Found YAML mode dashboard"
        validate_yaml_syntax "$yaml_dashboards"
    fi
}

# Function to check for common issues
check_common_issues() {
    log_info "Checking for common configuration issues..."
    
    # Check for secrets file if referenced
    if grep -q "!secret" "$HA_CONFIG_PATH"/*.yaml 2>/dev/null; then
        if [ ! -f "$HA_CONFIG_PATH/secrets.yaml" ]; then
            log_error "Configuration uses !secret but secrets.yaml not found"
            ((VALIDATION_ERRORS++))
        else
            log_debug "✓ secrets.yaml found"
            validate_yaml_syntax "$HA_CONFIG_PATH/secrets.yaml"
        fi
    fi
    
    # Check for include directories
    for dir in "packages" "automations" "scripts" "scenes"; do
        if grep -q "!include_dir" "$HA_CONFIG_PATH/configuration.yaml" 2>/dev/null | grep -q "$dir"; then
            if [ ! -d "$HA_CONFIG_PATH/$dir" ]; then
                log_warning "Configuration references directory '$dir' but it doesn't exist"
                ((VALIDATION_WARNINGS++))
            fi
        fi
    done
    
    # Check file permissions
    local permission_issues=0
    while IFS= read -r -d '' file; do
        if [ ! -r "$file" ]; then
            log_warning "File not readable: $file"
            ((permission_issues++))
        fi
    done < <(find "$HA_CONFIG_PATH" -name "*.yaml" -print0 2>/dev/null)
    
    if [ "$permission_issues" -gt 0 ]; then
        log_warning "Found $permission_issues files with permission issues"
        ((VALIDATION_WARNINGS++))
    fi
    
    # Check for duplicate keys (common error)
    for yaml_file in "$HA_CONFIG_PATH"/*.yaml; do
        if [ -f "$yaml_file" ]; then
            if python3 -c "
import yaml
from collections import Counter

class DuplicateKeyCheck(yaml.SafeLoader):
    def construct_mapping(self, node):
        keys = [self.construct_object(k) for k, v in node.value]
        duplicates = [k for k, count in Counter(keys).items() if count > 1]
        if duplicates:
            print(f'Duplicate keys found: {duplicates}')
            exit(1)
        return super().construct_mapping(node)

try:
    with open('$yaml_file', 'r') as f:
        yaml.load(f, Loader=DuplicateKeyCheck)
except Exception as e:
    print(f'Error checking $yaml_file: {e}')
    exit(1)
" 2>/dev/null; then
                log_debug "✓ No duplicate keys in $(basename "$yaml_file")"
            else
                log_error "Duplicate keys found in $(basename "$yaml_file")"
                ((VALIDATION_ERRORS++))
            fi
        fi
    done
}

# Function to generate validation report
generate_report() {
    local report_file="/tmp/validation_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Home Assistant Configuration Validation Report"
        echo "=============================================="
        echo "Date: $(date)"
        echo "Config Path: $HA_CONFIG_PATH"
        echo ""
        echo "Summary:"
        echo "  Errors: $VALIDATION_ERRORS"
        echo "  Warnings: $VALIDATION_WARNINGS"
        echo ""
        
        if [ "$VALIDATION_ERRORS" -eq 0 ] && [ "$VALIDATION_WARNINGS" -eq 0 ]; then
            echo "✓ Configuration is valid!"
        elif [ "$VALIDATION_ERRORS" -eq 0 ]; then
            echo "⚠ Configuration has warnings but no critical errors"
        else
            echo "✗ Configuration has errors that must be fixed"
        fi
        
        echo ""
        echo "Files checked:"
        find "$HA_CONFIG_PATH" -name "*.yaml" -type f | while read -r file; do
            echo "  - $(basename "$file")"
        done
    } > "$report_file"
    
    log_info "Validation report saved to: $report_file"
    cat "$report_file"
    
    # Log audit event
    log_audit "config_validation" "system" "$HA_CONFIG_PATH" \
        "$([ "$VALIDATION_ERRORS" -eq 0 ] && echo "success" || echo "failed")"
}

# Main validation function
main() {
    log_info "Starting Home Assistant configuration validation"
    log_info "Config path: $HA_CONFIG_PATH"
    log_info "Strict mode: $STRICT_MODE"
    
    # Check dependencies
    if ! check_dependencies; then
        log_error "Missing required dependencies"
        exit 1
    fi
    
    # Run all validations
    validate_ha_config
    validate_automations
    validate_scripts
    validate_scenes
    validate_lovelace
    check_common_issues
    
    # Generate report
    generate_report
    
    # Exit with appropriate code
    if [ "$VALIDATION_ERRORS" -gt 0 ]; then
        log_error "Validation failed with $VALIDATION_ERRORS errors"
        exit 1
    elif [ "$VALIDATION_WARNINGS" -gt 0 ]; then
        log_warning "Validation completed with $VALIDATION_WARNINGS warnings"
        exit 0
    else
        log_info "Validation completed successfully!"
        exit 0
    fi
}

# Handle command line arguments
case "${1:-validate}" in
    validate)
        main
        ;;
    check)
        # Quick check mode - only critical errors
        STRICT_MODE=false
        main
        ;;
    strict)
        # Strict mode - all warnings are errors
        STRICT_MODE=true
        main
        ;;
    *)
        echo "Usage: $0 {validate|check|strict}"
        echo ""
        echo "Modes:"
        echo "  validate - Standard validation (default)"
        echo "  check    - Quick check, only critical errors"  
        echo "  strict   - Strict validation, warnings as errors"
        exit 1
        ;;
esac