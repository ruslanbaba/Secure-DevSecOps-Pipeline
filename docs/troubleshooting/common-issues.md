# Troubleshooting Guide

## Common Issues and Solutions

### CI/CD Pipeline Issues

#### **Pipeline Fails at Security Scanning Stage**

**Symptoms:**
- Build fails during security scan step
- High/critical vulnerabilities detected
- Scanner timeout errors

**Diagnostic Steps:**
```bash
# Check scanner logs
gitlab-ci-multi-runner logs

# Review security scan results
cat security-scan-results.json | jq '.vulnerabilities[] | select(.severity == "HIGH")'

# Verify scanner configuration
docker run --rm trivy config
```

**Solutions:**
1. **For vulnerability findings:**
   ```bash
   # Update dependencies
   npm audit fix
   # or
   pip install --upgrade package-name
   
   # Add exemptions (if justified)
   echo "CVE-2023-12345" >> .trivyignore
   ```

2. **For scanner timeouts:**
   ```yaml
   # Increase timeout in .gitlab-ci.yml
   security_scan:
     timeout: 30m
     variables:
       TRIVY_TIMEOUT: "20m"
   ```

#### **Deployment Stuck in Pending State**

**Symptoms:**
- Pods remain in Pending state
- Deployment never completes
- Resource allocation errors

**Diagnostic Steps:**
```bash
# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check node resources
kubectl top nodes
kubectl describe nodes

# Check resource quotas
kubectl describe quota -n <namespace>
```

**Solutions:**
1. **Insufficient resources:**
   ```bash
   # Scale down other workloads temporarily
   kubectl scale deployment/non-critical-app --replicas=0
   
   # Add more nodes to cluster
   aws eks update-nodegroup-config --cluster-name <cluster> --nodegroup-name <nodegroup> --scaling-config minSize=2,maxSize=10,desiredSize=5
   ```

2. **Resource quota exceeded:**
   ```bash
   # Increase resource quota
   kubectl patch resourcequota myquota --patch='{"spec":{"hard":{"requests.cpu":"4","requests.memory":"8Gi"}}}'
   ```

### Security Issues

#### **Pod Security Policy Violations**

**Symptoms:**
- Pod creation fails with security policy errors
- Admission webhook denials
- OPA Gatekeeper constraint violations

**Diagnostic Steps:**
```bash
# Check OPA Gatekeeper violations
kubectl get constraintviolations --all-namespaces

# Review admission controller logs
kubectl logs -n gatekeeper-system deployment/gatekeeper-controller-manager

# Check pod security context
kubectl describe pod <pod-name> -o yaml | grep -A 20 securityContext
```

**Solutions:**
1. **Fix security context:**
   ```yaml
   # Update deployment manifest
   spec:
     securityContext:
       runAsNonRoot: true
       runAsUser: 1000
       fsGroup: 2000
     containers:
     - name: app
       securityContext:
         allowPrivilegeEscalation: false
         readOnlyRootFilesystem: true
         capabilities:
           drop:
           - ALL
   ```

2. **Update OPA policies:**
   ```bash
   # Review and update constraint template
   kubectl edit constrainttemplate requiredlabels
   
   # Apply updated policies
   kubectl apply -f security/opa-gatekeeper/
   ```

#### **RBAC Permission Denied**

**Symptoms:**
- kubectl commands fail with "forbidden" errors
- Service account cannot access resources
- API server authorization failures

**Diagnostic Steps:**
```bash
# Check current permissions
kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<namespace>:<serviceaccount>

# Review RBAC policies
kubectl describe rolebinding -n <namespace>
kubectl describe clusterrolebinding

# Check service account configuration
kubectl describe serviceaccount <name> -n <namespace>
```

**Solutions:**
1. **Grant required permissions:**
   ```yaml
   # Create role binding
   apiVersion: rbac.authorization.k8s.io/v1
   kind: RoleBinding
   metadata:
     name: app-access
     namespace: production
   subjects:
   - kind: ServiceAccount
     name: app-service-account
     namespace: production
   roleRef:
     kind: Role
     name: app-role
     apiGroup: rbac.authorization.k8s.io
   ```

2. **Fix service account token:**
   ```bash
   # Recreate service account token
   kubectl delete secret <sa-token-secret>
   kubectl patch serviceaccount <sa-name> -p '{"secrets": []}'
   ```

### Network and Connectivity Issues

#### **Service Discovery Failures**

**Symptoms:**
- Services cannot reach each other
- DNS resolution failures
- Connection timeouts

