#!/bin/bash

# Checkmarx SAST Integration Script
# Enterprise-grade security scanning with comprehensive reporting

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../configs/checkmarx-config.yaml"
RESULTS_DIR="${SCRIPT_DIR}/../../reports/sast"

# Create results directory
mkdir -p "${RESULTS_DIR}"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Validate environment variables
validate_environment() {
    log "Validating Checkmarx environment configuration..."
    
    local required_vars=(
        "CHECKMARX_URL"
        "CHECKMARX_USERNAME" 
        "CHECKMARX_PASSWORD"
        "CI_PROJECT_NAME"
        "CI_COMMIT_SHA"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error_exit "Required environment variable ${var} is not set"
        fi
    done
    
    log "✅ Environment validation completed"
}

# Authenticate with Checkmarx
authenticate_checkmarx() {
    log "Authenticating with Checkmarx server..."
    
    # Get authentication token
    local auth_response
    auth_response=$(curl -s -X POST \
        "${CHECKMARX_URL}/cxrestapi/auth/identity/connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${CHECKMARX_USERNAME}&password=${CHECKMARX_PASSWORD}&grant_type=password&scope=sast_rest_api&client_id=resource_owner_client&client_secret=014DF517-39D1-4453-B7B3-9930C563627C" \
        -w "%{http_code}")
    
    local http_code="${auth_response: -3}"
    local response_body="${auth_response%???}"
    
    if [[ "${http_code}" != "200" ]]; then
        error_exit "Authentication failed with HTTP code: ${http_code}"
    fi
    
    # Extract access token
    export CHECKMARX_TOKEN
    CHECKMARX_TOKEN=$(echo "${response_body}" | jq -r '.access_token')
    
    if [[ "${CHECKMARX_TOKEN}" == "null" || -z "${CHECKMARX_TOKEN}" ]]; then
        error_exit "Failed to extract access token from response"
    fi
    
    log "✅ Successfully authenticated with Checkmarx"
}

# Get or create project
get_or_create_project() {
    log "Getting or creating Checkmarx project..."
    
    local project_name="${CI_PROJECT_NAME}"
    local team_id="1"  # Default team ID, should be configured per organization
    
    # Check if project exists
    local projects_response
    projects_response=$(curl -s -X GET \
        "${CHECKMARX_URL}/cxrestapi/projects" \
        -H "Authorization: Bearer ${CHECKMARX_TOKEN}" \
        -H "Accept: application/json" \
        -w "%{http_code}")
    
    local http_code="${projects_response: -3}"
    local response_body="${projects_response%???}"
    
    if [[ "${http_code}" != "200" ]]; then
        error_exit "Failed to get projects list with HTTP code: ${http_code}"
    fi
    
    # Extract project ID if exists
    export CHECKMARX_PROJECT_ID
    CHECKMARX_PROJECT_ID=$(echo "${response_body}" | jq -r --arg name "${project_name}" '.[] | select(.name == $name) | .id')
    
    if [[ "${CHECKMARX_PROJECT_ID}" == "null" || -z "${CHECKMARX_PROJECT_ID}" ]]; then
        log "Project does not exist, creating new project..."
        
        # Create new project
        local create_response
        create_response=$(curl -s -X POST \
            "${CHECKMARX_URL}/cxrestapi/projects" \
            -H "Authorization: Bearer ${CHECKMARX_TOKEN}" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -d "{
                \"name\": \"${project_name}\",
                \"owningTeam\": ${team_id},
                \"isPublic\": false
            }" \
            -w "%{http_code}")
        
        local create_http_code="${create_response: -3}"
        local create_response_body="${create_response%???}"
        
        if [[ "${create_http_code}" != "201" ]]; then
            error_exit "Failed to create project with HTTP code: ${create_http_code}"
        fi
        
        CHECKMARX_PROJECT_ID=$(echo "${create_response_body}" | jq -r '.id')
        log "✅ Created new project with ID: ${CHECKMARX_PROJECT_ID}"
    else
        log "✅ Found existing project with ID: ${CHECKMARX_PROJECT_ID}"
    fi
}

# Upload source code
upload_source_code() {
    log "Uploading source code for scanning..."
    
    local zip_file="${RESULTS_DIR}/source-code-${CI_COMMIT_SHA}.zip"
    
    # Create source code archive excluding specified directories
    log "Creating source code archive..."
    zip -r "${zip_file}" . \
        -x "*.git*" "*/node_modules/*" "*/vendor/*" "*/test/*" "*/tests/*" \
           "*.min.js" "*.log" "*/coverage/*" "*/reports/*" \
        > /dev/null 2>&1
    
    if [[ ! -f "${zip_file}" ]]; then
        error_exit "Failed to create source code archive"
    fi
    
    # Upload to Checkmarx
    local upload_response
    upload_response=$(curl -s -X POST \
        "${CHECKMARX_URL}/cxrestapi/projects/${CHECKMARX_PROJECT_ID}/sourceCode/attachments" \
        -H "Authorization: Bearer ${CHECKMARX_TOKEN}" \
        -H "Content-Type: multipart/form-data" \
        -F "zippedSource=@${zip_file}" \
        -w "%{http_code}")
    
    local http_code="${upload_response: -3}"
    
    if [[ "${http_code}" != "204" ]]; then
        error_exit "Failed to upload source code with HTTP code: ${http_code}"
    fi
    
    log "✅ Source code uploaded successfully"
    
    # Clean up zip file
    rm -f "${zip_file}"
}

# Start SAST scan
start_sast_scan() {
    log "Starting SAST scan..."
    
    # Start scan
    local scan_response
    scan_response=$(curl -s -X POST \
        "${CHECKMARX_URL}/cxrestapi/sast/scans" \
        -H "Authorization: Bearer ${CHECKMARX_TOKEN}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "{
            \"projectId\": ${CHECKMARX_PROJECT_ID},
            \"isIncremental\": true,
            \"isPublic\": false,
            \"forceScan\": false,
            \"comment\": \"Automated DevSecOps pipeline scan - Commit: ${CI_COMMIT_SHA}\"
        }" \
        -w "%{http_code}")
    
    local http_code="${scan_response: -3}"
    local response_body="${scan_response%???}"
    
    if [[ "${http_code}" != "201" ]]; then
        error_exit "Failed to start scan with HTTP code: ${http_code}"
    fi
    
    # Extract scan ID
    export CHECKMARX_SCAN_ID
    CHECKMARX_SCAN_ID=$(echo "${response_body}" | jq -r '.id')
    
    if [[ "${CHECKMARX_SCAN_ID}" == "null" || -z "${CHECKMARX_SCAN_ID}" ]]; then
        error_exit "Failed to extract scan ID from response"
    fi
    
    log "✅ SAST scan started with ID: ${CHECKMARX_SCAN_ID}"
}

# Wait for scan completion
wait_for_scan_completion() {
    log "Waiting for scan completion..."
    
    local max_wait_time=7200  # 2 hours
    local check_interval=30   # 30 seconds
    local elapsed_time=0
    
    while [[ ${elapsed_time} -lt ${max_wait_time} ]]; do
        # Check scan status
        local status_response
        status_response=$(curl -s -X GET \
            "${CHECKMARX_URL}/cxrestapi/sast/scans/${CHECKMARX_SCAN_ID}" \
            -H "Authorization: Bearer ${CHECKMARX_TOKEN}" \
            -H "Accept: application/json" \
            -w "%{http_code}")
        
        local http_code="${status_response: -3}"
        local response_body="${status_response%???}"
        
        if [[ "${http_code}" != "200" ]]; then
            error_exit "Failed to get scan status with HTTP code: ${http_code}"
        fi
        
        local scan_status
        scan_status=$(echo "${response_body}" | jq -r '.status.name')
        
        log "Scan status: ${scan_status}"
        
        case "${scan_status}" in
            "Finished")
                log "✅ Scan completed successfully"
                return 0
                ;;
            "Failed" | "Canceled")
                error_exit "Scan failed with status: ${scan_status}"
                ;;
            "Queued" | "Running" | "SourcePulling" | "Scanning")
                log "Scan in progress... waiting ${check_interval} seconds"
                sleep ${check_interval}
                elapsed_time=$((elapsed_time + check_interval))
                ;;
            *)
                log "Unknown scan status: ${scan_status}, continuing to wait..."
                sleep ${check_interval}
                elapsed_time=$((elapsed_time + check_interval))
                ;;
        esac
    done
    
    error_exit "Scan timed out after ${max_wait_time} seconds"
}

