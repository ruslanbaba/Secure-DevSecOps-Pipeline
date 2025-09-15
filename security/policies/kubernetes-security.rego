# Security Policies for Kubernetes Resources
# Implements CIS Kubernetes Benchmark, NIST, and enterprise security standards

package kubernetes.security

import rego.v1

# Default deny policy
default allow = false

# Allow based on compliant configurations
allow if {
    not deny[_]
}

# Collect all denial reasons
deny contains msg if {
    some rule
    violation := data.kubernetes.security[rule]
    violation.deny[msg]
}

# =============================================================================
# Container Security Policies
# =============================================================================

# Deny containers running as root
deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"]
    container := input.spec.template.spec.containers[_]
    container.securityContext.runAsUser == 0
    msg := sprintf("Container '%s' is running as root user (UID 0)", [container.name])
}

deny[msg] if {
    input.kind == "Pod"
    container := input.spec.containers[_]
    container.securityContext.runAsUser == 0
    msg := sprintf("Container '%s' is running as root user (UID 0)", [container.name])
}

# Require non-root security context
deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"]
    container := input.spec.template.spec.containers[_]
    not container.securityContext.runAsNonRoot == true
    msg := sprintf("Container '%s' must set runAsNonRoot to true", [container.name])
}

deny[msg] if {
    input.kind == "Pod"
    container := input.spec.containers[_]
    not container.securityContext.runAsNonRoot == true
    msg := sprintf("Container '%s' must set runAsNonRoot to true", [container.name])
}

# Deny privileged containers
deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"]
    container := input.spec.template.spec.containers[_]
    container.securityContext.privileged == true
    msg := sprintf("Container '%s' is running in privileged mode", [container.name])
}

deny[msg] if {
    input.kind == "Pod"
    container := input.spec.containers[_]
    container.securityContext.privileged == true
    msg := sprintf("Container '%s' is running in privileged mode", [container.name])
}

# Deny containers with allowPrivilegeEscalation
deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"]
    container := input.spec.template.spec.containers[_]
    container.securityContext.allowPrivilegeEscalation == true
    msg := sprintf("Container '%s' allows privilege escalation", [container.name])
}

deny[msg] if {
    input.kind == "Pod"
    container := input.spec.containers[_]
    container.securityContext.allowPrivilegeEscalation == true
    msg := sprintf("Container '%s' allows privilege escalation", [container.name])
}

# Require readOnlyRootFilesystem
deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"]
    container := input.spec.template.spec.containers[_]
    not container.securityContext.readOnlyRootFilesystem == true
    msg := sprintf("Container '%s' must have readOnlyRootFilesystem set to true", [container.name])
}

deny[msg] if {
    input.kind == "Pod"
    container := input.spec.containers[_]
    not container.securityContext.readOnlyRootFilesystem == true
    msg := sprintf("Container '%s' must have readOnlyRootFilesystem set to true", [container.name])
}

# =============================================================================
# Resource Management Policies
# =============================================================================

# Require CPU limits
deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"]
    container := input.spec.template.spec.containers[_]
    not container.resources.limits.cpu
    msg := sprintf("Container '%s' must specify CPU limits", [container.name])
}

deny[msg] if {
    input.kind == "Pod"
    container := input.spec.containers[_]
    not container.resources.limits.cpu
    msg := sprintf("Container '%s' must specify CPU limits", [container.name])
}

# Require memory limits
deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"]
    container := input.spec.template.spec.containers[_]
    not container.resources.limits.memory
    msg := sprintf("Container '%s' must specify memory limits", [container.name])
}

deny[msg] if {
    input.kind == "Pod"
    container := input.spec.containers[_]
    not container.resources.limits.memory
    msg := sprintf("Container '%s' must specify memory limits", [container.name])
}

# Require CPU requests
deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"]
    container := input.spec.template.spec.containers[_]
    not container.resources.requests.cpu
    msg := sprintf("Container '%s' must specify CPU requests", [container.name])
}

deny[msg] if {
    input.kind == "Pod"
    container := input.spec.containers[_]
    not container.resources.requests.cpu
    msg := sprintf("Container '%s' must specify CPU requests", [container.name])
}

# Require memory requests
deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"]
    container := input.spec.template.spec.containers[_]
    not container.resources.requests.memory
    msg := sprintf("Container '%s' must specify memory requests", [container.name])
}