**Diagnostic Steps:**
```bash
# Test DNS resolution
kubectl exec -it <pod-name> -- nslookup <service-name>.<namespace>.svc.cluster.local

# Check service endpoints
kubectl get endpoints -n <namespace>

# Verify network policies
kubectl describe networkpolicy -n <namespace>

# Test connectivity
kubectl exec -it <pod-name> -- curl <service-name>:<port>/health
```

**Solutions:**
1. **Fix DNS issues:**
   ```bash
   # Restart CoreDNS
   kubectl rollout restart deployment/coredns -n kube-system
   
   # Check CoreDNS configuration
   kubectl get configmap coredns -n kube-system -o yaml
   ```

2. **Update network policies:**
   ```yaml
   # Allow communication between services
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: allow-app-communication
   spec:
     podSelector:
       matchLabels:
         app: frontend
     egress:
     - to:
       - podSelector:
           matchLabels:
             app: backend
       ports:
       - protocol: TCP
         port: 8080
   ```

#### **Ingress Controller Issues**

**Symptoms:**
- External traffic cannot reach services
- SSL/TLS certificate errors
- 502/504 gateway errors

**Diagnostic Steps:**
```bash
# Check ingress controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# Verify ingress configuration
kubectl describe ingress <ingress-name> -n <namespace>

# Check certificate status
kubectl describe certificate <cert-name> -n <namespace>

# Test endpoint directly
curl -I http://<ingress-ip>/<path>
```

**Solutions:**
1. **Fix ingress configuration:**
   ```yaml
   # Update ingress with correct annotations
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     annotations:
       nginx.ingress.kubernetes.io/rewrite-target: /
       cert-manager.io/cluster-issuer: "letsencrypt-prod"
   spec:
     tls:
     - hosts:
       - app.example.com
       secretName: app-tls
   ```

2. **Renew certificates:**
   ```bash
   # Force certificate renewal
   kubectl delete certificate <cert-name> -n <namespace>
   kubectl apply -f ingress/certificate.yaml
   ```

### Performance Issues

#### **High Memory Usage**

**Symptoms:**
- Pods getting OOMKilled
- Node memory pressure
- Slow application response

**Diagnostic Steps:**
```bash
# Check memory usage
kubectl top pods --all-namespaces
kubectl top nodes

# Review pod resource limits
kubectl describe pod <pod-name> | grep -A 5 -B 5 Limits

# Check memory events
kubectl get events --sort-by='.lastTimestamp' | grep -i memory
```

**Solutions:**
1. **Adjust resource limits:**
   ```yaml
   # Update deployment resource limits
   spec:
     containers:
     - name: app
       resources:
         limits:
           memory: "2Gi"
           cpu: "1000m"
         requests:
           memory: "1Gi"
           cpu: "500m"
   ```

2. **Optimize application:**
   ```bash
   # Profile memory usage
   kubectl exec -it <pod-name> -- /app/profiler --memory

   # Review application logs for memory leaks
   kubectl logs <pod-name> | grep -i "memory\|heap\|garbage"
   ```

#### **Slow Application Performance**

**Symptoms:**
- High response times
- Request timeouts
- CPU throttling

**Diagnostic Steps:**
```bash
# Check application metrics
curl http://<app-url>/metrics

# Review resource utilization
kubectl top pods -n <namespace>

# Check application logs
kubectl logs -f deployment/<app-name> -n <namespace>

# Profile application performance
kubectl exec -it <pod-name> -- /app/profiler --cpu
```

**Solutions:**
1. **Scale application:**
   ```bash
   # Horizontal scaling
   kubectl scale deployment/<app-name> --replicas=5
   
   # Configure HPA
   kubectl autoscale deployment <app-name> --cpu-percent=70 --min=2 --max=10
   ```

2. **Optimize configuration:**
   ```yaml
   # Update application configuration
   env:
   - name: JAVA_OPTS
     value: "-Xmx1g -XX:+UseG1GC"
   - name: CONNECTION_POOL_SIZE
     value: "20"
   ```

### Storage Issues

#### **Persistent Volume Mount Failures**

**Symptoms:**
- Pods fail to start with volume mount errors
- Storage class not found
- Insufficient storage capacity

**Diagnostic Steps:**
```bash
# Check PV and PVC status
kubectl get pv,pvc --all-namespaces

# Describe failed PVC
kubectl describe pvc <pvc-name> -n <namespace>

# Check storage class
kubectl describe storageclass <storage-class>

# Review volume events
kubectl get events --sort-by='.lastTimestamp' | grep -i volume
```

**Solutions:**
1. **Fix PVC configuration:**
   ```yaml
   # Update PVC with correct storage class
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: app-storage
   spec:
     accessModes:
       - ReadWriteOnce
     storageClassName: gp3
     resources:
       requests:
         storage: 10Gi
   ```

