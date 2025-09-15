#!/bin/bash
set -euo pipefail

# Docker Push Script for DevSecOps Pipeline
# This script handles secure container image pushing with additional security checks

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PUSH_LOG="/tmp/docker-push-$(date +%Y%m%d_%H%M%S).log"

# Default values
IMAGE_NAME="${IMAGE_NAME:-secure-app}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY_URL="${REGISTRY_URL:-}"
REGISTRY_USER="${REGISTRY_USER:-}"
REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-}"
VERIFY_SIGNATURE="${VERIFY_SIGNATURE:-false}"
SIGN_IMAGE="${SIGN_IMAGE:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$PUSH_LOG"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $*${NC}" | tee -a "$PUSH_LOG"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $*${NC}" | tee -a "$PUSH_LOG"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $*${NC}" | tee -a "$PUSH_LOG"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for image push..."
    
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
    
    # Check registry URL
    if [[ -z "$REGISTRY_URL" ]]; then
        log_error "Registry URL not provided"
        exit 1
    fi
    
    # Check credentials
    if [[ -z "$REGISTRY_USER" ]] || [[ -z "$REGISTRY_PASSWORD" ]]; then
        log_warning "Registry credentials not provided. Assuming already logged in."
    fi
    
    # Check if image signing tools are available
    if [[ "$SIGN_IMAGE" == "true" ]]; then
        if ! command -v cosign &> /dev/null; then
            log_warning "Cosign not found. Image signing will be skipped."
            SIGN_IMAGE="false"
        fi
    fi
    
    log_success "Prerequisites check completed"
}

# Function to verify image exists locally
verify_local_image() {
    local image_name="$1"
    
    log "Verifying local image exists: $image_name"
    
    if docker image inspect "$image_name" &>/dev/null; then
        log_success "Local image found: $image_name"
        
        # Show image details
        local image_size
        image_size=$(docker image inspect "$image_name" --format '{{.Size}}' | numfmt --to=iec --suffix=B)
        local created_date
        created_date=$(docker image inspect "$image_name" --format '{{.Created}}' | cut -d'T' -f1)
        
        log "Image details:"
        log "  Size: $image_size"
        log "  Created: $created_date"
        
        return 0
    else
        log_error "Local image not found: $image_name"
        return 1
    fi
}

# Function to login to registry
registry_login() {
    if [[ -n "$REGISTRY_USER" ]] && [[ -n "$REGISTRY_PASSWORD" ]]; then
        log "Logging in to registry: $REGISTRY_URL"
        
        if echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY_URL" -u "$REGISTRY_USER" --password-stdin 2>&1 | tee -a "$PUSH_LOG"; then
            log_success "Successfully logged in to registry"
            return 0
        else
            log_error "Failed to login to registry"
            return 1
        fi
    else
        log "Using existing registry authentication"
        return 0
    fi
}

# Function to tag image for registry
tag_image() {
    local local_image="$1"
    local registry_image="$2"
    
    if [[ "$local_image" != "$registry_image" ]]; then
        log "Tagging image for registry: $local_image -> $registry_image"
        
        if docker tag "$local_image" "$registry_image" 2>&1 | tee -a "$PUSH_LOG"; then
            log_success "Image tagged successfully"
            return 0
        else
            log_error "Failed to tag image"
            return 1
        fi
    else
        log "Image already has correct registry tag"
        return 0
    fi
}

# Function to push image
push_image() {
    local image_name="$1"
    
    log "Pushing image to registry: $image_name"
    
    # Push with progress
    if docker push "$image_name" 2>&1 | tee -a "$PUSH_LOG"; then
        log_success "Image pushed successfully: $image_name"
        
        # Get image digest
        local digest
        digest=$(docker image inspect "$image_name" --format '{{index .RepoDigests 0}}' 2>/dev/null || echo "N/A")
        if [[ "$digest" != "N/A" ]]; then
            log "Image digest: $digest"
            echo "$digest" > /tmp/pushed-image-digest.txt
        fi
        
        return 0
    else
        log_error "Failed to push image: $image_name"
        return 1
    fi
}

# Function to sign image (if enabled)
sign_image() {
    local image_name="$1"
    
    if [[ "$SIGN_IMAGE" != "true" ]]; then
        log "Image signing disabled, skipping..."
        return 0
    fi
    
    log "Signing image: $image_name"
    
    # Check if COSIGN_KEY is provided
    if [[ -z "${COSIGN_KEY:-}" ]]; then
        log_warning "COSIGN_KEY not provided. Using keyless signing."
        
        # Keyless signing
        if cosign sign --yes "$image_name" 2>&1 | tee -a "$PUSH_LOG"; then
            log_success "Image signed successfully (keyless)"
            return 0
        else
            log_error "Failed to sign image (keyless)"
            return 1
        fi
    else
        # Key-based signing
        if cosign sign --key "$COSIGN_KEY" "$image_name" 2>&1 | tee -a "$PUSH_LOG"; then
            log_success "Image signed successfully (key-based)"
            return 0
        else
            log_error "Failed to sign image (key-based)"
            return 1
        fi
    fi
}

