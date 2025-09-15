# Implementation Guide

## Prerequisites

### Required Tools and Services

- **GitLab Instance**: GitLab Premium/Ultimate for advanced security features
- **Kubernetes Cluster**: v1.24+ with RBAC enabled
- **Container Registry**: Secure container registry with vulnerability scanning
- **Security Tools Access**:
  - Checkmarx CxSAST license and API access
  - Snyk account with API token
  - Trivy scanner (open source)
  - OPA Conftest (open source)

### Environment Setup

#### 1. GitLab Configuration

```bash
# GitLab Runner registration (requires admin access)
gitlab-runner register \
  --url "${GITLAB_URL}" \
  --registration-token "${REGISTRATION_TOKEN}" \
  --executor docker \
  --docker-image alpine:latest \
  --description "DevSecOps Pipeline Runner" \
  --tag-list "devsecops,security,kubernetes"
```

#### 2. Kubernetes Cluster Setup

```yaml
# namespace-devsecops.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: devsecops-pipeline
  labels:
    security.policy/enforce: "strict"
    compliance.framework: "cis-k8s"
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pipeline-deployer
  namespace: devsecops-pipeline
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pipeline-deployer
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
- apiGroups: ["networking.k8s.io"]
  resources: ["networkpolicies"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
```

### GitLab CI/CD Variables Configuration

#### Required Variables (Protected & Masked)

```bash
# Security Tool API Keys
CHECKMARX_URL="https://your-checkmarx-instance.com"
CHECKMARX_USERNAME="service-account"
CHECKMARX_PASSWORD="secure-password"
SNYK_TOKEN="snyk-api-token"

# Container Registry
CI_REGISTRY="your-registry.com"
CI_REGISTRY_USER="registry-user"
CI_REGISTRY_PASSWORD="registry-password"

# Kubernetes
KUBE_CONFIG="base64-encoded-kubeconfig"
KUBE_NAMESPACE="devsecops-pipeline"

# Monitoring and Alerting
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
PROMETHEUS_URL="https://prometheus.monitoring.svc.cluster.local"
```

### Step-by-Step Implementation

#### Phase 1: Basic Pipeline Setup

1. **Import Project Structure**
   ```bash
   git clone <this-repository>
   cd secure-devsecops-pipeline
   ```

2. **Configure Pipeline Variables**
   - Navigate to GitLab Project → Settings → CI/CD → Variables
   - Add all required variables from the list above
   - Ensure sensitive variables are masked and protected

3. **Validate Pipeline Syntax**
   ```bash
   # Use GitLab CI Lint tool
   curl --header "PRIVATE-TOKEN: <your_access_token>" \
        "https://gitlab.example.com/api/v4/ci/lint" \
        --header "Content-Type: application/json" \
        --data '{"content": "$(cat .gitlab-ci.yml)"}'
   ```

#### Phase 2: Security Tool Integration

1. **Checkmarx SAST Configuration**
   - Verify Checkmarx server connectivity
   - Create project in Checkmarx portal
   - Configure scan presets and engine configurations

2. **Snyk SCA Setup**
   - Authenticate Snyk CLI with token
   - Configure organization and project settings
   - Set vulnerability thresholds

3. **Trivy Container Scanning**
   - Configure Trivy database updates
   - Set CVE severity thresholds
   - Configure ignore policies for false positives

#### Phase 3: Policy as Code Implementation

1. **OPA Conftest Policies**
   - Review and customize Kubernetes policies
   - Test policies against sample manifests
   - Configure policy violation handling

2. **Kubernetes RBAC**
   - Apply service accounts and role bindings
   - Validate least privilege access
   - Configure network policies

#### Phase 4: Monitoring and Observability

1. **Prometheus Metrics**
   - Configure pipeline metrics collection
   - Set up security scan result metrics
   - Configure alerting rules

2. **Grafana Dashboards**
   - Import pre-built security dashboards
   - Configure data sources
   - Set up notification channels

### Testing and Validation

#### Security Gate Testing

```bash
# Test SAST gate with intentionally vulnerable code
echo 'password = "hardcoded123"' > test-vuln.py
git add test-vuln.py && git commit -m "Test SAST detection"
git push origin feature/test-sast

# Test container security gate
docker build -t test-image:vuln -f Dockerfile.vulnerable .
docker push ${CI_REGISTRY}/test-image:vuln

# Test policy validation
kubectl apply --dry-run=client -f k8s/invalid-manifest.yaml
```

#### Pipeline Validation Checklist

- [ ] SAST scan completes and reports vulnerabilities
- [ ] SCA scan identifies dependency vulnerabilities
- [ ] Container scan detects image vulnerabilities
- [ ] Policy validation catches non-compliant manifests
- [ ] Security gates properly fail pipeline on critical findings
- [ ] Deployment succeeds with compliant configurations
- [ ] Monitoring and alerting function correctly

### Troubleshooting Common Issues

#### Pipeline Failures

1. **SAST Scan Timeout**
   ```yaml
   # Increase timeout in .gitlab-ci.yml
   checkmarx-sast:
     timeout: 2h
     retry:
       max: 2
       when: runner_system_failure
   ```

2. **Container Registry Authentication**
   ```bash
   # Verify registry credentials
   docker login ${CI_REGISTRY} -u ${CI_REGISTRY_USER} -p ${CI_REGISTRY_PASSWORD}
   ```

3. **Kubernetes Deployment Issues**
   ```bash
   # Check RBAC permissions
   kubectl auth can-i create deployments --namespace=${KUBE_NAMESPACE}
   ```

### Performance Optimization

#### Parallel Execution
- Run security scans in parallel where possible
- Use GitLab's `needs` keyword for dependency optimization
- Implement intelligent caching for dependencies

#### Resource Management
- Configure appropriate resource limits for scan jobs
- Use shared runners efficiently
- Implement job prioritization for critical security scans

### Security Best Practices

1. **Credential Management**
   - Use GitLab masked and protected variables
   - Rotate API keys regularly
   - Implement least privilege access

2. **Pipeline Security**
   - Validate all external inputs
   - Use official and verified container images
   - Implement audit logging for all pipeline activities

3. **Compliance Validation**
   - Regular compliance audits
   - Automated compliance reporting
   - Continuous policy updates