2. **Provision additional storage:**
   ```bash
   # Create new storage class if needed
   kubectl apply -f storage/storage-class.yaml
   
   # Expand existing PVC (if supported)
   kubectl patch pvc <pvc-name> -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
   ```

### Monitoring and Observability Issues

#### **Missing Metrics or Logs**

**Symptoms:**
- Grafana dashboards show no data
- Prometheus targets down
- Missing application logs

**Diagnostic Steps:**
```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Visit http://localhost:9090/targets

# Verify service monitors
kubectl get servicemonitor -n monitoring

# Check log collection
kubectl logs -n monitoring daemonset/fluent-bit

# Verify metric endpoints
kubectl exec -it <pod-name> -- curl localhost:8080/metrics
```

**Solutions:**
1. **Fix Prometheus configuration:**
   ```yaml
   # Update ServiceMonitor
   apiVersion: monitoring.coreos.com/v1
   kind: ServiceMonitor
   metadata:
     name: app-metrics
   spec:
     selector:
       matchLabels:
         app: myapp
     endpoints:
     - port: metrics
       path: /metrics
   ```

2. **Restart monitoring components:**
   ```bash
   # Restart Prometheus
   kubectl rollout restart statefulset/prometheus-server -n monitoring
   
   # Restart log collection
   kubectl rollout restart daemonset/fluent-bit -n monitoring
   ```

## Emergency Procedures

### Complete System Recovery

1. **Assessment Phase:**
   ```bash
   # Check cluster health
   kubectl get nodes
   kubectl get pods --all-namespaces
   kubectl cluster-info
   ```

2. **Recovery Phase:**
   ```bash
   # Restore from backup
   velero restore create --from-backup <latest-backup>
   
   # Verify restore
   kubectl get pods --all-namespaces
   
   # Run health checks
   ./scripts/health-check.sh
   ```

### Data Recovery

1. **Database Recovery:**
   ```bash
   # Stop application
   kubectl scale deployment/app --replicas=0
   
   # Restore database
   velero restore create --from-backup database-backup-20240115
   
   # Verify data integrity
   ./scripts/db-integrity-check.sh
   
   # Restart application
   kubectl scale deployment/app --replicas=3
   ```

## Diagnostic Scripts

### Health Check Script
```bash
#!/bin/bash
# health-check.sh

echo "=== Cluster Health Check ==="
kubectl get nodes
kubectl get pods --all-namespaces | grep -v Running
kubectl top nodes
kubectl top pods --all-namespaces

echo "=== Security Status ==="
kubectl get constraintviolations --all-namespaces
kubectl get networkpolicies --all-namespaces

echo "=== Application Status ==="
for app in frontend backend database; do
  echo "Checking $app..."
  kubectl get deployment/$app -o jsonpath='{.status.readyReplicas}/{.status.replicas}'
  echo
done
```

### Log Collection Script
```bash
#!/bin/bash
# collect-logs.sh

NAMESPACE=${1:-production}
OUTPUT_DIR="./logs/$(date +%Y%m%d-%H%M%S)"

mkdir -p $OUTPUT_DIR

echo "Collecting logs for namespace: $NAMESPACE"

# Collect pod logs
for pod in $(kubectl get pods -n $NAMESPACE -o name); do
  kubectl logs $pod -n $NAMESPACE > $OUTPUT_DIR/${pod##*/}.log
done

# Collect events
kubectl get events -n $NAMESPACE > $OUTPUT_DIR/events.log

# Collect resource status
kubectl get all -n $NAMESPACE -o yaml > $OUTPUT_DIR/resources.yaml

echo "Logs collected in: $OUTPUT_DIR"
```

## Reference

### Useful Commands
```bash
# Quick status check
kubectl get pods --all-namespaces | grep -v Running

# Resource usage
kubectl top nodes
kubectl top pods --all-namespaces --sort-by=memory

# Events
kubectl get events --sort-by='.lastTimestamp' | tail -20

# Debug pod
kubectl describe pod <pod-name>
kubectl logs <pod-name> --previous

# Network debugging
kubectl exec -it <pod-name> -- nslookup kubernetes.default
kubectl exec -it <pod-name> -- wget -qO- http://service-name:port
```

### Important Files and Locations
- **Configuration**: `/etc/kubernetes/`
- **Logs**: `/var/log/containers/`
- **Certificates**: `/etc/kubernetes/pki/`
- **Service Account Tokens**: `/var/run/secrets/kubernetes.io/serviceaccount/`

---
**Document Version**: 1.0
**Last Updated**: January 2024
**Next Review**: April 2024