# Function to verify image signature (if enabled)
verify_signature() {
    local image_name="$1"
    
    if [[ "$VERIFY_SIGNATURE" != "true" ]]; then
        log "Signature verification disabled, skipping..."
        return 0
    fi
    
    log "Verifying image signature: $image_name"
    
    if [[ -z "${COSIGN_PUBLIC_KEY:-}" ]]; then
        log_warning "COSIGN_PUBLIC_KEY not provided. Using keyless verification."
        
        # Keyless verification
        if cosign verify "$image_name" 2>&1 | tee -a "$PUSH_LOG"; then
            log_success "Image signature verified successfully (keyless)"
            return 0
        else
            log_error "Failed to verify image signature (keyless)"
            return 1
        fi
    else
        # Key-based verification
        if cosign verify --key "$COSIGN_PUBLIC_KEY" "$image_name" 2>&1 | tee -a "$PUSH_LOG"; then
            log_success "Image signature verified successfully (key-based)"
            return 0
        else
            log_error "Failed to verify image signature (key-based)"
            return 1
        fi
    fi
}

# Function to generate SBOM (Software Bill of Materials)
generate_sbom() {
    local image_name="$1"
    
    if ! command -v syft &> /dev/null; then
        log_warning "Syft not found. SBOM generation skipped."
        return 0
    fi
    
    log "Generating SBOM for image: $image_name"
    
    local sbom_file="/tmp/sbom-$(date +%Y%m%d_%H%M%S).json"
    
    if syft "$image_name" -o json > "$sbom_file" 2>&1; then
        log_success "SBOM generated: $sbom_file"
        
        # Optionally push SBOM as attestation
        if [[ "$SIGN_IMAGE" == "true" ]] && command -v cosign &> /dev/null; then
            log "Attaching SBOM as attestation..."
            if cosign attest --predicate "$sbom_file" "$image_name" 2>&1 | tee -a "$PUSH_LOG"; then
                log_success "SBOM attestation attached"
            else
                log_warning "Failed to attach SBOM attestation"
            fi
        fi
        
        return 0
    else
        log_warning "Failed to generate SBOM"
        return 0
    fi
}

# Function to push additional tags
push_additional_tags() {
    local base_image="$1"
    
    # Create additional tags
    local additional_tags=(
        "latest"
        "security-approved-$(date +%Y%m%d)"
        "build-${CI_PIPELINE_ID:-$(date +%s)}"
    )
    
    for tag in "${additional_tags[@]}"; do
        if [[ "$tag" != "$IMAGE_TAG" ]]; then
            local tagged_image="${REGISTRY_URL}/${IMAGE_NAME}:${tag}"
            
            log "Creating additional tag: $tagged_image"
            if docker tag "$base_image" "$tagged_image" && docker push "$tagged_image" 2>&1 | tee -a "$PUSH_LOG"; then
                log_success "Additional tag pushed: $tagged_image"
            else
                log_warning "Failed to push additional tag: $tagged_image"
            fi
        fi
    done
}

# Function to cleanup local images
cleanup_local_images() {
    log "Cleaning up local images..."
    
    # Remove temporary tags
    local images_to_remove=()
    
    # Find images to clean up
    while IFS= read -r image; do
        if [[ "$image" =~ $REGISTRY_URL/$IMAGE_NAME ]]; then
            images_to_remove+=("$image")
        fi
    done < <(docker images --format "{{.Repository}}:{{.Tag}}" | grep "$REGISTRY_URL/$IMAGE_NAME" || true)
    
    # Keep only the main tagged image
    local main_image="$REGISTRY_URL/$IMAGE_NAME:$IMAGE_TAG"
    
    for image in "${images_to_remove[@]}"; do
        if [[ "$image" != "$main_image" ]]; then
            log "Removing local image: $image"
            docker rmi "$image" 2>/dev/null || log_warning "Failed to remove: $image"
        fi
    done
    
    # Clean up build cache if specified
    if [[ "${CLEAN_BUILD_CACHE:-false}" == "true" ]]; then
        log "Cleaning Docker build cache..."
        docker builder prune -f 2>&1 | tee -a "$PUSH_LOG"
    fi
    
    log_success "Local cleanup completed"
}

