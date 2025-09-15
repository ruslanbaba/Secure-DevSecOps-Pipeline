#!/bin/bash

# OPA Conftest Policy Validation Script
# Enterprise-grade policy-as-code validation for Kubernetes manifests

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICIES_DIR="${SCRIPT_DIR}/../policies"
RESULTS_DIR="${SCRIPT_DIR}/../../reports/policy-validation"
MANIFESTS_DIR="${SCRIPT_DIR}/../../k8s"

# Create directories
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
    log "Validating policy validation environment..."
    
    local required_vars=(
        "CI_PROJECT_NAME"
        "CI_COMMIT_SHA"
        "CI_ENVIRONMENT_SLUG"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error_exit "Required environment variable ${var} is not set"
        fi
    done
    
    # Check if Conftest is available
    if ! command -v conftest >/dev/null 2>&1; then
        error_exit "Conftest is not installed or not in PATH"
    fi
    
    log "✅ Environment validation completed"
}

# Setup Conftest environment
setup_conftest() {
    log "Setting up Conftest environment..."
    
    # Verify policies directory exists
    if [[ ! -d "${POLICIES_DIR}" ]]; then
        error_exit "Policies directory not found: ${POLICIES_DIR}"
    fi
    
    # Verify policy files exist
    local policy_files
    policy_files=$(find "${POLICIES_DIR}" -name "*.rego" 2>/dev/null | wc -l)
    
    if [[ ${policy_files} -eq 0 ]]; then
        error_exit "No policy files (.rego) found in ${POLICIES_DIR}"
    fi
    
    log "📋 Found ${policy_files} policy files"
    
    # List policy files for debugging
    find "${POLICIES_DIR}" -name "*.rego" | while read -r policy_file; do
        log "  - $(basename "${policy_file}")"
    done
    
    log "✅ Conftest environment configured"
}