deny[msg] if {
    input.kind == "Pod"
    container := input.spec.containers[_]
    not container.resources.requests.memory
    msg := sprintf("Container '%s' must specify memory requests", [container.name])
}

# =============================================================================
# Network Security Policies
# =============================================================================

# Require specific labels for network policy enforcement
deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet"]
    not input.metadata.labels["app"]
    msg := "Resource must have 'app' label for network policy enforcement"
}

deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet"]
    not input.metadata.labels["version"]
    msg := "Resource must have 'version' label for network policy enforcement"
}

deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet"]
    not input.metadata.labels["component"]
    msg := "Resource must have 'component' label for network policy enforcement"
}

# Deny hostNetwork usage
deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"]
    input.spec.template.spec.hostNetwork == true
    msg := "hostNetwork is not allowed"
}

deny[msg] if {
    input.kind == "Pod"
    input.spec.hostNetwork == true
    msg := "hostNetwork is not allowed"
}

# Deny hostPID usage
deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"]
    input.spec.template.spec.hostPID == true
    msg := "hostPID is not allowed"
}

deny[msg] if {
    input.kind == "Pod"
    input.spec.hostPID == true
    msg := "hostPID is not allowed"
}

# Deny hostIPC usage
deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"]
    input.spec.template.spec.hostIPC == true
    msg := "hostIPC is not allowed"
}

deny[msg] if {
    input.kind == "Pod"
    input.spec.hostIPC == true
    msg := "hostIPC is not allowed"
}

# =============================================================================
# Image Security Policies
# =============================================================================

# Allowed image registries
allowed_registries := [
    "docker.io/library",
    "gcr.io",
    "quay.io",
    "registry.redhat.io",
    "your-secure-registry.com"
]

# Deny images from untrusted registries
deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"]
    container := input.spec.template.spec.containers[_]
    not image_from_allowed_registry(container.image)
    msg := sprintf("Container '%s' uses image from untrusted registry: %s", [container.name, container.image])
}

deny[msg] if {
    input.kind == "Pod"
    container := input.spec.containers[_]
    not image_from_allowed_registry(container.image)
    msg := sprintf("Container '%s' uses image from untrusted registry: %s", [container.name, container.image])
}

# Helper function to check allowed registries
image_from_allowed_registry(image) if {
    some registry in allowed_registries
    startswith(image, registry)
}

# Deny latest tag usage
deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"]
    container := input.spec.template.spec.containers[_]
    endswith(container.image, ":latest")
    msg := sprintf("Container '%s' uses 'latest' tag which is not allowed", [container.name])
}

deny[msg] if {
    input.kind == "Pod"
    container := input.spec.containers[_]
    endswith(container.image, ":latest")
    msg := sprintf("Container '%s' uses 'latest' tag which is not allowed", [container.name])
}

# Deny images without explicit tags
deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"]
    container := input.spec.template.spec.containers[_]
    not contains(container.image, ":")
    msg := sprintf("Container '%s' must specify explicit image tag", [container.name])
}

deny[msg] if {
    input.kind == "Pod"
    container := input.spec.containers[_]
    not contains(container.image, ":")
    msg := sprintf("Container '%s' must specify explicit image tag", [container.name])
}

# =============================================================================
# Service Security Policies
# =============================================================================

# Deny NodePort services in production
deny[msg] if {
    input.kind == "Service"
    input.spec.type == "NodePort"
    input.metadata.namespace != "kube-system"
    msg := "NodePort services are not allowed outside kube-system namespace"
}

# Require LoadBalancer services to have specific annotations
deny[msg] if {
    input.kind == "Service"
    input.spec.type == "LoadBalancer"
    not input.metadata.annotations["service.beta.kubernetes.io/aws-load-balancer-ssl-cert"]
    not input.metadata.annotations["service.beta.kubernetes.io/aws-load-balancer-backend-protocol"]
    msg := "LoadBalancer services must have SSL/TLS configuration annotations"
}

# =============================================================================
# Pod Security Standards (PSS) Compliance
# =============================================================================

# Require Pod Security Standard labels
deny[msg] if {
    input.kind == "Namespace"
    not input.metadata.labels["pod-security.kubernetes.io/enforce"]
    msg := "Namespace must have pod-security.kubernetes.io/enforce label"
}

deny[msg] if {
    input.kind == "Namespace"
    not input.metadata.labels["pod-security.kubernetes.io/audit"]
    msg := "Namespace must have pod-security.kubernetes.io/audit label"
}

deny[msg] if {
    input.kind == "Namespace"
    not input.metadata.labels["pod-security.kubernetes.io/warn"]
    msg := "Namespace must have pod-security.kubernetes.io/warn label"
}

# Enforce restricted Pod Security Standard
deny[msg] if {
    input.kind == "Namespace"
    input.metadata.labels["pod-security.kubernetes.io/enforce"] != "restricted"
    input.metadata.name != "kube-system"
    input.metadata.name != "kube-public"
    input.metadata.name != "kube-node-lease"
    msg := "Namespace must enforce 'restricted' Pod Security Standard"
}

# =============================================================================
# RBAC Security Policies
# =============================================================================

# Deny cluster-admin binding to users
deny[msg] if {
    input.kind == "ClusterRoleBinding"
    input.roleRef.name == "cluster-admin"
    subject := input.subjects[_]
    subject.kind == "User"
    msg := sprintf("ClusterRoleBinding grants cluster-admin to user '%s' which is not allowed", [subject.name])
}

# Deny overly permissive RoleBindings
deny[msg] if {
    input.kind in ["RoleBinding", "ClusterRoleBinding"]
    input.roleRef.name in ["admin", "edit"]
    subject := input.subjects[_]
    subject.kind == "ServiceAccount"
    subject.namespace != input.metadata.namespace
    msg := "Cross-namespace ServiceAccount bindings are not allowed"
}

# =============================================================================
# Data Protection Policies
# =============================================================================

# Require encryption for persistent volumes
deny[msg] if {
    input.kind == "PersistentVolume"
    not input.metadata.annotations["encrypted"]
    msg := "PersistentVolume must be encrypted (add 'encrypted' annotation)"
}

# Require secrets to be mounted as volumes, not environment variables
deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"]
    container := input.spec.template.spec.containers[_]
    env := container.env[_]
    env.valueFrom.secretKeyRef
    msg := sprintf("Container '%s' mounts secret as environment variable, use volume mount instead", [container.name])
}

deny[msg] if {
    input.kind == "Pod"
    container := input.spec.containers[_]
    env := container.env[_]
    env.valueFrom.secretKeyRef
    msg := sprintf("Container '%s' mounts secret as environment variable, use volume mount instead", [container.name])
}

# =============================================================================
# Compliance and Auditing
# =============================================================================

# Require specific labels for compliance tracking
required_labels := ["app", "version", "component", "managed-by", "environment"]

deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet", "Service"]
    label := required_labels[_]
    not input.metadata.labels[label]
    msg := sprintf("Resource must have '%s' label for compliance tracking", [label])
}

# Require annotations for audit trail
deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet"]
    not input.metadata.annotations["security.policy/reviewed-by"]
    msg := "Resource must have 'security.policy/reviewed-by' annotation"
}

deny[msg] if {
    input.kind in ["Pod", "Deployment", "StatefulSet", "DaemonSet"]
    not input.metadata.annotations["security.policy/review-date"]
    msg := "Resource must have 'security.policy/review-date' annotation"
}

# =============================================================================
# Ingress Security Policies
# =============================================================================

# Require TLS for Ingress
deny[msg] if {
    input.kind == "Ingress"
    count(input.spec.tls) == 0
    msg := "Ingress must have TLS configuration"
}

# Require specific TLS annotations
deny[msg] if {
    input.kind == "Ingress"
    not input.metadata.annotations["kubernetes.io/tls-acme"]
    not input.metadata.annotations["cert-manager.io/cluster-issuer"]
    msg := "Ingress must have TLS certificate management annotations"
}

# Deny HTTP-only Ingress
deny[msg] if {
    input.kind == "Ingress"
    input.metadata.annotations["kubernetes.io/ingress.allow-http"] == "true"
    msg := "HTTP-only Ingress is not allowed, HTTPS must be enforced"
}

# =============================================================================
# Helper Functions
# =============================================================================

# Check if container has security context
has_security_context(container) if {
    container.securityContext
}

# Check if resource has required labels
has_required_labels(resource) if {
    count([label | label := required_labels[_]; resource.metadata.labels[label]]) == count(required_labels)
}

# Check if image tag is semantically versioned
is_semantic_version(tag) if {
    regex.match(`^v?[0-9]+\.[0-9]+\.[0-9]+`, tag)
}