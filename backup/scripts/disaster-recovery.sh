#!/bin/bash

# Disaster Recovery Automation Script
# Handles backup validation, restoration procedures, and DR testing

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VELERO_NAMESPACE="velero"
KUBECTL_CMD="${KUBECTL_CMD:-kubectl}"
VELERO_CMD="${VELERO_CMD:-velero}"
AWS_CLI_CMD="${AWS_CLI_CMD:-aws}"

# DR Configuration
DR_REGION="${DR_REGION:-us-east-1}"
PRIMARY_REGION="${PRIMARY_REGION:-us-west-2}"
DR_CLUSTER_NAME="${DR_CLUSTER_NAME:-devsecops-dr-cluster}"
PRIMARY_CLUSTER_NAME="${PRIMARY_CLUSTER_NAME:-devsecops-primary-cluster}"
BACKUP_BUCKET="${BACKUP_BUCKET:-devsecops-velero-backups}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" >&2
}

# Function to check prerequisites
check_prerequisites() {
    log "${BLUE}Checking disaster recovery prerequisites...${NC}"
    
    # Check if required tools are available
    local missing_tools=()
    
    if ! command -v "${KUBECTL_CMD}" &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v "${VELERO_CMD}" &> /dev/null; then
        missing_tools+=("velero")
    fi
    
    if ! command -v "${AWS_CLI_CMD}" &> /dev/null; then
        missing_tools+=("aws")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log "${RED}❌ Missing required tools: ${missing_tools[*]}${NC}"
        return 1
    fi
    
    # Check if we can connect to the cluster
    if ! "${KUBECTL_CMD}" cluster-info &> /dev/null; then
        log "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
        return 1
    fi
    
    # Check if Velero is installed
    if ! "${KUBECTL_CMD}" get namespace "${VELERO_NAMESPACE}" &> /dev/null; then
        log "${RED}❌ Velero namespace not found. Please install Velero first.${NC}"
        return 1
    fi
    
    log "${GREEN}✅ Prerequisites checked${NC}"
}

# Function to validate backup integrity
validate_backups() {
    log "${BLUE}Validating backup integrity...${NC}"
    
    # Get list of recent backups
    local backups
    backups=$("${VELERO_CMD}" backup get --output json 2>/dev/null | jq -r '.items[] | select(.status.phase == "Completed") | .metadata.name' | head -10)
    
    if [[ -z "${backups}" ]]; then
        log "${RED}❌ No completed backups found${NC}"
        return 1
    fi
    
    local validation_errors=0
    
    echo "${backups}" | while read -r backup_name; do
        if [[ -n "${backup_name}" ]]; then
            log "${YELLOW}Validating backup: ${backup_name}${NC}"
            
            # Get backup details
            local backup_info
            backup_info=$("${VELERO_CMD}" backup describe "${backup_name}" --details --output json 2>/dev/null)
            
            if [[ $? -ne 0 ]]; then
                log "${RED}❌ Failed to get backup details for ${backup_name}${NC}"
                ((validation_errors++))
                continue
            fi
            
            # Check backup status
            local phase
            phase=$(echo "${backup_info}" | jq -r '.status.phase')
            
            if [[ "${phase}" != "Completed" ]]; then
                log "${RED}❌ Backup ${backup_name} is not completed (${phase})${NC}"
                ((validation_errors++))
                continue
            fi
            
            # Check for errors
            local errors
            errors=$(echo "${backup_info}" | jq -r '.status.errors // 0')
            
            if [[ "${errors}" != "0" ]] && [[ "${errors}" != "null" ]]; then
                log "${YELLOW}⚠️  Backup ${backup_name} has ${errors} errors${NC}"
            fi
            
            # Check backup size
            local total_items
            total_items=$(echo "${backup_info}" | jq -r '.status.totalItems // 0')
            
            if [[ "${total_items}" == "0" ]]; then
                log "${RED}❌ Backup ${backup_name} contains no items${NC}"
                ((validation_errors++))
                continue
            fi
            
            log "${GREEN}✅ Backup ${backup_name} validated (${total_items} items)${NC}"
        fi
    done
    
    if [[ ${validation_errors} -eq 0 ]]; then
        log "${GREEN}✅ All backups validated successfully${NC}"
        return 0
    else
        log "${RED}❌ ${validation_errors} backup validation errors found${NC}"
        return 1
    fi
}

# Function to test backup restoration
test_backup_restoration() {
    local backup_name="$1"
    local test_namespace="${2:-dr-test-$(date +%s)}"
    
    log "${BLUE}Testing restoration of backup: ${backup_name}${NC}"
    
    # Create test namespace
    "${KUBECTL_CMD}" create namespace "${test_namespace}" --dry-run=client -o yaml | "${KUBECTL_CMD}" apply -f -
    "${KUBECTL_CMD}" label namespace "${test_namespace}" "disaster-recovery=test" "test-restore=true"
    
    # Create restore with namespace mapping
    local restore_name="test-restore-$(date +%s)"
    
    "${VELERO_CMD}" restore create "${restore_name}" \
        --from-backup "${backup_name}" \
        --namespace-mappings "devsecops-production:${test_namespace},devsecops-staging:${test_namespace}" \
        --include-cluster-resources=false \
        --wait
    
    # Check restore status
    local restore_status
    restore_status=$("${VELERO_CMD}" restore get "${restore_name}" --output json | jq -r '.items[0].status.phase')
    
    if [[ "${restore_status}" == "Completed" ]]; then
        log "${GREEN}✅ Test restoration completed successfully${NC}"
        
        # Verify restored resources
        local restored_resources
        restored_resources=$("${KUBECTL_CMD}" get all -n "${test_namespace}" --no-headers 2>/dev/null | wc -l)
        
        log "${GREEN}✅ Restored ${restored_resources} resources to test namespace${NC}"
        
        # Cleanup test namespace after successful test
        sleep 30  # Give time to verify if needed
        "${KUBECTL_CMD}" delete namespace "${test_namespace}" --ignore-not-found=true
        
        return 0
    else
        log "${RED}❌ Test restoration failed with status: ${restore_status}${NC}"
        
        # Get restore details for debugging
        "${VELERO_CMD}" restore describe "${restore_name}" --details
        
        return 1
    fi
}

# Function to create manual backup
create_manual_backup() {
    local backup_name="$1"
    local namespaces="$2"
    local description="${3:-Manual backup created by DR script}"
    
    log "${BLUE}Creating manual backup: ${backup_name}${NC}"
    
    # Create backup
    "${VELERO_CMD}" backup create "${backup_name}" \
        --include-namespaces "${namespaces}" \
        --include-cluster-resources=true \
        --snapshot-volumes=true \
        --default-volumes-to-restic=false \
        --ttl 168h \
        --wait
    
    # Check backup status
    local backup_status
    backup_status=$("${VELERO_CMD}" backup get "${backup_name}" --output json | jq -r '.items[0].status.phase')
    
    if [[ "${backup_status}" == "Completed" ]]; then
        log "${GREEN}✅ Manual backup created successfully${NC}"
        return 0
    else
        log "${RED}❌ Manual backup failed with status: ${backup_status}${NC}"
        "${VELERO_CMD}" backup describe "${backup_name}" --details
        return 1
    fi
}

# Function to initiate disaster recovery
initiate_disaster_recovery() {
    local backup_name="$1"
    local target_cluster="${2:-${DR_CLUSTER_NAME}}"
    
    log "${BLUE}Initiating disaster recovery to cluster: ${target_cluster}${NC}"
    
    # Switch to DR cluster context
    local current_context
    current_context=$("${KUBECTL_CMD}" config current-context)
    
    if ! "${KUBECTL_CMD}" config use-context "${target_cluster}" 2>/dev/null; then
        log "${RED}❌ Cannot switch to DR cluster context: ${target_cluster}${NC}"
        return 1
    fi
    
    log "${YELLOW}Switched to DR cluster context${NC}"
    
    # Ensure Velero is installed in DR cluster
    if ! "${KUBECTL_CMD}" get namespace "${VELERO_NAMESPACE}" &> /dev/null; then
        log "${RED}❌ Velero not found in DR cluster. Installing...${NC}"
        # Install Velero in DR cluster
        install_velero_dr_cluster
    fi
    
    # Create restore in DR cluster
    local restore_name="dr-restore-$(date +%s)"
    
    "${VELERO_CMD}" restore create "${restore_name}" \
        --from-backup "${backup_name}" \
        --include-cluster-resources=true \
        --wait
    
    # Check restore status
    local restore_status
    restore_status=$("${VELERO_CMD}" restore get "${restore_name}" --output json | jq -r '.items[0].status.phase')
    
    if [[ "${restore_status}" == "Completed" ]]; then
        log "${GREEN}✅ Disaster recovery restoration completed${NC}"
        
        # Verify critical services
        verify_critical_services_dr
        
        return 0
    else
        log "${RED}❌ Disaster recovery restoration failed${NC}"
        "${VELERO_CMD}" restore describe "${restore_name}" --details
        
        # Switch back to original context
        "${KUBECTL_CMD}" config use-context "${current_context}"
        
        return 1
    fi
}