# Discover Kubernetes manifests
discover_manifests() {
    log "Discovering Kubernetes manifests..."
    
    local manifests=()
    local manifest_patterns=(
        "*.yaml"
        "*.yml"
    )
    
    # Search for manifests in k8s directory
    if [[ -d "${MANIFESTS_DIR}" ]]; then
        for pattern in "${manifest_patterns[@]}"; do
            while IFS= read -r -d '' file; do
                # Skip hidden files and directories
                if [[ ! "$(basename "${file}")" =~ ^\. ]]; then
                    manifests+=("${file}")
                fi
            done < <(find "${MANIFESTS_DIR}" -name "${pattern}" -type f -print0 2>/dev/null || true)
        done
    fi
    
    # Also check root directory for manifests
    for pattern in "${manifest_patterns[@]}"; do
        while IFS= read -r -d '' file; do
            # Only include files that look like Kubernetes manifests
            if grep -q "apiVersion\|kind" "${file}" 2>/dev/null; then
                manifests+=("${file}")
            fi
        done < <(find . -maxdepth 1 -name "${pattern}" -type f -print0 2>/dev/null || true)
    done
    
    if [[ ${#manifests[@]} -eq 0 ]]; then
        error_exit "No Kubernetes manifest files found"
    fi
    
    log "📁 Found ${#manifests[@]} manifest files:"
    printf '%s\n' "${manifests[@]}" | sed 's/^/  /'
    
    # Export for later use
    printf '%s\n' "${manifests[@]}" > "${RESULTS_DIR}/discovered-manifests.txt"
    
    log "✅ Manifest discovery completed"
}

# Validate policy syntax
validate_policies() {
    log "Validating policy syntax..."
    
    # Use conftest verify to check policy syntax
    if conftest verify --policy "${POLICIES_DIR}" > "${RESULTS_DIR}/policy-verification.txt" 2>&1; then
        log "✅ All policies passed syntax validation"
    else
        log "❌ Policy syntax validation failed:"
        cat "${RESULTS_DIR}/policy-verification.txt"
        error_exit "Policy syntax validation failed"
    fi
}

# Test individual manifest
test_manifest() {
    local manifest_file="$1"
    local manifest_name
    manifest_name=$(basename "${manifest_file}")
    
    log "🔍 Testing manifest: ${manifest_name}"
    
    local test_output="${RESULTS_DIR}/test-${manifest_name//\//_}.json"
    local test_exit_code=0
    
    # Run conftest test
    conftest test \
        --policy "${POLICIES_DIR}" \
        --output json \
        --all-namespaces \
        "${manifest_file}" > "${test_output}" 2>&1 || test_exit_code=$?
    
    # Process test results
    if [[ -f "${test_output}" ]]; then
        local failures successes warnings
        failures=$(jq '[.[] | select(.failures | length > 0)] | length' "${test_output}" 2>/dev/null || echo "0")
        warnings=$(jq '[.[] | select(.warnings | length > 0)] | length' "${test_output}" 2>/dev/null || echo "0")
        successes=$(jq '[.[] | select(.failures | length == 0) | select(.warnings | length == 0)] | length' "${test_output}" 2>/dev/null || echo "0")
        
        log "  Results: ${successes} passed, ${failures} failed, ${warnings} warnings"
        
        # Log failures
        if [[ ${failures} -gt 0 ]]; then
            log "  Failures:"
            jq -r '.[] | select(.failures | length > 0) | .failures[]' "${test_output}" 2>/dev/null | sed 's/^/    /'
        fi
        
        # Log warnings
        if [[ ${warnings} -gt 0 ]]; then
            log "  Warnings:"
            jq -r '.[] | select(.warnings | length > 0) | .warnings[]' "${test_output}" 2>/dev/null | sed 's/^/    /'
        fi
        
        return ${test_exit_code}
    else
        error_exit "Test output file not found for ${manifest_name}"
    fi
}

# Run policy validation
run_policy_validation() {
    log "Starting policy validation..."
    
    local total_manifests=0
    local failed_manifests=0
    local passed_manifests=0
    local total_failures=0
    local total_warnings=0
    
    # Create combined results file
    echo '[]' > "${RESULTS_DIR}/combined-results.json"
    
    # Test each manifest
    while IFS= read -r manifest; do
        if [[ -z "${manifest}" ]]; then
            continue
        fi
        
        total_manifests=$((total_manifests + 1))
        
        if test_manifest "${manifest}"; then
            passed_manifests=$((passed_manifests + 1))
        else
            failed_manifests=$((failed_manifests + 1))
        fi
        
        # Merge results
        local manifest_name
        manifest_name=$(basename "${manifest}")
        local manifest_results="${RESULTS_DIR}/test-${manifest_name//\//_}.json"
        
        if [[ -f "${manifest_results}" ]]; then
            # Extract and accumulate counts
            local manifest_failures manifest_warnings
            manifest_failures=$(jq '[.[] | select(.failures | length > 0)] | length' "${manifest_results}" 2>/dev/null || echo "0")
            manifest_warnings=$(jq '[.[] | select(.warnings | length > 0)] | length' "${manifest_results}" 2>/dev/null || echo "0")
            
            total_failures=$((total_failures + manifest_failures))
            total_warnings=$((total_warnings + manifest_warnings))
            
            # Merge into combined results
            jq -s '.[0] + .[1]' "${RESULTS_DIR}/combined-results.json" "${manifest_results}" > "${RESULTS_DIR}/combined-results.tmp"
            mv "${RESULTS_DIR}/combined-results.tmp" "${RESULTS_DIR}/combined-results.json"
        fi
        
    done < "${RESULTS_DIR}/discovered-manifests.txt"
    
    # Create summary
    cat > "${RESULTS_DIR}/validation-summary.json" <<EOF
{
    "total_manifests": ${total_manifests},
    "passed_manifests": ${passed_manifests},
    "failed_manifests": ${failed_manifests},
    "total_failures": ${total_failures},
    "total_warnings": ${total_warnings},
    "validation_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "project": "${CI_PROJECT_NAME}",
    "commit": "${CI_COMMIT_SHA}",
    "environment": "${CI_ENVIRONMENT_SLUG:-staging}"
}
EOF
    
    # Export results for pipeline use
    echo "CONFTEST_TOTAL_MANIFESTS=${total_manifests}" >> conftest-results.env
    echo "CONFTEST_PASSED_MANIFESTS=${passed_manifests}" >> conftest-results.env
    echo "CONFTEST_FAILED_MANIFESTS=${failed_manifests}" >> conftest-results.env
    echo "CONFTEST_TOTAL_FAILURES=${total_failures}" >> conftest-results.env
    echo "CONFTEST_TOTAL_WARNINGS=${total_warnings}" >> conftest-results.env
    
    log "📊 Policy Validation Summary:"
    log "  Total Manifests: ${total_manifests}"
    log "  Passed: ${passed_manifests}"
    log "  Failed: ${failed_manifests}"
    log "  Policy Violations: ${total_failures}"
    log "  Warnings: ${total_warnings}"
    
    log "✅ Policy validation completed"
    
    return ${failed_manifests}
}

# Generate detailed policy report
generate_policy_report() {
    log "Generating detailed policy report..."
    
    local combined_file="${RESULTS_DIR}/combined-results.json"
    local detailed_report="${RESULTS_DIR}/policy-detailed-report.json"
    
    if [[ ! -f "${combined_file}" ]]; then
        log "⚠️ No combined results file found"
        return 0
    fi
    
    # Create detailed report with policy violations categorized
    jq '{
        summary: {
            total_resources: length,
            failed_resources: [.[] | select(.failures | length > 0)] | length,
            warning_resources: [.[] | select(.warnings | length > 0)] | length,
            passed_resources: [.[] | select(.failures | length == 0) | select(.warnings | length == 0)] | length
        },
        policy_violations: [
            .[] | select(.failures | length > 0) | {
                filename: .filename,
                violations: .failures
            }
        ],
        policy_warnings: [
            .[] | select(.warnings | length > 0) | {
                filename: .filename,
                warnings: .warnings
            }
        ],
        compliance_status: {
            security_compliant: ([.[] | select(.failures | length > 0)] | length == 0),
            has_warnings: ([.[] | select(.warnings | length > 0)] | length > 0)
        }
    }' "${combined_file}" > "${detailed_report}"
    
    log "✅ Detailed policy report generated"
}

# Generate GitLab security report
generate_gitlab_security_report() {
    log "Generating GitLab security report..."
    
    local combined_file="${RESULTS_DIR}/combined-results.json"
    local gitlab_report="${RESULTS_DIR}/conftest-gitlab-sast.json"
    
    if [[ ! -f "${combined_file}" ]]; then
        log "⚠️ No combined results file found, creating empty report"
        echo '{"version": "14.0.0", "vulnerabilities": []}' > "${gitlab_report}"
        return 0
    fi
    
    # Convert policy violations to GitLab security report format
    jq '{
        version: "14.0.0",
        vulnerabilities: [
            .[] | select(.failures | length > 0) | .failures[] as $failure | {
                id: ((.filename | gsub("/"; "_")) + "-" + ($failure | gsub(" "; "_"))),
                category: "sast",
                name: "Policy Violation",
                message: $failure,
                description: ("Policy violation in " + .filename + ": " + $failure),
                severity: "high",
                confidence: "High",
                scanner: {
                    id: "conftest",
                    name: "OPA Conftest"
                },
                location: {
                    file: .filename,
                    start_line: 1,
                    end_line: 1
                },
                identifiers: [
                    {
                        type: "conftest_policy",
                        name: "policy_violation",
                        value: $failure
                    }
                ]
            }
        ]
    }' "${combined_file}" > "${gitlab_report}"
    
    log "✅ GitLab security report generated"
}

# Apply policy gates
apply_policy_gates() {
    log "Applying policy validation gates..."
    
    local total_failures total_warnings
    total_failures=$(grep "CONFTEST_TOTAL_FAILURES" conftest-results.env | cut -d'=' -f2 2>/dev/null || echo "0")
    total_warnings=$(grep "CONFTEST_TOTAL_WARNINGS" conftest-results.env | cut -d'=' -f2 2>/dev/null || echo "0")
    
    # Policy gate thresholds
    local failure_threshold=0
    local warning_threshold=10
    
    local gate_failed=false
    
    # Check policy violations
    if [[ ${total_failures} -gt ${failure_threshold} ]]; then
        log "❌ Policy Gate FAILED: ${total_failures} policy violations found (threshold: ${failure_threshold})"
        gate_failed=true
    fi
    
    # Check warnings (non-blocking but logged)
    if [[ ${total_warnings} -gt ${warning_threshold} ]]; then
        log "⚠️ Warning: ${total_warnings} policy warnings found (threshold: ${warning_threshold})"
    fi
    
    if [[ "${gate_failed}" == "true" ]]; then
        log "❌ Policy validation gate failed - deployment blocked"
        
        # Generate detailed failure report
        cat > "${RESULTS_DIR}/policy-gate-failure.json" <<EOF
{
    "gate_status": "failed",
    "policy_violations": ${total_failures},
    "policy_warnings": ${total_warnings},
    "thresholds": {
        "violations": ${failure_threshold},
        "warnings": ${warning_threshold}
    },
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "remediation": "Review and fix policy violations before deployment"
}
EOF
        
        exit 1
    fi
    
    log "✅ Policy validation gate passed"
}

# Generate compliance report
generate_compliance_report() {
    log "Generating compliance report..."
    
    # Create compliance mapping report
    cat > "${RESULTS_DIR}/compliance-report.json" <<EOF
{
    "compliance_frameworks": {
        "CIS_Kubernetes_Benchmark": {
            "version": "1.7.0",
            "controls_evaluated": [
                "4.2.1 - Minimize the admission of privileged containers",
                "4.2.2 - Minimize the admission of containers wishing to share the host process ID namespace",
                "4.2.3 - Minimize the admission of containers wishing to share the host IPC namespace",
                "4.2.4 - Minimize the admission of containers wishing to share the host network namespace",
                "4.2.5 - Minimize the admission of containers with allowPrivilegeEscalation",
                "4.2.6 - Minimize the admission of root containers",
                "5.1.1 - Ensure that the cluster-admin role is only used where required",
                "5.1.3 - Minimize wildcard use in Roles and ClusterRoles",
                "5.7.1 - Create administrative boundaries between resources using namespaces"
            ],
            "compliance_status": "evaluated"
        },
        "NIST_800_53": {
            "version": "Rev 5",
            "controls_evaluated": [
                "AC-2 - Account Management",
                "AC-3 - Access Enforcement",
                "AC-6 - Least Privilege",
                "CM-6 - Configuration Settings",
                "SC-2 - Application Partitioning",
                "SC-3 - Security Function Isolation",
                "SI-3 - Malicious Code Protection"
            ],
            "compliance_status": "evaluated"
        },
        "SOC2_Type_II": {
            "trust_criteria": [
                "CC6.1 - Logical and Physical Access Controls",
                "CC6.2 - Authorization",
                "CC6.3 - Entity Access",
                "CC6.7 - Data Transmission",
                "CC7.1 - System Monitoring"
            ],
            "compliance_status": "evaluated"
        }
    },
    "evaluation_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "project": "${CI_PROJECT_NAME}",
    "environment": "${CI_ENVIRONMENT_SLUG:-staging}",
    "total_violations": $(grep "CONFTEST_TOTAL_FAILURES" conftest-results.env | cut -d'=' -f2 2>/dev/null || echo "0"),
    "total_warnings": $(grep "CONFTEST_TOTAL_WARNINGS" conftest-results.env | cut -d'=' -f2 2>/dev/null || echo "0")
}
EOF
    
    log "✅ Compliance report generated"
}

# Generate comprehensive HTML report
generate_html_report() {
    log "Generating comprehensive HTML report..."
    
    # Create HTML report
    cat > "${RESULTS_DIR}/policy-validation-report.html" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Policy Validation Report - ${CI_PROJECT_NAME}</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f5f5f5; padding: 20px; border-radius: 5px; }
        .summary { margin: 20px 0; }
        .passed { color: #198754; font-weight: bold; }
        .failed { color: #d63384; font-weight: bold; }
        .warning { color: #fd7e14; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #f8f9fa; }
        .violation { background-color: #f8d7da; }
        .warning-row { background-color: #fff3cd; }
        .success-row { background-color: #d1e7dd; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🛡️ Policy Validation Report</h1>
        <p><strong>Project:</strong> ${CI_PROJECT_NAME}</p>
        <p><strong>Environment:</strong> ${CI_ENVIRONMENT_SLUG:-staging}</p>
        <p><strong>Validation Date:</strong> $(date)</p>
        <p><strong>Commit:</strong> ${CI_COMMIT_SHA}</p>
    </div>
    
    <div class="summary">
        <h2>📊 Validation Summary</h2>
        <p><strong>Total Manifests:</strong> $(grep "CONFTEST_TOTAL_MANIFESTS" conftest-results.env | cut -d'=' -f2 2>/dev/null || echo "0")</p>
        <p><span class="passed">Passed:</span> $(grep "CONFTEST_PASSED_MANIFESTS" conftest-results.env | cut -d'=' -f2 2>/dev/null || echo "0")</p>
        <p><span class="failed">Failed:</span> $(grep "CONFTEST_FAILED_MANIFESTS" conftest-results.env | cut -d'=' -f2 2>/dev/null || echo "0")</p>
        <p><span class="failed">Policy Violations:</span> $(grep "CONFTEST_TOTAL_FAILURES" conftest-results.env | cut -d'=' -f2 2>/dev/null || echo "0")</p>
        <p><span class="warning">Warnings:</span> $(grep "CONFTEST_TOTAL_WARNINGS" conftest-results.env | cut -d'=' -f2 2>/dev/null || echo "0")</p>
    </div>
    
    <div>
        <h2>🔍 Policy Coverage</h2>
        <ul>
            <li>Container Security (privileged containers, root users, capabilities)</li>
            <li>Resource Management (CPU/memory limits and requests)</li>
            <li>Network Security (host networking, port restrictions)</li>
            <li>Image Security (trusted registries, tag validation)</li>
            <li>RBAC and Access Control (service accounts, role bindings)</li>
            <li>Pod Security Standards (PSS compliance)</li>
            <li>Data Protection (secret handling, encryption)</li>
            <li>Compliance Frameworks (CIS, NIST, SOC2)</li>
        </ul>
    </div>
    
    <div>
        <h2>📋 Manifests Tested</h2>
        <ul>
EOF
    
    if [[ -f "${RESULTS_DIR}/discovered-manifests.txt" ]]; then
        while IFS= read -r manifest; do
            echo "            <li>$(basename "${manifest}")</li>" >> "${RESULTS_DIR}/policy-validation-report.html"
        done < "${RESULTS_DIR}/discovered-manifests.txt"
    fi
    
    cat >> "${RESULTS_DIR}/policy-validation-report.html" <<EOF
        </ul>
    </div>
    
    <div>
        <p><em>Generated by OPA Conftest Policy Validator - DevSecOps Pipeline</em></p>
    </div>
</body>
</html>
EOF
    
    log "✅ HTML report generated"
}

# Main execution
main() {
    log "🔍 Starting OPA Conftest policy validation..."
    
    validate_environment
    setup_conftest
    discover_manifests
    validate_policies
    
    local validation_result=0
    run_policy_validation || validation_result=$?
    
    # Generate reports
    generate_policy_report
    generate_gitlab_security_report
    generate_compliance_report
    generate_html_report
    
    # Apply policy gates
    apply_policy_gates
    
    log "🎉 OPA Conftest policy validation completed successfully"
}

# Execute main function
main "$@"