# Function to generate push report
generate_push_report() {
    local image_name="$1"
    local report_file="/tmp/push-report-$(date +%Y%m%d_%H%M%S).md"
    
    log "Generating push report: $report_file"
    
    cat > "$report_file" <<EOF
# Container Image Push Report

**Image:** \`$image_name\`  
**Push Date:** $(date)  
**Registry:** $REGISTRY_URL  
**Push Log:** $PUSH_LOG

## Push Details

- **Image Name:** $IMAGE_NAME
- **Image Tag:** $IMAGE_TAG
- **Full Image Name:** $image_name
- **Image Digest:** $(cat /tmp/pushed-image-digest.txt 2>/dev/null || echo "N/A")

## Security Features

- **Image Signing:** $SIGN_IMAGE
- **Signature Verification:** $VERIFY_SIGNATURE
- **SBOM Generation:** $(command -v syft &>/dev/null && echo "true" || echo "false")

## Verification Commands

\`\`\`bash
# Pull and verify image
docker pull $image_name

# Verify signature (if signed)
$(if [[ "$SIGN_IMAGE" == "true" ]]; then
    echo "cosign verify $image_name"
fi)

# Inspect image
docker image inspect $image_name
\`\`\`

## Next Steps

1. Deploy image to target environment
2. Monitor for security alerts
3. Update deployment manifests
4. Verify application functionality

---
*Generated by DevSecOps Pipeline Docker Push Script*
EOF
    
    log_success "Push report generated: $report_file"
}

# Function to show usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Docker Push Script for DevSecOps Pipeline

OPTIONS:
    -i, --image-name NAME       Image name (default: secure-app)
    -t, --tag TAG              Image tag (default: latest)
    -r, --registry URL         Registry URL (required)
    -u, --user USERNAME        Registry username
    -p, --password PASSWORD    Registry password
    --sign                     Sign image with Cosign
    --verify                   Verify image signature
    --no-cleanup               Skip local image cleanup
    -h, --help                 Show this help message

ENVIRONMENT VARIABLES:
    IMAGE_NAME                 Image name
    IMAGE_TAG                  Image tag
    REGISTRY_URL               Registry URL
    REGISTRY_USER              Registry username
    REGISTRY_PASSWORD          Registry password
    SIGN_IMAGE                 Enable image signing
    VERIFY_SIGNATURE           Enable signature verification
    COSIGN_KEY                 Cosign private key path
    COSIGN_PUBLIC_KEY          Cosign public key path
    CLEAN_BUILD_CACHE          Clean build cache after push

EXAMPLES:
    # Basic push
    $0 -i myapp -t v1.0.0 -r registry.example.com

    # Push with authentication
    $0 -i myapp -t v1.0.0 -r registry.example.com -u user -p pass

    # Push with signing
    $0 -i myapp -t v1.0.0 -r registry.example.com --sign

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
            -u|--user)
                REGISTRY_USER="$2"
                shift 2
                ;;
            -p|--password)
                REGISTRY_PASSWORD="$2"
                shift 2
                ;;
            --sign)
                SIGN_IMAGE="true"
                shift
                ;;
            --verify)
                VERIFY_SIGNATURE="true"
                shift
                ;;
            --no-cleanup)
                CLEANUP_LOCAL="false"
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
    log "Starting Docker push process..."
    log "Push log: $PUSH_LOG"
    
    # Parse arguments
    parse_args "$@"
    
    # Construct image names
    local local_image="$IMAGE_NAME:$IMAGE_TAG"
    local registry_image="$REGISTRY_URL/$IMAGE_NAME:$IMAGE_TAG"
    
    # Show configuration
    log "Configuration:"
    log "  Local Image: $local_image"
    log "  Registry Image: $registry_image"
    log "  Registry URL: $REGISTRY_URL"
    log "  Sign Image: $SIGN_IMAGE"
    log "  Verify Signature: $VERIFY_SIGNATURE"
    
    # Execute push pipeline
    check_prerequisites
    
    if verify_local_image "$local_image"; then
        if registry_login; then
            if tag_image "$local_image" "$registry_image"; then
                if push_image "$registry_image"; then
                    sign_image "$registry_image"
                    verify_signature "$registry_image"
                    generate_sbom "$registry_image"
                    push_additional_tags "$registry_image"
                    
                    if [[ "${CLEANUP_LOCAL:-true}" == "true" ]]; then
                        cleanup_local_images
                    fi
                    
                    generate_push_report "$registry_image"
                    log_success "Docker push pipeline completed successfully!"
                else
                    log_error "Image push failed"
                    exit 1
                fi
            else
                log_error "Image tagging failed"
                exit 1
            fi
        else
            log_error "Registry login failed"
            exit 1
        fi
    else
        log_error "Local image verification failed"
        exit 1
    fi
    
    log_success "Push process completed. Log available at: $PUSH_LOG"
}

# Error handling
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi