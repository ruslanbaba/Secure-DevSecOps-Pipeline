#!/bin/bash

# GitOps Workflow Management Script
# Automates environment promotion, rollbacks, and GitOps operations

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ARGOCD_NAMESPACE="argocd"
KUBECTL_CMD="${KUBECTL_CMD:-kubectl}"
ARGOCD_CMD="${ARGOCD_CMD:-argocd}"

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
    log "${BLUE}Checking prerequisites...${NC}"
    
    # Check if kubectl is available
    if ! command -v "${KUBECTL_CMD}" &> /dev/null; then
        log "${RED}❌ kubectl is not available${NC}"
        exit 1
    fi
    
    # Check if argocd CLI is available
    if ! command -v "${ARGOCD_CMD}" &> /dev/null; then
        log "${YELLOW}⚠️  ArgoCD CLI is not available. Some features may be limited.${NC}"
    fi
    
    # Check if we can connect to the cluster
    if ! "${KUBECTL_CMD}" cluster-info &> /dev/null; then
        log "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
        exit 1
    fi
    
    log "${GREEN}✅ Prerequisites checked${NC}"
}

# Function to deploy ArgoCD
deploy_argocd() {
    log "${BLUE}Deploying ArgoCD...${NC}"
    
    # Create ArgoCD namespace
    "${KUBECTL_CMD}" create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | "${KUBECTL_CMD}" apply -f -
    
    # Apply ArgoCD installation
    "${KUBECTL_CMD}" apply -n "${ARGOCD_NAMESPACE}" -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    # Wait for ArgoCD to be ready
    log "${YELLOW}Waiting for ArgoCD to be ready...${NC}"
    "${KUBECTL_CMD}" wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n "${ARGOCD_NAMESPACE}" --timeout=300s
    
    # Apply custom configurations
    if [[ -f "${SCRIPT_DIR}/../argocd/config.yaml" ]]; then
        "${KUBECTL_CMD}" apply -f "${SCRIPT_DIR}/../argocd/config.yaml"
        log "${GREEN}✅ Applied ArgoCD configuration${NC}"
    fi
    
    if [[ -f "${SCRIPT_DIR}/../argocd/notifications.yaml" ]]; then
        "${KUBECTL_CMD}" apply -f "${SCRIPT_DIR}/../argocd/notifications.yaml"
        log "${GREEN}✅ Applied ArgoCD notifications configuration${NC}"
    fi
    
    log "${GREEN}✅ ArgoCD deployed successfully${NC}"
}

# Function to setup ArgoCD projects and applications
setup_applications() {
    log "${BLUE}Setting up ArgoCD applications...${NC}"
    
    # Apply project configuration
    if [[ -f "${SCRIPT_DIR}/../argocd/project.yaml" ]]; then
        "${KUBECTL_CMD}" apply -f "${SCRIPT_DIR}/../argocd/project.yaml"
        log "${GREEN}✅ Applied ArgoCD project${NC}"
    fi
    
    # Apply application configurations
    if [[ -f "${SCRIPT_DIR}/../argocd/applications.yaml" ]]; then
        "${KUBECTL_CMD}" apply -f "${SCRIPT_DIR}/../argocd/applications.yaml"
        log "${GREEN}✅ Applied ArgoCD applications${NC}"
    fi
    
    # Apply application sets
    if [[ -f "${SCRIPT_DIR}/../argocd/applicationsets.yaml" ]]; then
        "${KUBECTL_CMD}" apply -f "${SCRIPT_DIR}/../argocd/applicationsets.yaml"
        log "${GREEN}✅ Applied ArgoCD application sets${NC}"
    fi
    
    log "${GREEN}✅ Applications setup completed${NC}"
}

# Function to promote application between environments
promote_application() {
    local app_name="$1"
    local from_env="$2"
    local to_env="$3"
    local image_tag="${4:-latest}"
    
    log "${BLUE}Promoting ${app_name} from ${from_env} to ${to_env}...${NC}"
    
    # Get current image from source environment
    local current_image
    current_image=$("${KUBECTL_CMD}" get deployment "${app_name}" -n "devsecops-${from_env}" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "")
    
    if [[ -z "${current_image}" ]]; then
        log "${RED}❌ Could not find ${app_name} deployment in ${from_env} environment${NC}"
        return 1
    fi
    
    log "${YELLOW}Current image in ${from_env}: ${current_image}${NC}"
    
    # Update the target environment overlay
    local overlay_path="${REPO_ROOT}/k8s/overlays/${to_env}"
    local kustomization_file="${overlay_path}/kustomization.yaml"
    
    if [[ ! -f "${kustomization_file}" ]]; then
        log "${RED}❌ Kustomization file not found: ${kustomization_file}${NC}"
        return 1
    fi
    
    # Update image in kustomization.yaml
    if grep -q "newTag:" "${kustomization_file}"; then
        sed -i.bak "s/newTag:.*/newTag: ${image_tag}/" "${kustomization_file}"
    else
        # Add images section if it doesn't exist
        cat >> "${kustomization_file}" << EOF

images:
- name: ${app_name}
  newTag: ${image_tag}
EOF
    fi
    
    # Commit and push changes
    cd "${REPO_ROOT}"
    git add "${kustomization_file}"
    git commit -m "Promote ${app_name} to ${to_env}: ${image_tag}"
    git push origin main
    
    log "${GREEN}✅ Promoted ${app_name} to ${to_env} environment${NC}"
    
    # Trigger ArgoCD sync if CLI is available
    if command -v "${ARGOCD_CMD}" &> /dev/null; then
        "${ARGOCD_CMD}" app sync "${to_env}-devsecops-app" || true
        log "${GREEN}✅ Triggered ArgoCD sync${NC}"
    fi
}

# Function to rollback application
rollback_application() {
    local app_name="$1"
    local environment="$2"
    local revision="${3:-HEAD~1}"
    
    log "${BLUE}Rolling back ${app_name} in ${environment} to ${revision}...${NC}"
    
    if command -v "${ARGOCD_CMD}" &> /dev/null; then
        # Use ArgoCD CLI for rollback
        "${ARGOCD_CMD}" app rollback "${environment}-devsecops-app" "${revision}"
        log "${GREEN}✅ Rollback initiated via ArgoCD${NC}"
    else
        # Manual rollback via git
        cd "${REPO_ROOT}"
        local overlay_path="k8s/overlays/${environment}"
        
        # Reset to previous commit
        git checkout "${revision}" -- "${overlay_path}"
        git add "${overlay_path}"
        git commit -m "Rollback ${app_name} in ${environment} to ${revision}"
        git push origin main
        
        log "${GREEN}✅ Rollback committed to git${NC}"
    fi
}

# Function to check application health
check_application_health() {
    local app_name="$1"
    local environment="$2"
    
    log "${BLUE}Checking health of ${app_name} in ${environment}...${NC}"
    
    local namespace="devsecops-${environment}"
    
    # Check deployment status
    local deployment_status
    deployment_status=$("${KUBECTL_CMD}" get deployment "${app_name}" -n "${namespace}" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "Unknown")
    
    if [[ "${deployment_status}" == "True" ]]; then
        log "${GREEN}✅ Deployment is healthy${NC}"
    else
        log "${RED}❌ Deployment is not healthy${NC}"
        return 1
    fi
    
    # Check pod status
    local ready_pods
    local total_pods
    ready_pods=$("${KUBECTL_CMD}" get deployment "${app_name}" -n "${namespace}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    total_pods=$("${KUBECTL_CMD}" get deployment "${app_name}" -n "${namespace}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [[ "${ready_pods}" == "${total_pods}" ]] && [[ "${total_pods}" != "0" ]]; then
        log "${GREEN}✅ All pods are ready (${ready_pods}/${total_pods})${NC}"
    else
        log "${RED}❌ Pods not ready (${ready_pods}/${total_pods})${NC}"
        return 1
    fi
    
    # Check if ArgoCD application is synced
    if command -v "${ARGOCD_CMD}" &> /dev/null; then
        local sync_status
        sync_status=$("${ARGOCD_CMD}" app get "${environment}-devsecops-app" -o json | jq -r '.status.sync.status' 2>/dev/null || echo "Unknown")
        
        if [[ "${sync_status}" == "Synced" ]]; then
            log "${GREEN}✅ ArgoCD application is synced${NC}"
        else
            log "${YELLOW}⚠️  ArgoCD application sync status: ${sync_status}${NC}"
        fi
    fi
    
    return 0
}

# Function to create preview environment
create_preview_environment() {
    local pr_number="$1"
    local git_ref="$2"
    
    log "${BLUE}Creating preview environment for PR #${pr_number}...${NC}"
    
    local namespace="pr-${pr_number}-preview"
    
    # Create namespace
    "${KUBECTL_CMD}" create namespace "${namespace}" --dry-run=client -o yaml | "${KUBECTL_CMD}" apply -f -
    
    # Label namespace for easier management
    "${KUBECTL_CMD}" label namespace "${namespace}" "preview=true" "pr-number=${pr_number}" --overwrite
    
    # Create ArgoCD application for preview
    cat << EOF | "${KUBECTL_CMD}" apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: pr-${pr_number}-preview
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    preview: "true"
    pr-number: "${pr_number}"
spec:
  project: devsecops-project
  source:
    repoURL: https://github.com/ruslanbaba/Secure-DevSecOps-Pipeline
    targetRevision: ${git_ref}
    path: k8s/overlays/development
    kustomize:
      namePrefix: pr-${pr_number}-
  destination:
    server: https://kubernetes.default.svc
    namespace: ${namespace}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
EOF
    
    log "${GREEN}✅ Preview environment created for PR #${pr_number}${NC}"
    
    # Wait for deployment to be ready
    sleep 10
    "${KUBECTL_CMD}" wait --for=condition=Ready pod -l app=secure-app -n "${namespace}" --timeout=300s || true
    
    # Get service URL
    local service_url
    service_url=$("${KUBECTL_CMD}" get service "pr-${pr_number}-secure-app" -n "${namespace}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
    
    log "${GREEN}✅ Preview environment URL: http://${service_url}${NC}"
}

# Function to cleanup preview environment
cleanup_preview_environment() {
    local pr_number="$1"
    
    log "${BLUE}Cleaning up preview environment for PR #${pr_number}...${NC}"
    
    local namespace="pr-${pr_number}-preview"
    local app_name="pr-${pr_number}-preview"
    
    # Delete ArgoCD application
    "${KUBECTL_CMD}" delete application "${app_name}" -n "${ARGOCD_NAMESPACE}" --ignore-not-found=true
    
    # Delete namespace
    "${KUBECTL_CMD}" delete namespace "${namespace}" --ignore-not-found=true
    
    log "${GREEN}✅ Preview environment cleaned up for PR #${pr_number}${NC}"
}

# Function to sync all applications
sync_all_applications() {
    log "${BLUE}Syncing all applications...${NC}"
    
    if command -v "${ARGOCD_CMD}" &> /dev/null; then
        # Get all applications in the project
        local apps
        apps=$("${ARGOCD_CMD}" app list -p devsecops-project -o name 2>/dev/null || echo "")
        
        if [[ -n "${apps}" ]]; then
            echo "${apps}" | while read -r app; do
                if [[ -n "${app}" ]]; then
                    log "${YELLOW}Syncing ${app}...${NC}"
                    "${ARGOCD_CMD}" app sync "${app}" || true
                fi
            done
        else
            log "${YELLOW}No applications found to sync${NC}"
        fi
    else
        log "${YELLOW}ArgoCD CLI not available. Manual sync required.${NC}"
    fi
    
    log "${GREEN}✅ Application sync completed${NC}"
}

# Function to get ArgoCD admin password
get_argocd_password() {
    log "${BLUE}Getting ArgoCD admin password...${NC}"
    
    local password
    password=$("${KUBECTL_CMD}" get secret argocd-initial-admin-secret -n "${ARGOCD_NAMESPACE}" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")
    
    if [[ -n "${password}" ]]; then
        log "${GREEN}ArgoCD admin password: ${password}${NC}"
    else
        log "${RED}❌ Could not retrieve ArgoCD admin password${NC}"
        return 1
    fi
}

# Function to show help
show_help() {
    cat << EOF
GitOps Workflow Management Script

Usage: $0 <command> [arguments]

Commands:
  check-prereqs                           Check prerequisites
  deploy-argocd                           Deploy ArgoCD
  setup-apps                              Setup ArgoCD applications
  promote <app> <from-env> <to-env> [tag] Promote application between environments
  rollback <app> <env> [revision]         Rollback application
  health <app> <env>                      Check application health
  preview-create <pr-number> <git-ref>    Create preview environment
  preview-cleanup <pr-number>             Cleanup preview environment
  sync-all                                Sync all applications
  get-password                            Get ArgoCD admin password
  help                                    Show this help message

Examples:
  $0 deploy-argocd
  $0 setup-apps
  $0 promote secure-app staging production v1.2.3
  $0 rollback secure-app production HEAD~1
  $0 health secure-app production
  $0 preview-create 123 feature/new-feature
  $0 preview-cleanup 123
  $0 sync-all
  $0 get-password

Environment Variables:
  KUBECTL_CMD    - kubectl command (default: kubectl)
  ARGOCD_CMD     - argocd command (default: argocd)
EOF
}

# Main script logic
main() {
    case "${1:-help}" in
        check-prereqs)
            check_prerequisites
            ;;
        deploy-argocd)
            check_prerequisites
            deploy_argocd
            ;;
        setup-apps)
            check_prerequisites
            setup_applications
            ;;
        promote)
            if [[ $# -lt 4 ]]; then
                log "${RED}❌ Usage: $0 promote <app> <from-env> <to-env> [tag]${NC}"
                exit 1
            fi
            check_prerequisites
            promote_application "$2" "$3" "$4" "${5:-latest}"
            ;;
        rollback)
            if [[ $# -lt 3 ]]; then
                log "${RED}❌ Usage: $0 rollback <app> <env> [revision]${NC}"
                exit 1
            fi
            check_prerequisites
            rollback_application "$2" "$3" "${4:-HEAD~1}"
            ;;
        health)
            if [[ $# -lt 3 ]]; then
                log "${RED}❌ Usage: $0 health <app> <env>${NC}"
                exit 1
            fi
            check_prerequisites
            check_application_health "$2" "$3"
            ;;
        preview-create)
            if [[ $# -lt 3 ]]; then
                log "${RED}❌ Usage: $0 preview-create <pr-number> <git-ref>${NC}"
                exit 1
            fi
            check_prerequisites
            create_preview_environment "$2" "$3"
            ;;
        preview-cleanup)
            if [[ $# -lt 2 ]]; then
                log "${RED}❌ Usage: $0 preview-cleanup <pr-number>${NC}"
                exit 1
            fi
            check_prerequisites
            cleanup_preview_environment "$2"
            ;;
        sync-all)
            check_prerequisites
            sync_all_applications
            ;;
        get-password)
            check_prerequisites
            get_argocd_password
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