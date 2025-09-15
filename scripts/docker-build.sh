#!/bin/bash
set -euo pipefail

# Docker Build and Push Script for DevSecOps Pipeline
# This script handles secure container image building with security validations

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_LOG="/tmp/docker-build-$(date +%Y%m%d_%H%M%S).log"

# Default values
IMAGE_NAME="${IMAGE_NAME:-secure-app}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY_URL="${REGISTRY_URL:-}"
DOCKERFILE_PATH="${DOCKERFILE_PATH:-$PROJECT_ROOT/Dockerfile}"
BUILD_CONTEXT="${BUILD_CONTEXT:-$PROJECT_ROOT}"
SECURITY_SCAN="${SECURITY_SCAN:-true}"
PUSH_IMAGE="${PUSH_IMAGE:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$BUILD_LOG"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $*${NC}" | tee -a "$BUILD_LOG"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $*${NC}" | tee -a "$BUILD_LOG"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $*${NC}" | tee -a "$BUILD_LOG"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    
    # Check Dockerfile exists
    if [[ ! -f "$DOCKERFILE_PATH" ]]; then
        log_error "Dockerfile not found at: $DOCKERFILE_PATH"
        exit 1
    fi
    
    # Check Trivy if security scan is enabled
    if [[ "$SECURITY_SCAN" == "true" ]] && ! command -v trivy &> /dev/null; then
        log_warning "Trivy not found. Security scanning will be skipped."
        SECURITY_SCAN="false"
    fi
    
    log_success "Prerequisites check completed"
}

# Function to validate Dockerfile security
validate_dockerfile() {
    log "Validating Dockerfile security..."
    
    local dockerfile="$1"
    local issues=0
    
    # Check for root user
    if grep -q "USER root" "$dockerfile" || ! grep -q "USER " "$dockerfile"; then
        log_warning "Dockerfile may run as root user"
        ((issues++))
    fi
    
    # Check for HEALTHCHECK
    if ! grep -q "HEALTHCHECK" "$dockerfile"; then
        log_warning "Dockerfile missing HEALTHCHECK instruction"
        ((issues++))
    fi
    
    # Check for security labels
    if ! grep -q "LABEL.*security" "$dockerfile"; then
        log_warning "Dockerfile missing security labels"
        ((issues++))
    fi
    
    # Check for latest tag usage
    if grep -q "FROM.*:latest" "$dockerfile"; then
        log_warning "Dockerfile uses 'latest' tag (not recommended for production)"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        log_success "Dockerfile security validation passed"
    else
        log_warning "Dockerfile security validation found $issues potential issues"
    fi
    
    return 0
}

# Function to build Docker image
build_image() {
    log "Building Docker image..."
    
    local full_image_name
    if [[ -n "$REGISTRY_URL" ]]; then
        full_image_name="$REGISTRY_URL/$IMAGE_NAME:$IMAGE_TAG"
    else
        full_image_name="$IMAGE_NAME:$IMAGE_TAG"
    fi
    
    log "Image: $full_image_name"
    log "Dockerfile: $DOCKERFILE_PATH"
    log "Build context: $BUILD_CONTEXT"
    
    # Build with security best practices
    local build_args=(
        "--file" "$DOCKERFILE_PATH"
        "--tag" "$full_image_name"
        "--label" "build.date=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        "--label" "build.version=$IMAGE_TAG"
        "--label" "build.vcs-ref=${CI_COMMIT_SHA:-$(git rev-parse HEAD 2>/dev/null || echo 'unknown')}"
        "--label" "security.scanned=pending"
        "--no-cache"
        "--pull"
        "$BUILD_CONTEXT"
    )
    
    if docker build "${build_args[@]}" 2>&1 | tee -a "$BUILD_LOG"; then
        log_success "Docker image built successfully: $full_image_name"
        echo "$full_image_name" > /tmp/built-image-name.txt
        return 0
    else
        log_error "Docker build failed"
        return 1
    fi
}

# Function to scan image for vulnerabilities
scan_image() {
    local image_name="$1"
    
    if [[ "$SECURITY_SCAN" != "true" ]]; then
        log "Security scanning disabled, skipping..."
        return 0
    fi
    
    log "Scanning image for vulnerabilities: $image_name"
    
    # Create scan results directory
    local scan_dir="/tmp/trivy-scan-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$scan_dir"
    
    # Trivy scan with comprehensive checks
    local scan_result=0
    
    # Vulnerability scan
    log "Running vulnerability scan..."
    if trivy image \
        --format json \
        --output "$scan_dir/vulnerabilities.json" \
        --severity HIGH,CRITICAL \
        --ignore-unfixed \
        "$image_name" 2>&1 | tee -a "$BUILD_LOG"; then
        log_success "Vulnerability scan completed"
    else
        log_error "Vulnerability scan failed"
        scan_result=1
    fi
    
    # Configuration scan
    log "Running configuration scan..."
    if trivy config \
        --format json \
        --output "$scan_dir/config.json" \
        "$DOCKERFILE_PATH" 2>&1 | tee -a "$BUILD_LOG"; then
        log_success "Configuration scan completed"
    else
        log_error "Configuration scan failed"
        scan_result=1
    fi
    
    # Secret scan
    log "Running secret scan..."
    if trivy fs \
        --format json \
        --output "$scan_dir/secrets.json" \
        --scanners secret \
        "$BUILD_CONTEXT" 2>&1 | tee -a "$BUILD_LOG"; then
        log_success "Secret scan completed"
    else
        log_error "Secret scan failed"
        scan_result=1
    fi
    
    # Process scan results
    if [[ $scan_result -eq 0 ]]; then
        process_scan_results "$scan_dir" "$image_name"
    fi
    
    return $scan_result
}

