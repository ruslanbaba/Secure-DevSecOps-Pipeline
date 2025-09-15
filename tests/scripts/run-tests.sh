#!/bin/bash

# Comprehensive Test Runner Script for DevSecOps Pipeline
# This script runs all test suites with proper reporting and notifications

set -euo pipefail

# Configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${TEST_DIR}/test-results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${RESULTS_DIR}/test-run-${TIMESTAMP}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create results directory
mkdir -p "${RESULTS_DIR}"

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Function to display header
print_header() {
    log "${BLUE}======================================${NC}"
    log "${BLUE}   DevSecOps Pipeline Test Suite     ${NC}"
    log "${BLUE}======================================${NC}"
    log "Started at: $(date)"
    log "Test Directory: ${TEST_DIR}"
    log "Results Directory: ${RESULTS_DIR}"
    log ""
}

# Function to run a test suite
run_test_suite() {
    local suite_name="$1"
    local test_command="$2"
    local output_file="${RESULTS_DIR}/${suite_name}-${TIMESTAMP}.json"
    
    log "${BLUE}Running ${suite_name} tests...${NC}"
    
    if eval "${test_command}" > "${output_file}" 2>&1; then
        log "${GREEN}✅ ${suite_name} tests PASSED${NC}"
        return 0
    else
        log "${RED}❌ ${suite_name} tests FAILED${NC}"
        return 1
    fi
}

