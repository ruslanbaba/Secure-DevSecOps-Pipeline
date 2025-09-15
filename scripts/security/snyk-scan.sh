#!/bin/bash

# Snyk Software Composition Analysis (SCA) Integration Script
# Enterprise-grade dependency vulnerability and license scanning

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../configs/snyk-config.yaml"
RESULTS_DIR="${SCRIPT_DIR}/../../reports/sca"

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
    log "Validating Snyk environment configuration..."
    
    local required_vars=(
        "SNYK_TOKEN"
        "CI_PROJECT_NAME"
        "CI_COMMIT_SHA"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error_exit "Required environment variable ${var} is not set"
        fi
    done
    
    # Validate Snyk token format
    if [[ ! "${SNYK_TOKEN}" =~ ^[a-f0-9-]{36}$ ]]; then
        error_exit "Invalid Snyk token format"
    fi
    
    log "✅ Environment validation completed"
}

# Authenticate with Snyk
authenticate_snyk() {
    log "Authenticating with Snyk..."
    
    # Configure Snyk CLI
    snyk config set api="${SNYK_TOKEN}"
    
    # Test authentication
    if ! snyk auth "${SNYK_TOKEN}" > /dev/null 2>&1; then
        error_exit "Failed to authenticate with Snyk"
    fi
    
    # Verify authentication
    local auth_test
    auth_test=$(snyk config get api 2>/dev/null || echo "")
    
    if [[ -z "${auth_test}" ]]; then
        error_exit "Snyk authentication verification failed"
    fi
    
    log "✅ Successfully authenticated with Snyk"
}

