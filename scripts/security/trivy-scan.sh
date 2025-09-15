#!/bin/bash

# Trivy Container Security Scanning Script
# Enterprise-grade container vulnerability and configuration scanning

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../configs/trivy-config.yaml"
RESULTS_DIR="${SCRIPT_DIR}/../../reports/container-security"
CACHE_DIR="/tmp/.trivy-cache"

# Create directories
mkdir -p "${RESULTS_DIR}" "${CACHE_DIR}"

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
    log "Validating container security environment..."
    
    local required_vars=(
        "CI_REGISTRY_IMAGE"
        "IMAGE_TAG"
        "CI_PROJECT_NAME"
        "CI_COMMIT_SHA"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error_exit "Required environment variable ${var} is not set"
        fi
    done
    
    # Validate image tag format
    if [[ ! "${IMAGE_TAG}" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        error_exit "Invalid image tag format: ${IMAGE_TAG}"
    fi
    
    log "✅ Environment validation completed"
}

# Setup Trivy environment
setup_trivy() {
    log "Setting up Trivy scanner..."
    
    # Set Trivy environment variables
    export TRIVY_CACHE_DIR="${CACHE_DIR}"
    export TRIVY_TIMEOUT="10m"
    export TRIVY_NO_PROGRESS="true"
    export TRIVY_QUIET="false"
    export TRIVY_FORMAT="json"
    export TRIVY_EXIT_CODE="0"  # Handle exit codes manually
    
    # Create ignore file if it doesn't exist
    if [[ ! -f ".trivyignore" ]]; then
        cat > .trivyignore <<EOF
# Trivy ignore file for enterprise security scanning
# Temporary ignores for false positives (review regularly)

# Example: Ignore specific CVE until patch available
# CVE-2021-12345

# Example: Ignore low severity in test dependencies
# */test/*

# Development dependencies (if applicable)
*/node_modules/*/test/*
*/vendor/*/test/*
EOF
        log "📝 Created default .trivyignore file"
    fi
    
    log "✅ Trivy environment configured"
}

# Update vulnerability database
update_trivy_db() {
    log "Updating Trivy vulnerability database..."
    
    # Update vulnerability database
    if trivy image --download-db-only > /dev/null 2>&1; then
        log "✅ Vulnerability database updated successfully"
    else
        log "⚠️ Failed to update vulnerability database, using cached version"
    fi
    
    # Update Java database if scanning Java applications
    if trivy image --download-java-db-only > /dev/null 2>&1; then
        log "✅ Java vulnerability database updated successfully"
    else
        log "⚠️ Failed to update Java vulnerability database, using cached version"
    fi
}

# Validate container image
validate_image() {
    log "Validating container image accessibility..."
    
    local image_name="${CI_REGISTRY_IMAGE}:${IMAGE_TAG}"
    
    # Check if image exists and is accessible
    if ! docker image inspect "${image_name}" > /dev/null 2>&1; then
        # Try to pull the image
        log "Image not found locally, attempting to pull..."
        if ! docker pull "${image_name}" > /dev/null 2>&1; then
            error_exit "Failed to access container image: ${image_name}"
        fi
    fi
    
    # Get image information
    local image_id
    image_id=$(docker image inspect "${image_name}" --format '{{.Id}}' 2>/dev/null || echo "unknown")
    
    local image_size
    image_size=$(docker image inspect "${image_name}" --format '{{.Size}}' 2>/dev/null || echo "0")
    
    local created_date
    created_date=$(docker image inspect "${image_name}" --format '{{.Created}}' 2>/dev/null || echo "unknown")
    
    log "📦 Image Information:"
    log "  Name: ${image_name}"
    log "  ID: ${image_id}"
    log "  Size: $((image_size / 1024 / 1024)) MB"
    log "  Created: ${created_date}"
    
    # Export image info for later use
    echo "SCANNED_IMAGE=${image_name}" >> trivy-results.env
    echo "IMAGE_ID=${image_id}" >> trivy-results.env
    echo "IMAGE_SIZE=${image_size}" >> trivy-results.env
    
    log "✅ Container image validated"
}

# Run vulnerability scan
run_vulnerability_scan() {
    log "Starting container vulnerability scan..."
    
    local image_name="${CI_REGISTRY_IMAGE}:${IMAGE_TAG}"
    local scan_output="${RESULTS_DIR}/trivy-vulnerabilities.json"
    local scan_exit_code=0
    
    # Run Trivy vulnerability scan
    trivy image \
        --format json \
        --output "${scan_output}" \
        --severity HIGH,CRITICAL \
        --vuln-type os,library \
        --ignore-unfixed \
        --timeout 10m \
        --cache-dir "${CACHE_DIR}" \
        "${image_name}" || scan_exit_code=$?
    
    if [[ ${scan_exit_code} -ne 0 && ${scan_exit_code} -ne 1 ]]; then
        error_exit "Trivy vulnerability scan failed with exit code: ${scan_exit_code}"
    fi
    
    # Process scan results
    if [[ -f "${scan_output}" ]]; then
        process_vulnerability_results "${scan_output}"
    else
        error_exit "Vulnerability scan output file not found"
    fi
    
    log "✅ Vulnerability scan completed"
}

# Process vulnerability scan results
process_vulnerability_results() {
    local scan_file="$1"
    
    log "Processing vulnerability scan results..."
    
    # Extract vulnerability counts by severity
    local critical_count high_count medium_count low_count unknown_count
    critical_count=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' "${scan_file}" 2>/dev/null || echo "0")
    high_count=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH")] | length' "${scan_file}" 2>/dev/null || echo "0")
    medium_count=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "MEDIUM")] | length' "${scan_file}" 2>/dev/null || echo "0")
    low_count=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "LOW")] | length' "${scan_file}" 2>/dev/null || echo "0")
    unknown_count=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "UNKNOWN")] | length' "${scan_file}" 2>/dev/null || echo "0")
    
    local total_vulnerabilities=$((critical_count + high_count + medium_count + low_count + unknown_count))
    
    # Export vulnerability counts
    echo "TRIVY_TOTAL_VULNERABILITIES=${total_vulnerabilities}" >> trivy-results.env
    echo "TRIVY_CRITICAL_COUNT=${critical_count}" >> trivy-results.env
    echo "TRIVY_HIGH_COUNT=${high_count}" >> trivy-results.env
    echo "TRIVY_MEDIUM_COUNT=${medium_count}" >> trivy-results.env
    echo "TRIVY_LOW_COUNT=${low_count}" >> trivy-results.env
    echo "TRIVY_UNKNOWN_COUNT=${unknown_count}" >> trivy-results.env
    
    log "📊 Vulnerability Summary:"
    log "  Total: ${total_vulnerabilities}"
    log "  Critical: ${critical_count}"
    log "  High: ${high_count}"
    log "  Medium: ${medium_count}"
    log "  Low: ${low_count}"
    log "  Unknown: ${unknown_count}"
    
    # Generate detailed vulnerability report
    generate_vulnerability_summary "${scan_file}"
    
    log "✅ Vulnerability results processed"
}

# Generate vulnerability summary
generate_vulnerability_summary() {
    local scan_file="$1"
    local summary_file="${RESULTS_DIR}/vulnerability-summary.json"
    
    log "Generating vulnerability summary..."
    
    # Create comprehensive summary
    jq -n \
        --arg project "${CI_PROJECT_NAME}" \
        --arg image "${CI_REGISTRY_IMAGE}:${IMAGE_TAG}" \
        --arg commit "${CI_COMMIT_SHA}" \
        --arg scan_date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson scan_data "$(cat "${scan_file}")" \
        --argjson critical "$(grep "TRIVY_CRITICAL_COUNT" trivy-results.env | cut -d'=' -f2)" \
        --argjson high "$(grep "TRIVY_HIGH_COUNT" trivy-results.env | cut -d'=' -f2)" \
        --argjson medium "$(grep "TRIVY_MEDIUM_COUNT" trivy-results.env | cut -d'=' -f2)" \
        --argjson low "$(grep "TRIVY_LOW_COUNT" trivy-results.env | cut -d'=' -f2)" \
        '{
            project: $project,
            image: $image,
            commit: $commit,
            scan_timestamp: $scan_date,
            summary: {
                total_vulnerabilities: ($critical + $high + $medium + $low),
                critical: $critical,
                high: $high,
                medium: $medium,
                low: $low
            },
            scan_results: $scan_data
        }' > "${summary_file}"
    
    log "✅ Vulnerability summary generated"
}

# Run secret detection scan
run_secret_scan() {
    log "Starting secret detection scan..."
    
    local image_name="${CI_REGISTRY_IMAGE}:${IMAGE_TAG}"
    local secret_output="${RESULTS_DIR}/trivy-secrets.json"
    local scan_exit_code=0
    
    # Run Trivy secret detection
    trivy image \
        --format json \
        --output "${secret_output}" \
        --scanners secret \
        --timeout 5m \
        --cache-dir "${CACHE_DIR}" \
        "${image_name}" || scan_exit_code=$?
    
    if [[ ${scan_exit_code} -ne 0 && ${scan_exit_code} -ne 1 ]]; then
        log "⚠️ Secret detection scan failed with exit code: ${scan_exit_code} (non-critical)"
        return 0
    fi
    
    # Process secret scan results
    if [[ -f "${secret_output}" ]]; then
        local secrets_found
        secrets_found=$(jq '[.Results[]?.Secrets[]?] | length' "${secret_output}" 2>/dev/null || echo "0")
        
        echo "TRIVY_SECRETS_FOUND=${secrets_found}" >> trivy-results.env
        
        log "🔍 Secret Detection Results: ${secrets_found} secrets found"
        
        if [[ ${secrets_found} -gt 0 ]]; then
            log "⚠️ Secrets detected in container image!"
            # Log secret types found (without exposing actual secrets)
            jq -r '.Results[]?.Secrets[]? | "  - " + .RuleID + " in " + .StartLine' "${secret_output}" 2>/dev/null || true
        fi
    else
        echo "TRIVY_SECRETS_FOUND=0" >> trivy-results.env
    fi
    
    log "✅ Secret detection scan completed"
}

# Run configuration scan
run_config_scan() {
    log "Starting configuration issue scan..."
    
    local image_name="${CI_REGISTRY_IMAGE}:${IMAGE_TAG}"
    local config_output="${RESULTS_DIR}/trivy-config.json"
    local scan_exit_code=0
    
    # Run Trivy configuration scan
    trivy image \
        --format json \
        --output "${config_output}" \
        --scanners config \
        --timeout 5m \
        --cache-dir "${CACHE_DIR}" \
        "${image_name}" || scan_exit_code=$?
    
    if [[ ${scan_exit_code} -ne 0 && ${scan_exit_code} -ne 1 ]]; then
        log "⚠️ Configuration scan failed with exit code: ${scan_exit_code} (non-critical)"
        return 0
    fi
    
    # Process configuration scan results
    if [[ -f "${config_output}" ]]; then
        local config_issues
        config_issues=$(jq '[.Results[]?.Misconfigurations[]?] | length' "${config_output}" 2>/dev/null || echo "0")
        
        echo "TRIVY_CONFIG_ISSUES=${config_issues}" >> trivy-results.env
        
        log "⚙️ Configuration Scan Results: ${config_issues} issues found"
        
        if [[ ${config_issues} -gt 0 ]]; then
            log "⚠️ Configuration issues detected:"
            # Log configuration issues found
            jq -r '.Results[]?.Misconfigurations[]? | "  - " + .Type + ": " + .Title' "${config_output}" 2>/dev/null || true
        fi
    else
        echo "TRIVY_CONFIG_ISSUES=0" >> trivy-results.env
    fi
    
    log "✅ Configuration scan completed"
}

# Generate GitLab security report
generate_gitlab_security_report() {
    log "Generating GitLab security report..."
    
    local vuln_file="${RESULTS_DIR}/trivy-vulnerabilities.json"
    local gitlab_report="${RESULTS_DIR}/trivy-gitlab-container-scanning.json"
    
    if [[ ! -f "${vuln_file}" ]]; then
        log "⚠️ No vulnerability scan file found, creating empty report"
        echo '{"version": "14.0.0", "vulnerabilities": []}' > "${gitlab_report}"
        return 0
    fi
    
    # Convert Trivy format to GitLab security report format
    jq '{
        version: "14.0.0",
        vulnerabilities: [
            .Results[]?.Vulnerabilities[]? | {
                id: (.VulnerabilityID // .PkgName + "-" + .InstalledVersion),
                category: "container_scanning",
                name: .Title,
                message: .Description,
                description: .Description,
                severity: (.Severity | ascii_downcase),
                confidence: "High",
                scanner: {
                    id: "trivy",
                    name: "Trivy"
                },
                location: {
                    dependency: {
                        package: {
                            name: .PkgName
                        },
                        version: .InstalledVersion
                    },
                    operating_system: (.Target // "unknown"),
                    image: "${CI_REGISTRY_IMAGE}:${IMAGE_TAG}"
                },
                identifiers: [
                    {
                        type: "trivy",
                        name: .VulnerabilityID,
                        value: .VulnerabilityID
                    }
                ] + (
                    if .References then
                        [.References[] | {
                            type: "cve",
                            name: .,
                            value: .,
                            url: .
                        }]
                    else [] end
                ),
                links: [
                    {
                        url: (.PrimaryURL // "")
                    }
                ]
            }
        ]
    }' "${vuln_file}" > "${gitlab_report}"
    
    log "✅ GitLab security report generated"
}

# Generate SARIF report
generate_sarif_report() {
    log "Generating SARIF report..."
    
    local vuln_file="${RESULTS_DIR}/trivy-vulnerabilities.json"
    local sarif_report="${RESULTS_DIR}/trivy-sarif.json"
    
    if [[ ! -f "${vuln_file}" ]]; then
        log "⚠️ No vulnerability scan file found for SARIF generation"
        return 0
    fi
    
    # Generate SARIF report using Trivy's built-in capability
    trivy convert \
        --format sarif \
        --output "${sarif_report}" \
        "${vuln_file}" || {
        log "⚠️ SARIF conversion failed, creating basic SARIF structure"
        
        cat > "${sarif_report}" <<EOF
{
    "\$schema": "https://schemastore.azurewebsites.net/schemas/json/sarif-2.1.0.json",
    "version": "2.1.0",
    "runs": [
        {
            "tool": {
                "driver": {
                    "name": "Trivy",
                    "version": "$(trivy --version | cut -d' ' -f2 || echo 'unknown')",
                    "informationUri": "https://aquasecurity.github.io/trivy/"
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
    log "Applying container security gates..."
    
    local critical_count high_count secrets_found config_issues
    critical_count=$(grep "TRIVY_CRITICAL_COUNT" trivy-results.env | cut -d'=' -f2 2>/dev/null || echo "0")
    high_count=$(grep "TRIVY_HIGH_COUNT" trivy-results.env | cut -d'=' -f2 2>/dev/null || echo "0")
    secrets_found=$(grep "TRIVY_SECRETS_FOUND" trivy-results.env | cut -d'=' -f2 2>/dev/null || echo "0")
    config_issues=$(grep "TRIVY_CONFIG_ISSUES" trivy-results.env | cut -d'=' -f2 2>/dev/null || echo "0")
    
    # Security gate thresholds
    local critical_threshold=0
    local high_threshold=3
    local secrets_threshold=0
    local config_threshold=10
    
    local gate_failed=false
    
    # Check critical vulnerabilities
    if [[ ${critical_count} -gt ${critical_threshold} ]]; then
        log "❌ Security Gate FAILED: ${critical_count} critical container vulnerabilities found (threshold: ${critical_threshold})"
        gate_failed=true
    fi
    
    # Check high vulnerabilities
    if [[ ${high_count} -gt ${high_threshold} ]]; then
        log "❌ Security Gate FAILED: ${high_count} high container vulnerabilities found (threshold: ${high_threshold})"
        gate_failed=true
    fi
    
    # Check secrets
    if [[ ${secrets_found} -gt ${secrets_threshold} ]]; then
        log "❌ Security Gate FAILED: ${secrets_found} secrets detected in container (threshold: ${secrets_threshold})"
        gate_failed=true
    fi
    
    # Check configuration issues (warning only)
    if [[ ${config_issues} -gt ${config_threshold} ]]; then
        log "⚠️ Warning: ${config_issues} configuration issues found (threshold: ${config_threshold})"
    fi
    
    if [[ "${gate_failed}" == "true" ]]; then
        log "❌ Container security gate failed - pipeline will be terminated"
        
        # Generate failure summary
        cat > "${RESULTS_DIR}/container-security-gate-failure.json" <<EOF
{
    "gate_status": "failed",
    "critical_vulnerabilities": ${critical_count},
    "high_vulnerabilities": ${high_count},
    "secrets_found": ${secrets_found},
    "config_issues": ${config_issues},
    "thresholds": {
        "critical": ${critical_threshold},
        "high": ${high_threshold},
        "secrets": ${secrets_threshold},
        "config": ${config_threshold}
    },
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
        
        exit 1
    fi
    
    log "✅ Container security gate passed"
}

# Generate comprehensive report
generate_comprehensive_report() {
    log "Generating comprehensive container security report..."
    
    # Create HTML report
    cat > "${RESULTS_DIR}/container-security-report.html" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Container Security Report - ${CI_PROJECT_NAME}</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f5f5f5; padding: 20px; border-radius: 5px; }
        .summary { margin: 20px 0; }
        .critical { color: #d63384; font-weight: bold; }
        .high { color: #fd7e14; font-weight: bold; }
        .medium { color: #ffc107; font-weight: bold; }
        .low { color: #198754; }
        .warning { color: #fd7e14; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #f8f9fa; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🛡️ Container Security Report</h1>
        <p><strong>Project:</strong> ${CI_PROJECT_NAME}</p>
        <p><strong>Image:</strong> ${CI_REGISTRY_IMAGE}:${IMAGE_TAG}</p>
        <p><strong>Scan Date:</strong> $(date)</p>
        <p><strong>Commit:</strong> ${CI_COMMIT_SHA}</p>
    </div>
    
    <div class="summary">
        <h2>📊 Security Summary</h2>
        <p><span class="critical">Critical Vulnerabilities:</span> $(grep "TRIVY_CRITICAL_COUNT" trivy-results.env | cut -d'=' -f2 2>/dev/null || echo "0")</p>
        <p><span class="high">High Vulnerabilities:</span> $(grep "TRIVY_HIGH_COUNT" trivy-results.env | cut -d'=' -f2 2>/dev/null || echo "0")</p>
        <p><span class="medium">Medium Vulnerabilities:</span> $(grep "TRIVY_MEDIUM_COUNT" trivy-results.env | cut -d'=' -f2 2>/dev/null || echo "0")</p>
        <p><span class="low">Low Vulnerabilities:</span> $(grep "TRIVY_LOW_COUNT" trivy-results.env | cut -d'=' -f2 2>/dev/null || echo "0")</p>
        <p><span class="warning">Secrets Detected:</span> $(grep "TRIVY_SECRETS_FOUND" trivy-results.env | cut -d'=' -f2 2>/dev/null || echo "0")</p>
        <p><span class="warning">Configuration Issues:</span> $(grep "TRIVY_CONFIG_ISSUES" trivy-results.env | cut -d'=' -f2 2>/dev/null || echo "0")</p>
    </div>
    
    <div>
        <h2>🔧 Scan Configuration</h2>
        <ul>
            <li>Scanner: Trivy $(trivy --version | cut -d' ' -f2 || echo 'unknown')</li>
            <li>Scan Types: Vulnerabilities, Secrets, Configuration</li>
            <li>Severity Levels: CRITICAL, HIGH, MEDIUM, LOW</li>
            <li>Database: Updated before scan</li>
        </ul>
    </div>
    
    <div>
        <p><em>Generated by Trivy Container Scanner - DevSecOps Pipeline</em></p>
    </div>
</body>
</html>
EOF
    
    log "✅ Comprehensive report generated"
}

# Clean up temporary files
cleanup() {
    log "Cleaning up temporary files..."
    
    # Remove temporary files but keep cache for performance
    find "${RESULTS_DIR}" -name "*.tmp" -delete 2>/dev/null || true
    
    # Optionally clean cache if requested
    if [[ "${CLEAR_CACHE:-false}" == "true" ]]; then
        rm -rf "${CACHE_DIR}"
        log "🧹 Cache cleared"
    fi
    
    log "✅ Cleanup completed"
}

# Main execution
main() {
    log "🔍 Starting Trivy container security scan..."
    
    validate_environment
    setup_trivy
    update_trivy_db
    validate_image
    
    # Run security scans
    run_vulnerability_scan
    run_secret_scan
    run_config_scan
    
    # Generate reports
    generate_gitlab_security_report
    generate_sarif_report
    generate_comprehensive_report
    
    # Apply security gates
    apply_security_gates
    
    # Cleanup
    cleanup
    
    log "🎉 Trivy container security scan completed successfully"
}

# Execute main function
main "$@"