# Function to process scan results
process_scan_results() {
    local scan_dir="$1"
    local image_name="$2"
    
    log "Processing scan results..."
    
    # Count vulnerabilities
    local critical_vulns=0
    local high_vulns=0
    
    if [[ -f "$scan_dir/vulnerabilities.json" ]]; then
        critical_vulns=$(jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL") | .VulnerabilityID' "$scan_dir/vulnerabilities.json" 2>/dev/null | wc -l || echo "0")
        high_vulns=$(jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH") | .VulnerabilityID' "$scan_dir/vulnerabilities.json" 2>/dev/null | wc -l || echo "0")
    fi
    
    log "Scan Results Summary:"
    log "  Critical vulnerabilities: $critical_vulns"
    log "  High vulnerabilities: $high_vulns"
    
    # Security gate enforcement
    local gate_fail=false
    
    if [[ $critical_vulns -gt 0 ]]; then
        log_error "Security gate FAILED: $critical_vulns critical vulnerabilities found"
        gate_fail=true
    fi
    
    if [[ $high_vulns -gt 5 ]]; then
        log_error "Security gate FAILED: $high_vulns high vulnerabilities found (threshold: 5)"
        gate_fail=true
    fi
    
    if [[ "$gate_fail" == "true" ]]; then
        log_error "Image failed security gates. Build should not proceed to production."
        
        # In CI/CD, this would fail the pipeline
        if [[ "${CI:-}" == "true" ]]; then
            exit 1
        fi
    else
        log_success "Image passed security gates"
        
        # Update image label
        docker image tag "$image_name" "${image_name%:*}:security-approved-$(date +%Y%m%d)"
        log_success "Tagged image as security-approved"
    fi
    
    # Generate scan report
    generate_scan_report "$scan_dir" "$image_name"
}

# Function to generate scan report
generate_scan_report() {
    local scan_dir="$1"
    local image_name="$2"
    local report_file="$scan_dir/security-report.md"
    
    log "Generating security report: $report_file"
    
    cat > "$report_file" <<EOF
# Container Security Scan Report

**Image:** \`$image_name\`  
**Scan Date:** $(date)  
**Build Log:** $BUILD_LOG

## Vulnerability Summary

$(if [[ -f "$scan_dir/vulnerabilities.json" ]]; then
    echo "### Vulnerabilities"
    echo "\`\`\`json"
    jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL" or .Severity == "HIGH") | {ID: .VulnerabilityID, Severity: .Severity, Package: .PkgName, Version: .InstalledVersion, FixedVersion: .FixedVersion}' "$scan_dir/vulnerabilities.json" 2>/dev/null | head -20
    echo "\`\`\`"
else
    echo "No vulnerability data available"
fi)

## Configuration Issues

$(if [[ -f "$scan_dir/config.json" ]]; then
    echo "### Configuration Scan Results"
    echo "\`\`\`json"
    jq -r '.Results[]?.Misconfigurations[]? | select(.Severity == "HIGH" or .Severity == "CRITICAL") | {ID: .ID, Severity: .Severity, Message: .Message}' "$scan_dir/config.json" 2>/dev/null | head -10
    echo "\`\`\`"
else
    echo "No configuration issues found"
fi)

## Recommendations

1. Update base image to latest security patches
2. Remove unnecessary packages and dependencies
3. Follow container security best practices
4. Implement runtime security monitoring

## Next Steps

- [ ] Review and remediate critical vulnerabilities
- [ ] Update dependencies to secure versions
- [ ] Re-scan after fixes applied
- [ ] Document any accepted risks

---
*Generated by DevSecOps Pipeline Security Scanner*
EOF
    
    log_success "Security report generated: $report_file"
}

# Function to push image
push_image() {
    local image_name="$1"
    
    if [[ "$PUSH_IMAGE" != "true" ]]; then
        log "Image push disabled, skipping..."
        return 0
    fi
    
    if [[ -z "$REGISTRY_URL" ]]; then
        log_warning "No registry URL provided, skipping push"
        return 0
    fi
    
    log "Pushing image to registry: $image_name"
    
    # Login to registry if credentials provided
    if [[ -n "${REGISTRY_USER:-}" ]] && [[ -n "${REGISTRY_PASSWORD:-}" ]]; then
        log "Logging in to registry..."
        echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY_URL" -u "$REGISTRY_USER" --password-stdin
    fi
    
    # Push image
    if docker push "$image_name" 2>&1 | tee -a "$BUILD_LOG"; then
        log_success "Image pushed successfully: $image_name"
        
        # Also push security-approved tag if it exists
        local approved_tag="${image_name%:*}:security-approved-$(date +%Y%m%d)"
        if docker image inspect "$approved_tag" &>/dev/null; then
            docker push "$approved_tag" 2>&1 | tee -a "$BUILD_LOG"
            log_success "Security-approved image pushed: $approved_tag"
        fi
        
        return 0
    else
        log_error "Image push failed"
        return 1
    fi
}

# Function to cleanup
cleanup() {
    log "Cleaning up temporary files..."
    
    # Remove old build logs (keep last 5)
    find /tmp -name "docker-build-*.log" -type f -mtime +7 -delete 2>/dev/null || true
    
    # Clean up Docker build cache (optional)
    if [[ "${CLEAN_BUILD_CACHE:-false}" == "true" ]]; then
        log "Cleaning Docker build cache..."
        docker builder prune -f
    fi
    
    log_success "Cleanup completed"
}

# Function to show usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Docker Build and Push Script for DevSecOps Pipeline

OPTIONS:
    -i, --image-name NAME       Image name (default: secure-app)
    -t, --tag TAG              Image tag (default: latest)
    -r, --registry URL         Registry URL
    -f, --dockerfile PATH      Dockerfile path (default: ./Dockerfile)
    -c, --context PATH         Build context path (default: .)
    -p, --push                 Push image to registry
    -s, --security-scan        Enable security scanning (default: true)
    --no-security-scan         Disable security scanning
    --clean-cache              Clean Docker build cache after build
    -h, --help                 Show this help message

ENVIRONMENT VARIABLES:
    IMAGE_NAME                 Image name
    IMAGE_TAG                  Image tag
    REGISTRY_URL               Registry URL
    REGISTRY_USER              Registry username
    REGISTRY_PASSWORD          Registry password
    DOCKERFILE_PATH            Dockerfile path
    BUILD_CONTEXT              Build context path
    SECURITY_SCAN              Enable/disable security scanning
    PUSH_IMAGE                 Enable/disable image push
    CLEAN_BUILD_CACHE          Enable/disable build cache cleanup

EXAMPLES:
    # Basic build
    $0 -i myapp -t v1.0.0

    # Build and push with security scan
    $0 -i myapp -t v1.0.0 -r registry.example.com -p

    # Build without security scan
    $0 -i myapp -t v1.0.0 --no-security-scan

    # Build with custom Dockerfile
    $0 -i myapp -t v1.0.0 -f Dockerfile.prod

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--image-name)
                IMAGE_NAME="$2"
                shift 2
                ;;
            -t|--tag)
                IMAGE_TAG="$2"
                shift 2
                ;;
            -r|--registry)
                REGISTRY_URL="$2"
                shift 2
                ;;
            -f|--dockerfile)
                DOCKERFILE_PATH="$2"
                shift 2
                ;;
            -c|--context)
                BUILD_CONTEXT="$2"
                shift 2
                ;;
            -p|--push)
                PUSH_IMAGE="true"
                shift
                ;;
            -s|--security-scan)
                SECURITY_SCAN="true"
                shift
                ;;
            --no-security-scan)
                SECURITY_SCAN="false"
                shift
                ;;
            --clean-cache)
                CLEAN_BUILD_CACHE="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    log "Starting Docker build process..."
    log "Build log: $BUILD_LOG"
    
    # Parse arguments
    parse_args "$@"
    
    # Show configuration
    log "Configuration:"
    log "  Image Name: $IMAGE_NAME"
    log "  Image Tag: $IMAGE_TAG"
    log "  Registry: ${REGISTRY_URL:-'(none)'}"
    log "  Dockerfile: $DOCKERFILE_PATH"
    log "  Build Context: $BUILD_CONTEXT"
    log "  Security Scan: $SECURITY_SCAN"
    log "  Push Image: $PUSH_IMAGE"
    
    # Execute build pipeline
    check_prerequisites
    validate_dockerfile "$DOCKERFILE_PATH"
    
    if build_image; then
        local built_image
        built_image=$(cat /tmp/built-image-name.txt 2>/dev/null || echo "$IMAGE_NAME:$IMAGE_TAG")
        
        if scan_image "$built_image"; then
            if push_image "$built_image"; then
                log_success "Docker build pipeline completed successfully!"
            else
                log_error "Image push failed"
                exit 1
            fi
        else
            log_error "Security scan failed"
            exit 1
        fi
    else
        log_error "Docker build failed"
        exit 1
    fi
    
    cleanup
    log_success "Build process completed. Log available at: $BUILD_LOG"
}

# Error handling
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi