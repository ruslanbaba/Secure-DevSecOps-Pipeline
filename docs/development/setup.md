# Development Setup Guide

## Prerequisites

### Required Software
- **Docker Desktop** (4.15+)
- **kubectl** (1.24+)
- **Helm** (3.10+)
- **Git** (2.30+)
- **Node.js** (18.x LTS)
- **Python** (3.9+)
- **Terraform** (1.5+)
- **ArgoCD CLI** (2.8+)

### Development Tools
- **VS Code** with extensions:
  - Kubernetes
  - Docker
  - GitLab Workflow
  - YAML
  - Terraform
- **Postman** or **Insomnia** for API testing
- **k9s** for Kubernetes cluster management

## Environment Setup

### 1. Clone Repository
```bash
git clone https://github.com/ruslanbaba/Secure-DevSecOps-Pipeline.git
cd Secure-DevSecOps-Pipeline
```

### 2. Install Development Dependencies
```bash
# Install Node.js dependencies for testing
cd tests
npm install

# Install Python dependencies
pip install -r requirements-dev.txt

# Install pre-commit hooks
pre-commit install
```

### 3. Setup Local Kubernetes Cluster

#### Option A: Kind (Recommended for development)
```bash
# Install kind
go install sigs.k8s.io/kind@v0.20.0

# Create cluster with custom configuration
kind create cluster --config=dev/kind-config.yaml --name=devsecops-dev

# Install ingress controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
```

#### Option B: Minikube
```bash
# Start minikube with sufficient resources
minikube start --memory=8192 --cpus=4 --kubernetes-version=v1.28.0

# Enable addons
minikube addons enable ingress
minikube addons enable metrics-server
```

### 4. Setup Development Namespace
```bash
# Create development namespace
kubectl create namespace development

# Apply development RBAC
kubectl apply -f security/rbac/development-rbac.yaml

# Setup service account
kubectl apply -f dev/service-account.yaml
```

### 5. Install Development Tools in Cluster

#### ArgoCD
```bash
# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port forward ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

#### Monitoring Stack (Development)
```bash
# Install Prometheus
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace

# Port forward Grafana
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80
# Default credentials: admin/prom-operator
```

### 6. Configure Development Environment Variables
```bash
# Copy environment template
cp .env.template .env.dev

# Edit with your values
export KUBECONFIG=~/.kube/config
export DOCKER_REGISTRY=localhost:5000
export ENVIRONMENT=development
export DEBUG=true
```

## Development Workflow

### 1. Feature Development
```bash
# Create feature branch
git checkout -b feature/security-enhancement

# Make changes and test locally
make test-local

# Run security scans
make security-scan-local

# Commit with conventional commits
git commit -m "feat: add enhanced RBAC policies"
```

### 2. Local Testing

#### Run Unit Tests
```bash
cd tests
npm test -- --coverage
```

#### Run Integration Tests
```bash
# Start test environment
make test-env-up

# Run integration tests
npm run test:integration

# Cleanup
make test-env-down
```

#### Run Security Tests
```bash
# Container security scan
trivy image local/secure-app:latest

# Kubernetes manifest scan
trivy config manifests/

# Policy validation
conftest test --policy policies/ manifests/
```

### 3. Local Application Deployment
```bash
# Build application image
docker build -t localhost:5000/secure-app:dev .

# Push to local registry
docker push localhost:5000/secure-app:dev

# Deploy to development namespace
kubectl apply -f manifests/development/ -n development

# Verify deployment
kubectl get pods -n development
kubectl logs -f deployment/secure-app -n development
```

### 4. Debug Application Issues

#### Access Application Logs
```bash
# Stream application logs
kubectl logs -f deployment/secure-app -n development

# Get logs from specific container
kubectl logs pod/secure-app-xxx -c security-sidecar -n development

# Save logs to file
kubectl logs deployment/secure-app -n development > debug.log
```

#### Debug Pod Issues
```bash
# Describe pod for events
kubectl describe pod secure-app-xxx -n development

# Execute into pod for debugging
kubectl exec -it pod/secure-app-xxx -n development -- /bin/bash

# Check resource usage
kubectl top pod secure-app-xxx -n development
```

#### Network Debugging
```bash
# Test service connectivity
kubectl exec -it pod/debug-pod -n development -- wget -qO- http://secure-app:8080/health

# Check DNS resolution
kubectl exec -it pod/debug-pod -n development -- nslookup secure-app.development.svc.cluster.local

# Verify network policies
kubectl describe networkpolicy -n development
```

## Development Best Practices

### Code Quality

#### Linting and Formatting
```bash
# Run linters
make lint

# Format code
make format

# Check for security issues
make security-check
```

#### Pre-commit Hooks
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.4.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
  
  - repo: https://github.com/adrienverge/yamllint
    rev: v1.32.0
    hooks:
      - id: yamllint
  
  - repo: https://github.com/bridgecrewio/checkov
    rev: 2.4.9
    hooks:
      - id: checkov
        files: \.tf$
```

### Security in Development

#### Secrets Management
```bash
# Never commit secrets - use sealed secrets for development
kubectl create secret generic app-secrets \
  --from-literal=database-url="postgres://dev:dev@localhost:5432/devdb" \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > manifests/development/sealed-secret.yaml
```

#### Security Scanning in Development
```bash
# Scan container images before commit
trivy image --exit-code 1 --severity HIGH,CRITICAL localhost:5000/secure-app:dev

# Scan Kubernetes manifests
trivy config --exit-code 1 manifests/

# Check for secret leaks
gitleaks detect --source . --verbose
```

### Testing Strategy

#### Test Pyramid
1. **Unit Tests** (70%): Fast, isolated tests
2. **Integration Tests** (20%): Component interaction tests
3. **E2E Tests** (10%): Full user journey tests

#### Test Configuration
```javascript
// jest.config.js
module.exports = {
  testEnvironment: 'node',
  coverageThreshold: {
    global: {
      branches: 80,
      functions: 80,
      lines: 80,
      statements: 80
    }
  },
  testMatch: [
    '<rootDir>/tests/unit/**/*.test.js',
    '<rootDir>/tests/integration/**/*.test.js'
  ]
};
```

### Performance Testing
```bash
# Load testing with k6
k6 run tests/performance/load-test.js

# Memory and CPU profiling
kubectl exec -it pod/secure-app-xxx -- /app/profiler --duration=60s
```

## Debugging Common Issues

### Build Issues
```bash
# Docker build failures
docker build --no-cache -t secure-app:debug .

# Check build context
docker build --progress=plain -t secure-app:debug .

# Multi-stage build debugging
docker build --target=development -t secure-app:dev .
```

### Deployment Issues
```bash
# Check deployment status
kubectl rollout status deployment/secure-app -n development

# View deployment events
kubectl describe deployment secure-app -n development

# Check resource quotas
kubectl describe quota -n development
```

### Network Issues
```bash
# Check service endpoints
kubectl get endpoints -n development

# Test service from within cluster
kubectl run debug-pod --image=curlimages/curl -it --rm -- sh

# Check ingress configuration
kubectl describe ingress secure-app -n development
```

## IDE Configuration

### VS Code Settings
```json
{
  "kubernetes.namespace": "development",
  "yaml.schemas": {
    "https://raw.githubusercontent.com/instrumenta/kubernetes-json-schema/master/v1.18.0-standalone-strict/all.json": "*.k8s.yaml"
  },
  "files.associations": {
    "*.yaml": "yaml",
    "Dockerfile*": "dockerfile"
  }
}
```

### Useful VS Code Extensions
- **Kubernetes**: Kubernetes cluster management
- **Docker**: Container management
- **YAML**: YAML language support
- **GitLab Workflow**: GitLab integration
- **Thunder Client**: API testing
- **Error Lens**: Inline error display

## Documentation

### Code Documentation
```javascript
/**
 * Validates user authentication token
 * @param {string} token - JWT authentication token
 * @param {Object} options - Validation options
 * @returns {Promise<Object>} Decoded token payload
 * @throws {AuthenticationError} When token is invalid
 */
async function validateToken(token, options = {}) {
  // Implementation
}
```

### API Documentation
```yaml
# openapi.yaml
openapi: 3.0.0
info:
  title: Secure App API
  version: 1.0.0
paths:
  /health:
    get:
      summary: Health check endpoint
      responses:
        '200':
          description: Application is healthy
```

## Makefile Targets

```makefile
# Makefile for development tasks

.PHONY: help build test deploy clean

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

build: ## Build application image
	docker build -t localhost:5000/secure-app:dev .

test: ## Run all tests
	cd tests && npm test

test-coverage: ## Run tests with coverage
	cd tests && npm run test:coverage

security-scan: ## Run security scans
	trivy image localhost:5000/secure-app:dev
	trivy config manifests/

deploy-dev: ## Deploy to development namespace
	kubectl apply -f manifests/development/ -n development

clean: ## Clean up development resources
	kubectl delete -f manifests/development/ -n development || true
	docker system prune -f

lint: ## Run linters
	yamllint manifests/
	hadolint Dockerfile
	eslint tests/

format: ## Format code
	prettier --write tests/**/*.js
	terraform fmt -recursive terraform/
```

---
**Document Version**: 1.0
**Last Updated**: January 2024
**Next Review**: April 2024