# Discover project manifests
discover_manifests() {
    log "Discovering project manifests..."
    
    local manifests=()
    local manifest_patterns=(
        "package.json"
        "package-lock.json"
        "yarn.lock"
        "pom.xml"
        "build.gradle"
        "requirements.txt"
        "Pipfile"
        "Pipfile.lock"
        "composer.json"
        "composer.lock"
        "Gemfile"
        "Gemfile.lock"
        "go.mod"
        "go.sum"
        "Cargo.toml"
        "Cargo.lock"
    )
    
    for pattern in "${manifest_patterns[@]}"; do
        while IFS= read -r -d '' file; do
            # Exclude files in test directories and node_modules
            if [[ ! "${file}" =~ (test|tests|spec|node_modules|vendor|target|build)/ ]]; then
                manifests+=("${file}")
            fi
        done < <(find . -name "${pattern}" -type f -print0 2>/dev/null || true)
    done
    
    if [[ ${#manifests[@]} -eq 0 ]]; then
        error_exit "No supported manifest files found in project"
    fi
    
    log "📁 Found ${#manifests[@]} manifest files:"
    printf '%s\n' "${manifests[@]}" | sed 's/^/  /'
    
    # Export for later use
    printf '%s\n' "${manifests[@]}" > "${RESULTS_DIR}/discovered-manifests.txt"
    
    log "✅ Manifest discovery completed"
}

# Run vulnerability scan
run_vulnerability_scan() {
    log "Starting dependency vulnerability scan..."
    
    local scan_exit_code=0
    local total_vulnerabilities=0
    local critical_count=0
    local high_count=0
    local medium_count=0
    local low_count=0
    
    # Create combined results file
    echo '{"vulnerabilities": [], "summary": {}}' > "${RESULTS_DIR}/snyk-combined-results.json"
    
    # Scan each discovered manifest
    while IFS= read -r manifest; do
        if [[ -z "${manifest}" ]]; then
            continue
        fi
        
        log "🔍 Scanning manifest: ${manifest}"
        
        local manifest_dir
        manifest_dir=$(dirname "${manifest}")
        local manifest_file
        manifest_file=$(basename "${manifest}")
        
        # Change to manifest directory
        pushd "${manifest_dir}" > /dev/null
        
        # Run Snyk test
        local scan_output
        local temp_json="${RESULTS_DIR}/temp-${manifest_file//\//_}.json"
        
        if snyk test \
            --json \
            --severity-threshold=high \
            --all-projects \
            --detection-depth=5 \
            --exclude=test,spec,docs \
            > "${temp_json}" 2>&1; then
            log "✅ No vulnerabilities found in ${manifest}"
        else
            local exit_code=$?
            if [[ ${exit_code} -eq 1 ]]; then
                log "⚠️ Vulnerabilities found in ${manifest}"
                scan_exit_code=1
                
                # Extract vulnerability counts from JSON
                if [[ -f "${temp_json}" ]]; then
                    local vuln_data
                    vuln_data=$(cat "${temp_json}")
                    
                    # Count vulnerabilities by severity
                    local manifest_critical manifest_high manifest_medium manifest_low
                    manifest_critical=$(echo "${vuln_data}" | jq '[.vulnerabilities[]? | select(.severity == "critical")] | length' 2>/dev/null || echo "0")
                    manifest_high=$(echo "${vuln_data}" | jq '[.vulnerabilities[]? | select(.severity == "high")] | length' 2>/dev/null || echo "0")
                    manifest_medium=$(echo "${vuln_data}" | jq '[.vulnerabilities[]? | select(.severity == "medium")] | length' 2>/dev/null || echo "0")
                    manifest_low=$(echo "${vuln_data}" | jq '[.vulnerabilities[]? | select(.severity == "low")] | length' 2>/dev/null || echo "0")
                    
                    # Add to totals
                    critical_count=$((critical_count + manifest_critical))
                    high_count=$((high_count + manifest_high))
                    medium_count=$((medium_count + manifest_medium))
                    low_count=$((low_count + manifest_low))
                    
                    log "  Critical: ${manifest_critical}, High: ${manifest_high}, Medium: ${manifest_medium}, Low: ${manifest_low}"
                    
                    # Merge results into combined file
                    merge_scan_results "${temp_json}" "${manifest}"
                fi
            else
                log "❌ Scan error for ${manifest} (exit code: ${exit_code})"
            fi
        fi
        
        # Clean up temporary file
        rm -f "${temp_json}"
        
        popd > /dev/null
        
    done < "${RESULTS_DIR}/discovered-manifests.txt"
    
    # Calculate total vulnerabilities
    total_vulnerabilities=$((critical_count + high_count + medium_count + low_count))
    
    # Create summary
    cat > "${RESULTS_DIR}/snyk-summary.json" <<EOF
{
    "total_vulnerabilities": ${total_vulnerabilities},
    "critical": ${critical_count},
    "high": ${high_count},
    "medium": ${medium_count},
    "low": ${low_count},
    "scan_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "project": "${CI_PROJECT_NAME}",
    "commit": "${CI_COMMIT_SHA}"
}
EOF
    
    # Export counts for pipeline use
    echo "SNYK_TOTAL_VULNERABILITIES=${total_vulnerabilities}" >> snyk-results.env
    echo "SNYK_CRITICAL_COUNT=${critical_count}" >> snyk-results.env
    echo "SNYK_HIGH_COUNT=${high_count}" >> snyk-results.env
    echo "SNYK_MEDIUM_COUNT=${medium_count}" >> snyk-results.env
    echo "SNYK_LOW_COUNT=${low_count}" >> snyk-results.env
    
    log "📊 Vulnerability Summary:"
    log "  Total: ${total_vulnerabilities}"
    log "  Critical: ${critical_count}"
    log "  High: ${high_count}"
    log "  Medium: ${medium_count}"
    log "  Low: ${low_count}"
    
    return ${scan_exit_code}
}

# Merge scan results
merge_scan_results() {
    local temp_file="$1"
    local manifest_path="$2"
    local combined_file="${RESULTS_DIR}/snyk-combined-results.json"
    
    if [[ -f "${temp_file}" ]] && [[ -s "${temp_file}" ]]; then
        # Add manifest information to vulnerabilities
        jq --arg manifest "${manifest_path}" \
           '.vulnerabilities[]? |= (. + {manifest: $manifest})' \
           "${temp_file}" > "${temp_file}.enriched"
        
        # Merge with combined results
        jq -s '.[0].vulnerabilities += .[1].vulnerabilities? // [] | .[0]' \
           "${combined_file}" "${temp_file}.enriched" > "${combined_file}.tmp"
        
        mv "${combined_file}.tmp" "${combined_file}"
        rm -f "${temp_file}.enriched"
    fi
}

# Run license audit
run_license_audit() {
    log "Starting license compliance audit..."
    
    local license_exit_code=0
    local license_issues=0
    
    # Run Snyk license audit
    if snyk test \
        --json \
        --print-deps \
        --dev \
        > "${RESULTS_DIR}/snyk-licenses.json" 2>&1; then
        log "✅ No license issues found"
    else
        local exit_code=$?
        if [[ ${exit_code} -eq 1 ]]; then
            log "⚠️ License issues detected"
            license_exit_code=1
            
            # Extract license issues
            if [[ -f "${RESULTS_DIR}/snyk-licenses.json" ]]; then
                license_issues=$(jq '[.vulnerabilities[]? | select(.type == "license")] | length' "${RESULTS_DIR}/snyk-licenses.json" 2>/dev/null || echo "0")
                log "  License Issues: ${license_issues}"
            fi
        else
            log "❌ License audit error (exit code: ${exit_code})"
        fi
    fi
    
    # Export license results
    echo "SNYK_LICENSE_ISSUES=${license_issues}" >> snyk-results.env
    
    return ${license_exit_code}
}

# Generate GitLab security report
generate_gitlab_security_report() {
    log "Generating GitLab security report..."
    
    local combined_file="${RESULTS_DIR}/snyk-combined-results.json"
    local gitlab_report="${RESULTS_DIR}/snyk-gitlab-dependency-scanning.json"
    
    if [[ ! -f "${combined_file}" ]]; then
        log "⚠️ No combined results file found, creating empty report"
        echo '{"version": "14.0.0", "vulnerabilities": []}' > "${gitlab_report}"
        return 0
    fi
    
    # Convert Snyk format to GitLab security report format
    jq '{
        version: "14.0.0",
        vulnerabilities: [
            .vulnerabilities[]? | {
                id: (.id // (.title + "-" + (.identifiers.CVE[0] // "unknown"))),
                category: "dependency_scanning",
                name: .title,
                message: .title,
                description: .description,
                severity: (.severity | ascii_downcase),
                confidence: "High",
                scanner: {
                    id: "snyk",
                    name: "Snyk"
                },
                location: {
                    file: (.manifest // "unknown"),
                    dependency: {
                        package: {
                            name: (.packageName // "unknown")
                        },
                        version: (.version // "unknown")
                    }
                },
                identifiers: [
                    {
                        type: "snyk",
                        name: (.id // "unknown"),
                        value: (.id // "unknown")
                    }
                ] + (
                    if .identifiers.CVE then
                        [.identifiers.CVE[] | {
                            type: "cve",
                            name: .,
                            value: .,
                            url: ("https://cve.mitre.org/cgi-bin/cvename.cgi?name=" + .)
                        }]
                    else [] end
                ) + (
                    if .identifiers.CWE then
                        [.identifiers.CWE[] | {
                            type: "cwe",
                            name: .,
                            value: .,
                            url: ("https://cwe.mitre.org/data/definitions/" + (. | ltrimstr("CWE-")) + ".html")
                        }]
                    else [] end
                ),
                links: [
                    {
                        url: (.url // "")
                    }
                ]
            }
        ]
    }' "${combined_file}" > "${gitlab_report}"
    
    log "✅ GitLab security report generated"
}

# Generate SARIF report
generate_sarif_report() {
    log "Generating SARIF report..."
    
    local combined_file="${RESULTS_DIR}/snyk-combined-results.json"
    local sarif_report="${RESULTS_DIR}/snyk-sarif.json"
    
    if [[ ! -f "${combined_file}" ]]; then
        log "⚠️ No combined results file found for SARIF generation"
        return 0
    fi
    
    # Convert to SARIF format
    snyk-to-sarif -i "${combined_file}" -o "${sarif_report}" || {
        log "⚠️ SARIF conversion failed, creating manual conversion"
        
        # Manual SARIF conversion as fallback
        cat > "${sarif_report}" <<EOF
{
    "\$schema": "https://schemastore.azurewebsites.net/schemas/json/sarif-2.1.0.json",
    "version": "2.1.0",
    "runs": [
        {
            "tool": {
                "driver": {
                    "name": "Snyk",
                    "version": "1.0.0",
                    "informationUri": "https://snyk.io/"
                }
            },
            "results": []
        }
    ]
}
EOF
    }
    
    log "✅ SARIF report generated"
}

# Apply security gates
apply_security_gates() {
    log "Applying SCA security gates..."
    
    local critical_count high_count license_issues
    critical_count=$(grep "SNYK_CRITICAL_COUNT" snyk-results.env | cut -d'=' -f2 2>/dev/null || echo "0")
    high_count=$(grep "SNYK_HIGH_COUNT" snyk-results.env | cut -d'=' -f2 2>/dev/null || echo "0")
    license_issues=$(grep "SNYK_LICENSE_ISSUES" snyk-results.env | cut -d'=' -f2 2>/dev/null || echo "0")
    
    # Security gate thresholds
    local critical_threshold=0
    local high_threshold=10
    local license_threshold=0
    
    local gate_failed=false
    
    # Check critical vulnerabilities
    if [[ ${critical_count} -gt ${critical_threshold} ]]; then
        log "❌ Security Gate FAILED: ${critical_count} critical dependency vulnerabilities found (threshold: ${critical_threshold})"
        gate_failed=true
    fi
    
    # Check high vulnerabilities
    if [[ ${high_count} -gt ${high_threshold} ]]; then
        log "❌ Security Gate FAILED: ${high_count} high dependency vulnerabilities found (threshold: ${high_threshold})"
        gate_failed=true
    fi
    
    # Check license issues
    if [[ ${license_issues} -gt ${license_threshold} ]]; then
        log "❌ License Gate FAILED: ${license_issues} license compliance issues found (threshold: ${license_threshold})"
        gate_failed=true
    fi
    
    if [[ "${gate_failed}" == "true" ]]; then
        log "❌ SCA security gate failed - pipeline will be terminated"
        
        # Generate failure summary
        cat > "${RESULTS_DIR}/sca-gate-failure.json" <<EOF
{
    "gate_status": "failed",
    "critical_vulnerabilities": ${critical_count},
    "high_vulnerabilities": ${high_count},
    "license_issues": ${license_issues},
    "thresholds": {
        "critical": ${critical_threshold},
        "high": ${high_threshold},
        "license": ${license_threshold}
    },
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
        
        exit 1
    fi
    
    log "✅ SCA security gate passed"
}

# Monitor project
setup_monitoring() {
    log "Setting up Snyk monitoring..."
    
    # Monitor project for ongoing vulnerability detection
    if snyk monitor \
        --all-projects \
        --detection-depth=5 \
        --project-name="${CI_PROJECT_NAME}" > /dev/null 2>&1; then
        log "✅ Project monitoring configured successfully"
    else
        log "⚠️ Failed to configure project monitoring (non-critical)"
    fi
}

# Generate comprehensive report
generate_comprehensive_report() {
    log "Generating comprehensive SCA report..."
    
    # Create HTML report
    cat > "${RESULTS_DIR}/sca-report.html" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>SCA Security Report - ${CI_PROJECT_NAME}</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f5f5f5; padding: 20px; border-radius: 5px; }
        .summary { margin: 20px 0; }
        .critical { color: #d63384; font-weight: bold; }
        .high { color: #fd7e14; font-weight: bold; }
        .medium { color: #ffc107; font-weight: bold; }
        .low { color: #198754; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #f8f9fa; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🔍 Software Composition Analysis Report</h1>
        <p><strong>Project:</strong> ${CI_PROJECT_NAME}</p>
        <p><strong>Scan Date:</strong> $(date)</p>
        <p><strong>Commit:</strong> ${CI_COMMIT_SHA}</p>
    </div>
    
    <div class="summary">
        <h2>📊 Vulnerability Summary</h2>
        <p><span class="critical">Critical:</span> $(grep "SNYK_CRITICAL_COUNT" snyk-results.env | cut -d'=' -f2 2>/dev/null || echo "0")</p>
        <p><span class="high">High:</span> $(grep "SNYK_HIGH_COUNT" snyk-results.env | cut -d'=' -f2 2>/dev/null || echo "0")</p>
        <p><span class="medium">Medium:</span> $(grep "SNYK_MEDIUM_COUNT" snyk-results.env | cut -d'=' -f2 2>/dev/null || echo "0")</p>
        <p><span class="low">Low:</span> $(grep "SNYK_LOW_COUNT" snyk-results.env | cut -d'=' -f2 2>/dev/null || echo "0")</p>
        <p><strong>License Issues:</strong> $(grep "SNYK_LICENSE_ISSUES" snyk-results.env | cut -d'=' -f2 2>/dev/null || echo "0")</p>
    </div>
    
    <div>
        <h2>📋 Scanned Manifests</h2>
        <ul>
EOF
    
    if [[ -f "${RESULTS_DIR}/discovered-manifests.txt" ]]; then
        while IFS= read -r manifest; do
            echo "            <li>${manifest}</li>" >> "${RESULTS_DIR}/sca-report.html"
        done < "${RESULTS_DIR}/discovered-manifests.txt"
    fi
    
    cat >> "${RESULTS_DIR}/sca-report.html" <<EOF
        </ul>
    </div>
    
    <div>
        <p><em>Generated by Snyk SCA Scanner - DevSecOps Pipeline</em></p>
    </div>
</body>
</html>
EOF
    
    log "✅ Comprehensive report generated"
}

# Main execution
main() {
    log "🔍 Starting Snyk SCA security scan..."
    
    validate_environment
    authenticate_snyk
    discover_manifests
    
    local vulnerability_scan_result=0
    local license_audit_result=0
    
    # Run scans
    run_vulnerability_scan || vulnerability_scan_result=$?
    run_license_audit || license_audit_result=$?
    
    # Generate reports
    generate_gitlab_security_report
    generate_sarif_report
    generate_comprehensive_report
    
    # Setup monitoring (non-critical)
    setup_monitoring || true
    
    # Apply security gates
    apply_security_gates
    
    log "🎉 Snyk SCA scan completed successfully"
}

# Execute main function
main "$@"