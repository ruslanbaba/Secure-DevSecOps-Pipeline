# Application Deployment Runbook

## Overview
This runbook provides step-by-step procedures for deploying applications through the Secure DevSecOps Pipeline.

## Prerequisites
- Access to GitLab CI/CD
- kubectl access to target cluster
- ArgoCD CLI configured
- Valid deployment manifests

## Deployment Process

### 1. Pre-Deployment Checklist
- [ ] Code has passed all security scans
- [ ] All tests are passing (unit, integration, e2e)
- [ ] Deployment manifests validated
- [ ] Target environment is healthy
- [ ] Rollback plan prepared

### 2. Standard Deployment

#### Via GitOps (Recommended)
```bash
# 1. Update application manifests
git add manifests/
git commit -m "feat: update application to v1.2.3"
git push origin main

# 2. Monitor ArgoCD sync
argocd app sync secure-app
argocd app wait secure-app --health

# 3. Verify deployment
kubectl get pods -n production
kubectl get svc -n production
```

#### Manual Deployment (Emergency Only)
```bash
# 1. Apply manifests directly
kubectl apply -f manifests/ -n production

# 2. Wait for rollout
kubectl rollout status deployment/secure-app -n production

# 3. Verify health
kubectl get pods -n production -l app=secure-app
```

### 3. Deployment Validation

#### Health Checks
```bash
# Check pod status
kubectl get pods -n production -l app=secure-app

# Check service endpoints
kubectl get endpoints -n production

# Check ingress status
kubectl get ingress -n production

# Run smoke tests
./scripts/smoke-tests.sh production
```

#### Security Validation
```bash
# Verify security policies
kubectl auth can-i create pods --as=system:serviceaccount:production:secure-app

# Check network policies
kubectl describe networkpolicy -n production

# Validate RBAC
kubectl auth can-i get secrets --as=system:serviceaccount:production:secure-app
```

### 4. Monitoring Deployment

#### Application Metrics
- Check Grafana dashboard: Application Performance
- Verify SLI/SLO metrics are within targets
- Monitor error rates and response times

#### Infrastructure Metrics
- CPU and memory utilization
- Network traffic patterns
- Storage usage

### 5. Post-Deployment Tasks

#### Update Documentation
- [ ] Update deployment notes
- [ ] Record any configuration changes
- [ ] Update runbooks if procedures changed

#### Communication
- [ ] Notify stakeholders of successful deployment
- [ ] Update status page if applicable
- [ ] Schedule post-deployment review

## Troubleshooting

### Common Issues

#### Deployment Stuck in Pending
```bash
# Check pod events
kubectl describe pod <pod-name> -n production

# Check resource constraints
kubectl top nodes
kubectl describe nodes

# Check scheduling issues
kubectl get events -n production --sort-by='.lastTimestamp'
```

#### Image Pull Errors
```bash
# Check image exists
docker pull <image-name>

# Verify registry credentials
kubectl get secrets -n production

# Check image pull policy
kubectl describe pod <pod-name> -n production
```

#### Health Check Failures
```bash
# Check application logs
kubectl logs -f deployment/secure-app -n production

# Verify health endpoint
kubectl exec -it <pod-name> -n production -- curl localhost:8080/health

# Check service configuration
kubectl describe svc secure-app -n production
```

### Rollback Procedures

#### Immediate Rollback
```bash
# Rollback to previous version
kubectl rollout undo deployment/secure-app -n production

# Monitor rollback progress
kubectl rollout status deployment/secure-app -n production

# Verify rollback success
kubectl get pods -n production -l app=secure-app
```

#### ArgoCD Rollback
```bash
# Find previous revision
argocd app history secure-app

# Rollback to specific revision
argocd app rollback secure-app <revision-id>

# Sync application
argocd app sync secure-app
```

## Emergency Procedures

### Critical Production Issue
1. **Immediate Actions**
   - Scale down problematic deployment: `kubectl scale deployment/secure-app --replicas=0 -n production`
   - Route traffic to healthy instances
   - Activate incident response team

2. **Investigation**
   - Collect logs: `kubectl logs deployment/secure-app -n production --previous`
   - Check metrics in Grafana
   - Review recent changes in Git

3. **Resolution**
   - Apply hotfix if available
   - Rollback to last known good state
   - Scale up healthy deployment

### Security Incident
1. **Containment**
   - Isolate affected pods: `kubectl cordon <node-name>`
   - Block network traffic: Apply network policies
   - Collect forensic data

2. **Assessment**
   - Review security logs
   - Check for privilege escalation
   - Validate image integrity

3. **Recovery**
   - Deploy patched version
   - Rotate compromised secrets
   - Update security policies

## Maintenance Windows

### Planned Maintenance
1. **Preparation** (24 hours before)
   - Notify users of maintenance window
   - Prepare rollback plan
   - Backup current state

2. **Execution**
   - Deploy during low-traffic period
   - Monitor deployment closely
   - Validate all systems post-deployment

3. **Validation**
   - Run full test suite
   - Check all integrations
   - Monitor for 24 hours post-deployment

## Contacts

### Primary Contacts
- **DevOps Team**: devops@company.com
- **Security Team**: security@company.com
- **On-Call Engineer**: +1-555-0123

### Escalation
- **Level 1**: Development Team
- **Level 2**: Platform Team
- **Level 3**: Architecture Team
- **Level 4**: CTO

## Related Documents
- [Scaling Operations Runbook](scaling.md)
- [Security Incident Response](security-incident.md)
- [Backup and Recovery Procedures](backup-recovery.md)
- [Certificate Management](certificate-management.md)

---
**Document Version**: 1.0
**Last Updated**: January 2024
**Next Review**: April 2024