# Function to verify critical services after DR
verify_critical_services_dr() {
    log "${BLUE}Verifying critical services in DR environment...${NC}"
    
    local critical_namespaces=("devsecops-production" "monitoring")
    local verification_errors=0
    
    for namespace in "${critical_namespaces[@]}"; do
        if "${KUBECTL_CMD}" get namespace "${namespace}" &> /dev/null; then
            log "${YELLOW}Checking namespace: ${namespace}${NC}"
            
            # Check deployments
            local deployments
            deployments=$("${KUBECTL_CMD}" get deployments -n "${namespace}" --no-headers 2>/dev/null | awk '{print $1}' || echo "")
            
            if [[ -n "${deployments}" ]]; then
                echo "${deployments}" | while read -r deployment; do
                    if [[ -n "${deployment}" ]]; then
                        local ready_replicas
                        local desired_replicas
                        
                        ready_replicas=$("${KUBECTL_CMD}" get deployment "${deployment}" -n "${namespace}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
                        desired_replicas=$("${KUBECTL_CMD}" get deployment "${deployment}" -n "${namespace}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
                        
                        if [[ "${ready_replicas}" == "${desired_replicas}" ]] && [[ "${desired_replicas}" != "0" ]]; then
                            log "${GREEN}✅ Deployment ${deployment} is healthy (${ready_replicas}/${desired_replicas})${NC}"
                        else
                            log "${RED}❌ Deployment ${deployment} is not healthy (${ready_replicas}/${desired_replicas})${NC}"
                            ((verification_errors++))
                        fi
                    fi
                done
            fi
        else
            log "${RED}❌ Namespace ${namespace} not found${NC}"
            ((verification_errors++))
        fi
    done
    
    # Check ingress and services
    log "${YELLOW}Checking external access...${NC}"
    
    local ingresses
    ingresses=$("${KUBECTL_CMD}" get ingress --all-namespaces --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [[ "${ingresses}" -gt 0 ]]; then
        log "${GREEN}✅ Found ${ingresses} ingress resources${NC}"
    else
        log "${YELLOW}⚠️  No ingress resources found${NC}"
    fi
    
    if [[ ${verification_errors} -eq 0 ]]; then
        log "${GREEN}✅ All critical services verified in DR environment${NC}"
        return 0
    else
        log "${RED}❌ ${verification_errors} service verification errors found${NC}"
        return 1
    fi
}

# Function to install Velero in DR cluster
install_velero_dr_cluster() {
    log "${BLUE}Installing Velero in DR cluster...${NC}"
    
    # Create Velero namespace
    "${KUBECTL_CMD}" create namespace "${VELERO_NAMESPACE}" --dry-run=client -o yaml | "${KUBECTL_CMD}" apply -f -
    
    # Install Velero using the same configuration as primary
    "${VELERO_CMD}" install \
        --provider aws \
        --plugins velero/velero-plugin-for-aws:v1.8.0 \
        --bucket "${BACKUP_BUCKET}" \
        --backup-location-config region="${DR_REGION}" \
        --snapshot-location-config region="${DR_REGION}" \
        --secret-file "${HOME}/.aws/credentials" \
        --use-node-agent \
        --wait
    
    log "${GREEN}✅ Velero installed in DR cluster${NC}"
}

# Function to run DR tests
run_dr_tests() {
    log "${BLUE}Running disaster recovery tests...${NC}"
    
    # Test 1: Validate recent backups
    log "${YELLOW}Test 1: Validating backups...${NC}"
    if ! validate_backups; then
        log "${RED}❌ Backup validation test failed${NC}"
        return 1
    fi
    
    # Test 2: Test restoration to temporary namespace
    log "${YELLOW}Test 2: Testing backup restoration...${NC}"
    local latest_backup
    latest_backup=$("${VELERO_CMD}" backup get --output json | jq -r '.items[] | select(.status.phase == "Completed") | .metadata.name' | head -1)
    
    if [[ -n "${latest_backup}" ]]; then
        if ! test_backup_restoration "${latest_backup}"; then
            log "${RED}❌ Backup restoration test failed${NC}"
            return 1
        fi
    else
        log "${RED}❌ No backups available for restoration test${NC}"
        return 1
    fi
    
    # Test 3: Check DR cluster connectivity (if configured)
    if [[ -n "${DR_CLUSTER_NAME}" ]]; then
        log "${YELLOW}Test 3: Testing DR cluster connectivity...${NC}"
        local current_context
        current_context=$("${KUBECTL_CMD}" config current-context)
        
        if "${KUBECTL_CMD}" config use-context "${DR_CLUSTER_NAME}" 2>/dev/null; then
            log "${GREEN}✅ DR cluster connectivity test passed${NC}"
            "${KUBECTL_CMD}" config use-context "${current_context}"
        else
            log "${YELLOW}⚠️  DR cluster not accessible (expected if not configured)${NC}"
        fi
    fi
    
    log "${GREEN}✅ All DR tests completed successfully${NC}"
}

# Function to show backup status
show_backup_status() {
    log "${BLUE}Backup Status Report${NC}"
    log "==================="
    
    # Recent backups
    log "${YELLOW}Recent Backups:${NC}"
    "${VELERO_CMD}" backup get | head -10
    
    echo ""
    
    # Backup schedules
    log "${YELLOW}Backup Schedules:${NC}"
    "${VELERO_CMD}" schedule get
    
    echo ""
    
    # Storage usage
    if command -v "${AWS_CLI_CMD}" &> /dev/null; then
        log "${YELLOW}Storage Usage:${NC}"
        local bucket_size
        bucket_size=$("${AWS_CLI_CMD}" s3 ls "s3://${BACKUP_BUCKET}" --recursive --summarize 2>/dev/null | grep "Total Size" | awk '{print $3, $4}' || echo "Unable to determine")
        log "Backup bucket size: ${bucket_size}"
    fi
    
    echo ""
    
    # System health
    log "${YELLOW}Velero System Health:${NC}"
    "${KUBECTL_CMD}" get pods -n "${VELERO_NAMESPACE}"
}

# Function to show help
show_help() {
    cat << EOF
Disaster Recovery Automation Script

Usage: $0 <command> [arguments]

Commands:
  check-prereqs                    Check prerequisites
  validate-backups                 Validate backup integrity
  test-restore <backup-name>       Test backup restoration
  create-backup <name> <namespaces> Create manual backup
  initiate-dr <backup-name>        Initiate full disaster recovery
  run-tests                        Run comprehensive DR tests
  status                           Show backup and DR status
  help                             Show this help message

Examples:
  $0 check-prereqs
  $0 validate-backups
  $0 test-restore daily-backup-20240101
  $0 create-backup manual-backup-prod devsecops-production
  $0 initiate-dr daily-backup-20240101
  $0 run-tests
  $0 status

Environment Variables:
  KUBECTL_CMD         - kubectl command (default: kubectl)
  VELERO_CMD          - velero command (default: velero)
  AWS_CLI_CMD         - aws CLI command (default: aws)
  DR_REGION           - DR region (default: us-east-1)
  PRIMARY_REGION      - Primary region (default: us-west-2)
  DR_CLUSTER_NAME     - DR cluster name
  BACKUP_BUCKET       - Backup storage bucket name
EOF
}

# Main script logic
main() {
    case "${1:-help}" in
        check-prereqs)
            check_prerequisites
            ;;
        validate-backups)
            check_prerequisites
            validate_backups
            ;;
        test-restore)
            if [[ $# -lt 2 ]]; then
                log "${RED}❌ Usage: $0 test-restore <backup-name>${NC}"
                exit 1
            fi
            check_prerequisites
            test_backup_restoration "$2" "${3:-}"
            ;;
        create-backup)
            if [[ $# -lt 3 ]]; then
                log "${RED}❌ Usage: $0 create-backup <name> <namespaces>${NC}"
                exit 1
            fi
            check_prerequisites
            create_manual_backup "$2" "$3" "${4:-}"
            ;;
        initiate-dr)
            if [[ $# -lt 2 ]]; then
                log "${RED}❌ Usage: $0 initiate-dr <backup-name>${NC}"
                exit 1
            fi
            check_prerequisites
            initiate_disaster_recovery "$2" "${3:-}"
            ;;
        run-tests)
            check_prerequisites
            run_dr_tests
            ;;
        status)
            check_prerequisites
            show_backup_status
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log "${RED}❌ Unknown command: $1${NC}"
            show_help
            exit 1
            ;;
    esac
}

# Execute main function with all arguments
main "$@"