# Get scan results
get_scan_results() {
    log "Retrieving scan results..."
    
    # Get scan statistics
    local stats_response
    stats_response=$(curl -s -X GET \
        "${CHECKMARX_URL}/cxrestapi/sast/scans/${CHECKMARX_SCAN_ID}/resultsStatistics" \
        -H "Authorization: Bearer ${CHECKMARX_TOKEN}" \
        -H "Accept: application/json" \
        -w "%{http_code}")
    
    local http_code="${stats_response: -3}"
    local response_body="${stats_response%???}"
    
    if [[ "${http_code}" != "200" ]]; then
        error_exit "Failed to get scan statistics with HTTP code: ${http_code}"
    fi
    
    # Save statistics
    echo "${response_body}" > "${RESULTS_DIR}/checkmarx-statistics.json"
    
    # Extract vulnerability counts
    local critical_count high_count medium_count low_count info_count
    critical_count=$(echo "${response_body}" | jq -r '.criticalSeverity // 0')
    high_count=$(echo "${response_body}" | jq -r '.highSeverity // 0')
    medium_count=$(echo "${response_body}" | jq -r '.mediumSeverity // 0')
    low_count=$(echo "${response_body}" | jq -r '.lowSeverity // 0')
    info_count=$(echo "${response_body}" | jq -r '.infoSeverity // 0')
    
    log "📊 Vulnerability Summary:"
    log "  Critical: ${critical_count}"
    log "  High: ${high_count}"
    log "  Medium: ${medium_count}"
    log "  Low: ${low_count}"
    log "  Info: ${info_count}"
    
    # Export counts for pipeline use
    echo "CHECKMARX_CRITICAL_COUNT=${critical_count}" >> checkmarx-results.env
    echo "CHECKMARX_HIGH_COUNT=${high_count}" >> checkmarx-results.env
    echo "CHECKMARX_MEDIUM_COUNT=${medium_count}" >> checkmarx-results.env
    echo "CHECKMARX_LOW_COUNT=${low_count}" >> checkmarx-results.env
    echo "CHECKMARX_INFO_COUNT=${info_count}" >> checkmarx-results.env
    
    # Generate detailed report
    generate_detailed_report
    
    log "✅ Scan results retrieved successfully"
}

# Generate detailed report
generate_detailed_report() {
    log "Generating detailed vulnerability report..."
    
    # Get detailed results
    local results_response
    results_response=$(curl -s -X GET \
        "${CHECKMARX_URL}/cxrestapi/sast/scans/${CHECKMARX_SCAN_ID}/results" \
        -H "Authorization: Bearer ${CHECKMARX_TOKEN}" \
        -H "Accept: application/json" \
        -w "%{http_code}")
    
    local http_code="${results_response: -3}"
    local response_body="${results_response%???}"
    
    if [[ "${http_code}" != "200" ]]; then
        log "Warning: Failed to get detailed results with HTTP code: ${http_code}"
        return 0
    fi
    
    # Save detailed results
    echo "${response_body}" > "${RESULTS_DIR}/checkmarx-detailed-results.json"
    
    # Generate JSON report for GitLab security dashboard
    generate_gitlab_security_report "${response_body}"
    
    log "✅ Detailed report generated"
}

# Generate GitLab security report format
generate_gitlab_security_report() {
    local results_data="$1"
    
    log "Generating GitLab security report..."
    
    # Create GitLab-compatible SAST report
    cat > "${RESULTS_DIR}/checkmarx-gitlab-sast.json" <<EOF
{
  "version": "14.0.0",
  "vulnerabilities": [
EOF
    
    # Process results and convert to GitLab format
    echo "${results_data}" | jq -r '.[] | 
    {
        "id": (.id | tostring),
        "category": "sast",
        "name": .queryName,
        "message": .queryName,
        "description": .description,
        "severity": (.severity | ascii_downcase),
        "confidence": "High",
        "scanner": {
            "id": "checkmarx",
            "name": "Checkmarx SAST"
        },
        "location": {
            "file": .fileName,
            "start_line": .line,
            "end_line": .line
        },
        "identifiers": [
            {
                "type": "checkmarx_query_id",
                "name": .queryId,
                "value": .queryId
            }
        ]
    }' | jq -s '.' | jq '.[:-1] | .[] as $item | $item, ","' | sed '$s/,$//' >> "${RESULTS_DIR}/checkmarx-gitlab-sast.json"
    
    echo '  ]' >> "${RESULTS_DIR}/checkmarx-gitlab-sast.json"
    echo '}' >> "${RESULTS_DIR}/checkmarx-gitlab-sast.json"
    
    log "✅ GitLab security report generated"
}

# Apply security gates
apply_security_gates() {
    log "Applying security gates..."
    
    local critical_count high_count
    critical_count=$(grep "CHECKMARX_CRITICAL_COUNT" checkmarx-results.env | cut -d'=' -f2)
    high_count=$(grep "CHECKMARX_HIGH_COUNT" checkmarx-results.env | cut -d'=' -f2)
    
    # Security gate thresholds
    local critical_threshold=0
    local high_threshold=5
    
    local gate_failed=false
    
    # Check critical vulnerabilities
    if [[ ${critical_count} -gt ${critical_threshold} ]]; then
        log "❌ Security Gate FAILED: ${critical_count} critical vulnerabilities found (threshold: ${critical_threshold})"
        gate_failed=true
    fi
    
    # Check high vulnerabilities
    if [[ ${high_count} -gt ${high_threshold} ]]; then
        log "❌ Security Gate FAILED: ${high_count} high vulnerabilities found (threshold: ${high_threshold})"
        gate_failed=true
    fi
    
    if [[ "${gate_failed}" == "true" ]]; then
        log "❌ SAST security gate failed - pipeline will be terminated"
        exit 1
    fi
    
    log "✅ SAST security gate passed"
}

# Main execution
main() {
    log "🔍 Starting Checkmarx SAST security scan..."
    
    validate_environment
    authenticate_checkmarx
    get_or_create_project
    upload_source_code
    start_sast_scan
    wait_for_scan_completion
    get_scan_results
    apply_security_gates
    
    log "🎉 Checkmarx SAST scan completed successfully"
}

# Execute main function
main "$@"