# Function to generate consolidated report
generate_report() {
    local exit_code="$1"
    local report_file="${RESULTS_DIR}/test-report-${TIMESTAMP}.html"
    
    cat > "${report_file}" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>DevSecOps Pipeline Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f4f4f4; padding: 20px; border-radius: 5px; }
        .success { color: #28a745; }
        .failure { color: #dc3545; }
        .warning { color: #ffc107; }
        .test-suite { margin: 20px 0; padding: 15px; border-left: 4px solid #007bff; }
        .metrics { display: flex; justify-content: space-around; margin: 20px 0; }
        .metric { text-align: center; padding: 10px; background-color: #f8f9fa; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>DevSecOps Pipeline Test Report</h1>
        <p><strong>Generated:</strong> $(date)</p>
        <p><strong>Overall Status:</strong> 
            <span class="$([ $exit_code -eq 0 ] && echo 'success' || echo 'failure')">
                $([ $exit_code -eq 0 ] && echo 'PASSED' || echo 'FAILED')
            </span>
        </p>
    </div>
    
    <div class="metrics">
        <div class="metric">
            <h3>Test Suites</h3>
            <p id="suite-count">0</p>
        </div>
        <div class="metric">
            <h3>Total Tests</h3>
            <p id="test-count">0</p>
        </div>
        <div class="metric">
            <h3>Coverage</h3>
            <p id="coverage">0%</p>
        </div>
        <div class="metric">
            <h3>Duration</h3>
            <p id="duration">0s</p>
        </div>
    </div>
    
    <div class="test-suites">
        <!-- Test suite results will be populated here -->
    </div>
    
    <script>
        // JavaScript to populate metrics from JSON files
        // This would be enhanced with actual data parsing
    </script>
</body>
</html>
EOF
    
    log "${BLUE}Test report generated: ${report_file}${NC}"
}

# Function to send notifications
send_notifications() {
    local exit_code="$1"
    local duration="$2"
    
    # Slack notification (if webhook URL is set)
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        local color="good"
        local status="PASSED"
        
        if [[ $exit_code -ne 0 ]]; then
            color="danger"
            status="FAILED"
        fi
        
        curl -X POST -H 'Content-type: application/json' \
            --data "{
                \"attachments\": [{
                    \"color\": \"${color}\",
                    \"title\": \"DevSecOps Pipeline Test Results\",
                    \"text\": \"Test suite ${status} in ${duration} seconds\",
                    \"fields\": [
                        {\"title\": \"Status\", \"value\": \"${status}\", \"short\": true},
                        {\"title\": \"Duration\", \"value\": \"${duration}s\", \"short\": true},
                        {\"title\": \"Timestamp\", \"value\": \"$(date)\", \"short\": true}
                    ]
                }]
            }" \
            "${SLACK_WEBHOOK_URL}" || true
    fi
    
    # Email notification (if configured)
    if command -v mail >/dev/null 2>&1 && [[ -n "${NOTIFICATION_EMAIL:-}" ]]; then
        local subject="DevSecOps Pipeline Tests ${status}"
        local body="Test suite completed with status: ${status}\nDuration: ${duration} seconds\nTimestamp: $(date)"
        
        echo "${body}" | mail -s "${subject}" "${NOTIFICATION_EMAIL}" || true
    fi
}

# Function to cleanup old test results
cleanup_old_results() {
    log "${YELLOW}Cleaning up old test results (keeping last 10 runs)...${NC}"
    
    # Keep only the 10 most recent test result files
    find "${RESULTS_DIR}" -name "test-run-*.log" -type f -printf '%T@ %p\n' | \
        sort -rn | tail -n +11 | cut -d' ' -f2- | \
        xargs -r rm -f
    
    find "${RESULTS_DIR}" -name "*-${TIMESTAMP%_*}*.json" -type f -printf '%T@ %p\n' | \
        sort -rn | tail -n +11 | cut -d' ' -f2- | \
        xargs -r rm -f
}

# Function to setup test environment
setup_test_environment() {
    log "${YELLOW}Setting up test environment...${NC}"
    
    # Install test dependencies if needed
    if [[ ! -d "${TEST_DIR}/node_modules" ]]; then
        log "Installing test dependencies..."
        cd "${TEST_DIR}"
        npm install
    fi
    
    # Ensure test database is available
    if command -v docker >/dev/null 2>&1; then
        log "Starting test database container..."
        docker-compose -f "${TEST_DIR}/../docker-compose.test.yml" up -d db redis || true
        
        # Wait for database to be ready
        sleep 10
    fi
    
    # Load test environment variables
    if [[ -f "${TEST_DIR}/.env.test" ]]; then
        set -a
        source "${TEST_DIR}/.env.test"
        set +a
    fi
}

# Function to teardown test environment
teardown_test_environment() {
    log "${YELLOW}Tearing down test environment...${NC}"
    
    # Stop test containers
    if command -v docker >/dev/null 2>&1; then
        docker-compose -f "${TEST_DIR}/../docker-compose.test.yml" down || true
    fi
    
    # Clean up test data
    rm -rf "${TEST_DIR}/tmp" || true
}

# Main execution
main() {
    local start_time=$(date +%s)
    local exit_code=0
    
    print_header
    
    # Setup
    setup_test_environment
    
    # Change to test directory
    cd "${TEST_DIR}"
    
    # Run test suites
    log "${BLUE}Starting test execution...${NC}"
    
    # Unit Tests
    if ! run_test_suite "unit" "npm run test:unit -- --json"; then
        exit_code=1
    fi
    
    # Integration Tests
    if ! run_test_suite "integration" "npm run test:integration -- --json"; then
        exit_code=1
    fi
    
    # Security Tests
    if ! run_test_suite "security" "npm run test:security -- --json"; then
        exit_code=1
    fi
    
    # E2E Tests (only if unit and integration pass)
    if [[ $exit_code -eq 0 ]]; then
        if ! run_test_suite "e2e" "npm run test:e2e -- --json"; then
            exit_code=1
        fi
    else
        log "${YELLOW}⚠️  Skipping E2E tests due to previous failures${NC}"
    fi
    
    # Performance Tests (only if all other tests pass)
    if [[ $exit_code -eq 0 ]]; then
        if ! run_test_suite "performance" "npm run test:performance -- --json"; then
            exit_code=1
        fi
    else
        log "${YELLOW}⚠️  Skipping Performance tests due to previous failures${NC}"
    fi
    
    # Generate coverage report
    log "${BLUE}Generating coverage report...${NC}"
    npm run test:coverage || true
    
    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Generate reports
    generate_report $exit_code
    
    # Send notifications
    send_notifications $exit_code $duration
    
    # Cleanup
    cleanup_old_results
    teardown_test_environment
    
    # Final summary
    log ""
    log "${BLUE}======================================${NC}"
    if [[ $exit_code -eq 0 ]]; then
        log "${GREEN}🎉 All tests completed successfully!${NC}"
    else
        log "${RED}💥 Some tests failed. Check the logs for details.${NC}"
    fi
    log "Duration: ${duration} seconds"
    log "Results saved in: ${RESULTS_DIR}"
    log "${BLUE}======================================${NC}"
    
    exit $exit_code
}

# Handle script interruption
trap 'teardown_test_environment; exit 1' INT TERM

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi