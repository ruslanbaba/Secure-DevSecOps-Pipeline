# Security Incident Response Runbook

## Overview
This runbook provides procedures for responding to security incidents in the DevSecOps pipeline.

## Incident Classification

### Severity Levels

#### **Critical (P0)**
- Active data breach or unauthorized access
- Ransomware or malware detected
- Complete system compromise
- **Response Time**: Immediate (within 15 minutes)

#### **High (P1)**
- Suspicious activity detected
- Vulnerability exploitation attempt
- Privilege escalation detected
- **Response Time**: Within 1 hour

#### **Medium (P2)**
- Security policy violations
- Failed authentication attempts
- Suspicious network traffic
- **Response Time**: Within 4 hours

#### **Low (P3)**
- Security configuration drift
- Minor compliance issues
- Non-critical vulnerability findings
- **Response Time**: Within 24 hours

## Incident Response Process

### Phase 1: Preparation
- Incident response team contact list updated
- Security tools and monitoring in place
- Forensic tools and procedures ready
- Communication channels established

### Phase 2: Identification
1. **Detection Sources**
   - Security monitoring alerts
   - User reports
   - Automated security scans
   - Third-party security feeds

2. **Initial Assessment**
   ```bash
   # Check security alerts
   kubectl get events --all-namespaces | grep -i security
   
   # Review Falco alerts
   kubectl logs -n falco daemonset/falco
   
   # Check OPA Gatekeeper violations
   kubectl get constraintviolations --all-namespaces
   ```

### Phase 3: Containment

#### Immediate Containment
```bash
# Isolate affected pods
kubectl cordon <affected-node>
kubectl drain <affected-node> --ignore-daemonsets

# Block network traffic
kubectl apply -f security/network-policies/block-all.yaml

# Scale down compromised deployment
kubectl scale deployment/<compromised-app> --replicas=0
```

#### Network Isolation
```bash
# Apply strict network policies
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: incident-isolation
  namespace: <affected-namespace>
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress: []
  egress: []
EOF
```

#### Access Control
```bash
# Revoke suspicious service account permissions
kubectl delete rolebinding <suspicious-binding>

# Rotate secrets
kubectl delete secret <compromised-secret>
kubectl create secret generic <new-secret> --from-literal=...

# Update RBAC policies
kubectl apply -f security/rbac/emergency-lockdown.yaml
```

### Phase 4: Eradication

#### Vulnerability Assessment
```bash
# Scan for vulnerabilities
trivy image <compromised-image>

# Check for malware
clamav-scan /var/lib/containers/

# Validate image integrity
cosign verify <image-signature>
```

#### System Hardening
```bash
# Update security policies
kubectl apply -f security/pod-security-standards/restricted.yaml

# Apply security patches
kubectl patch deployment <app> -p '{"spec":{"template":{"spec":{"containers":[{"name":"app","image":"<patched-image>"}]}}}}'

# Update admission controllers
kubectl apply -f security/opa-gatekeeper/new-policies.yaml
```

### Phase 5: Recovery

#### Service Restoration
```bash
# Deploy clean version
kubectl apply -f manifests/clean-deployment.yaml

# Verify security posture
kubectl auth can-i --list --as=system:serviceaccount:<namespace>:<serviceaccount>

# Restore network connectivity
kubectl delete networkpolicy incident-isolation

# Scale up services
kubectl scale deployment/<app> --replicas=3
```

#### Data Recovery
```bash
# Restore from backup if needed
velero restore create --from-backup <backup-name>

# Verify data integrity
./scripts/data-integrity-check.sh

# Validate application functionality
./scripts/smoke-tests.sh
```

### Phase 6: Lessons Learned
1. **Incident Documentation**
   - Timeline of events
   - Actions taken
   - Impact assessment
   - Root cause analysis

2. **Process Improvement**
   - Update security policies
   - Enhance monitoring rules
   - Improve response procedures

## Security Monitoring

### Real-time Monitoring
```bash
# Falco security events
kubectl logs -f -n falco daemonset/falco | grep CRITICAL

# OPA Gatekeeper violations
kubectl get constraintviolations --watch

# Istio security policies
kubectl logs -f -n istio-system deployment/istiod | grep deny
```

### Log Analysis
```bash
# Check authentication logs
kubectl logs -n kube-system deployment/kube-apiserver | grep authentication

# Review audit logs
kubectl logs -n kube-system deployment/kube-apiserver | grep audit

# Analyze application logs for suspicious activity
kubectl logs deployment/<app> | grep -i "error\|fail\|unauthorized"
```

## Forensic Procedures

### Evidence Collection
```bash
# Capture node state
kubectl describe node <affected-node> > forensics/node-state.txt

# Collect pod information
kubectl get pods -o yaml > forensics/pod-state.yaml

# Export container logs
kubectl logs <pod-name> --previous > forensics/container-logs.txt

# Capture network traffic
tcpdump -i any -w forensics/network-capture.pcap
```

### Memory Dump
```bash
# Create memory dump (if tools available)
kubectl exec -it <pod-name> -- gcore <pid>

# Copy dump for analysis
kubectl cp <pod-name>:/tmp/core.dump ./forensics/
```

## Communication Procedures

### Internal Communication
1. **Immediate Notification** (within 15 minutes)
   - Security team
   - DevOps team
   - On-call manager

2. **Regular Updates** (every hour during active incident)
   - Status updates
   - Actions taken
   - Next steps

### External Communication
1. **Customer Notification** (if customer data affected)
   - Within 2 hours for critical incidents
   - Clear, factual information
   - Steps being taken

2. **Regulatory Notification** (if required)
   - GDPR: Within 72 hours
   - Other regulations as applicable

## Recovery Validation

### Security Checks
```bash
# Verify no backdoors
find /var/lib/containers -name "*.sh" -type f | xargs grep -l "nc\|netcat\|reverse"

# Check for persistence mechanisms
kubectl get cronjobs --all-namespaces

# Validate image signatures
for image in $(kubectl get pods -o jsonpath='{.items[*].spec.containers[*].image}'); do
  cosign verify $image
done
```

### Compliance Validation
```bash
# Run CIS benchmark
kube-bench run --targets node,master

# Check pod security standards
kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.securityContext}{"\n"}{end}'

# Validate RBAC configuration
kubectl auth can-i --list --as=system:serviceaccount:default:default
```

## Tools and Resources

### Security Tools
- **Falco**: Runtime security monitoring
- **OPA Gatekeeper**: Policy enforcement
- **Trivy**: Vulnerability scanning
- **Istio**: Service mesh security
- **ClamAV**: Anti-malware scanning

### Forensic Tools
- **kubectl**: Kubernetes debugging
- **tcpdump**: Network packet capture
- **strace**: System call tracing
- **gdb**: Debugging and memory dumps

### Communication Tools
- **Slack**: #security-incidents channel
- **PagerDuty**: Incident management
- **Email**: security-alerts@company.com

## Incident Templates

### Security Alert Template
```
SECURITY INCIDENT ALERT
Severity: [Critical/High/Medium/Low]
Time: [Timestamp]
Affected Systems: [List]
Initial Assessment: [Brief description]
Actions Taken: [Initial response]
Next Steps: [Planned actions]
Incident Commander: [Name]
```

### Status Update Template
```
INCIDENT STATUS UPDATE
Incident ID: [ID]
Time: [Timestamp]
Current Status: [Status]
Actions Completed: [List]
Ongoing Actions: [List]
Next Update: [Time]
```

## Post-Incident Activities

### Immediate (24 hours)
- [ ] Incident timeline documented
- [ ] All systems restored and validated
- [ ] Security posture verified
- [ ] Stakeholders notified

### Short-term (1 week)
- [ ] Root cause analysis completed
- [ ] Process improvements identified
- [ ] Security controls updated
- [ ] Training needs assessed

### Long-term (1 month)
- [ ] Security architecture review
- [ ] Monitoring enhancements implemented
- [ ] Staff training completed
- [ ] Incident response plan updated

