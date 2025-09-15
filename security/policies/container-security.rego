# Container Image Security Policies
# Focuses on container image security and Dockerfile best practices

package container.security

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
    violation := data.container.security[rule]
    violation.deny[msg]
}

# =============================================================================
# Dockerfile Security Policies
# =============================================================================

# Deny running as root in Dockerfile
deny[msg] if {
    input.kind == "dockerfile"
    instruction := input.instructions[_]
    instruction.cmd == "user"
    instruction.value == "root"
    msg := "Dockerfile must not run as root user"
}

deny[msg] if {
    input.kind == "dockerfile"
    instruction := input.instructions[_]
    instruction.cmd == "user"
    instruction.value == "0"
    msg := "Dockerfile must not run as root user (UID 0)"
}

# Require USER instruction in Dockerfile
deny[msg] if {
    input.kind == "dockerfile"
    not has_user_instruction
    msg := "Dockerfile must include USER instruction to run as non-root"
}

has_user_instruction if {
    instruction := input.instructions[_]
    instruction.cmd == "user"
    instruction.value != "root"
    instruction.value != "0"
}

# Deny COPY/ADD with overly permissive permissions
deny[msg] if {
    input.kind == "dockerfile"
    instruction := input.instructions[_]
    instruction.cmd in ["copy", "add"]
    contains(instruction.flags, "--chown=root:root")
    msg := "COPY/ADD should not set root ownership"
}

# Require HEALTHCHECK in Dockerfile
deny[msg] if {
    input.kind == "dockerfile"
    not has_healthcheck
    msg := "Dockerfile must include HEALTHCHECK instruction"
}

has_healthcheck if {
    instruction := input.instructions[_]
    instruction.cmd == "healthcheck"
}

# Deny hardcoded secrets in Dockerfile
secrets_patterns := [
    "password",
    "passwd",
    "secret",
    "token",
    "key",
    "api_key",
    "apikey",
    "auth",
    "credential"
]

deny[msg] if {
    input.kind == "dockerfile"
    instruction := input.instructions[_]
    instruction.cmd in ["env", "arg"]
    pattern := secrets_patterns[_]
    contains(lower(instruction.value), pattern)
    msg := sprintf("Dockerfile contains potential hardcoded secret in %s instruction", [upper(instruction.cmd)])
}

# Deny sudo installation
deny[msg] if {
    input.kind == "dockerfile"
    instruction := input.instructions[_]
    instruction.cmd == "run"
    contains(instruction.value, "sudo")
    msg := "Dockerfile must not install sudo"
}

# Require explicit package versions
deny[msg] if {
    input.kind == "dockerfile"
    instruction := input.instructions[_]
    instruction.cmd == "run"
    contains(instruction.value, "apt-get install")
    not contains(instruction.value, "=")
    msg := "Package installations must specify explicit versions"
}

deny[msg] if {
    input.kind == "dockerfile"
    instruction := input.instructions[_]
    instruction.cmd == "run"
    contains(instruction.value, "yum install")
    not contains(instruction.value, "-")
    msg := "Package installations must specify explicit versions"
}

# =============================================================================
# Base Image Security Policies
# =============================================================================

# Allowed base images
allowed_base_images := [
    "alpine:",
    "debian:",
    "ubuntu:",
    "node:lts-alpine",
    "python:slim",
    "openjdk:slim",
    "nginx:alpine",
    "redis:alpine",
    "postgres:alpine",
    "gcr.io/distroless/"
]

deny[msg] if {
    input.kind == "dockerfile"
    from_instruction := input.instructions[_]
    from_instruction.cmd == "from"
    not is_allowed_base_image(from_instruction.value)
    msg := sprintf("Base image '%s' is not from approved list", [from_instruction.value])
}

is_allowed_base_image(image) if {
    some allowed in allowed_base_images
    startswith(image, allowed)
}

# Deny latest tag in base images
deny[msg] if {
    input.kind == "dockerfile"
    from_instruction := input.instructions[_]
    from_instruction.cmd == "from"
    endswith(from_instruction.value, ":latest")
    msg := "Base image must not use 'latest' tag"
}

# Require specific tags for base images
deny[msg] if {
    input.kind == "dockerfile"
    from_instruction := input.instructions[_]
    from_instruction.cmd == "from"
    not contains(from_instruction.value, ":")
    msg := "Base image must specify explicit tag"
}

# =============================================================================
# Multi-stage Build Security
# =============================================================================

# Require multi-stage builds for compiled languages
compiled_language_indicators := [
    "gcc",
    "g++",
    "make",
    "cmake",
    "mvn",
    "gradle",
    "go build",
    "cargo build",
    "npm run build",
    "yarn build"
]

deny[msg] if {
    input.kind == "dockerfile"
    has_compilation_stage
    not has_multistage_build
    msg := "Dockerfile with compilation steps must use multi-stage builds"
}

has_compilation_stage if {
    instruction := input.instructions[_]
    instruction.cmd == "run"
    indicator := compiled_language_indicators[_]
    contains(instruction.value, indicator)
}

has_multistage_build if {
    count([from | from := input.instructions[_]; from.cmd == "from"]) > 1
}

# =============================================================================
# Layer Optimization Policies
# =============================================================================

# Minimize layers by combining RUN instructions
deny[msg] if {
    input.kind == "dockerfile"
    run_count := count([run | run := input.instructions[_]; run.cmd == "run"])
    run_count > 5
    msg := "Too many RUN instructions, combine them to minimize layers"
}

# Require cleanup in package installation layers
deny[msg] if {
    input.kind == "dockerfile"
    instruction := input.instructions[_]
    instruction.cmd == "run"
    contains(instruction.value, "apt-get install")
    not contains(instruction.value, "apt-get clean")
    not contains(instruction.value, "rm -rf /var/lib/apt/lists/*")
    msg := "apt-get install must include cleanup commands"
}

deny[msg] if {
    input.kind == "dockerfile"
    instruction := input.instructions[_]
    instruction.cmd == "run"
    contains(instruction.value, "yum install")
    not contains(instruction.value, "yum clean all")
    msg := "yum install must include cleanup commands"
}

# =============================================================================
# File Permission Security
# =============================================================================

# Deny overly permissive file permissions
deny[msg] if {
    input.kind == "dockerfile"
    instruction := input.instructions[_]
    instruction.cmd == "run"
    contains(instruction.value, "chmod 777")
    msg := "chmod 777 is not allowed, use more restrictive permissions"
}

deny[msg] if {
    input.kind == "dockerfile"
    instruction := input.instructions[_]
    instruction.cmd == "run"
    contains(instruction.value, "chmod -R 777")
    msg := "chmod -R 777 is not allowed, use more restrictive permissions"
}

# Require secure permissions for sensitive files
deny[msg] if {
    input.kind == "dockerfile"
    instruction := input.instructions[_]
    instruction.cmd == "copy"
    contains(instruction.value, ".key")
    not contains(instruction.flags, "--chmod=600")
    msg := "Private keys must be copied with secure permissions (600)"
}

deny[msg] if {
    input.kind == "dockerfile"
    instruction := input.instructions[_]
    instruction.cmd == "copy"
    contains(instruction.value, ".pem")
    not contains(instruction.flags, "--chmod=600")
    msg := "Certificate files must be copied with secure permissions (600)"
}

# =============================================================================
# Network Security Policies
# =============================================================================

# Limit exposed ports
allowed_ports := [80, 443, 8080, 8443, 3000, 5000, 9000]

deny[msg] if {
    input.kind == "dockerfile"
    instruction := input.instructions[_]
    instruction.cmd == "expose"
    port := to_number(instruction.value)
    not port in allowed_ports
    msg := sprintf("Port %d is not in the allowed ports list", [port])
}

# Deny privileged ports (< 1024) unless specifically allowed
deny[msg] if {
    input.kind == "dockerfile"
    instruction := input.instructions[_]
    instruction.cmd == "expose"
    port := to_number(instruction.value)
    port < 1024
    not port in [80, 443]
    msg := sprintf("Privileged port %d is not allowed", [port])
}

# =============================================================================
# Dependency Security Policies
# =============================================================================

# Require package manager security updates
deny[msg] if {
    input.kind == "dockerfile"
    instruction := input.instructions[_]
    instruction.cmd == "run"
    contains(instruction.value, "apt-get install")
    not contains(instruction.value, "apt-get update")
    msg := "apt-get install must be preceded by apt-get update"
}

# Deny package managers that don't verify signatures
deny[msg] if {
    input.kind == "dockerfile"
    instruction := input.instructions[_]
    instruction.cmd == "run"
    contains(instruction.value, "pip install")
    not contains(instruction.value, "--trusted-host")
    not contains(instruction.value, "--index-url")
    msg := "pip install should use trusted package sources"
}

# =============================================================================
# Runtime Security Policies
# =============================================================================

# Require explicit entrypoint
deny[msg] if {
    input.kind == "dockerfile"
    not has_entrypoint
    not has_cmd
    msg := "Dockerfile must have either ENTRYPOINT or CMD instruction"
}

has_entrypoint if {
    instruction := input.instructions[_]
    instruction.cmd == "entrypoint"
}

has_cmd if {
    instruction := input.instructions[_]
    instruction.cmd == "cmd"
}

# Deny shell form for ENTRYPOINT and CMD
deny[msg] if {
    input.kind == "dockerfile"
    instruction := input.instructions[_]
    instruction.cmd in ["entrypoint", "cmd"]
    is_string(instruction.value)
    msg := sprintf("%s should use exec form, not shell form", [upper(instruction.cmd)])
}

# =============================================================================
# Metadata and Documentation
# =============================================================================

# Require essential labels
required_labels := ["maintainer", "version", "description"]

deny[msg] if {
    input.kind == "dockerfile"
    label := required_labels[_]
    not has_label(label)
    msg := sprintf("Dockerfile must have LABEL %s", [label])
}

has_label(label_name) if {
    instruction := input.instructions[_]
    instruction.cmd == "label"
    contains(instruction.value, label_name)
}

# =============================================================================
# Security Scanning Integration
# =============================================================================

# Require security scanning annotations
deny[msg] if {
    input.kind == "dockerfile"
    not has_label("security.scan.enabled")
    msg := "Dockerfile must have security scanning enabled label"
}

# Require vulnerability database update
deny[msg] if {
    input.kind == "dockerfile"
    not has_security_update_layer
    msg := "Dockerfile must include security update layer"
}

has_security_update_layer if {
    instruction := input.instructions[_]
    instruction.cmd == "run"
    contains(instruction.value, "apt-get upgrade")
}

has_security_update_layer if {
    instruction := input.instructions[_]
    instruction.cmd == "run"
    contains(instruction.value, "yum update")
}

has_security_update_layer if {
    instruction := input.instructions[_]
    instruction.cmd == "run"
    contains(instruction.value, "apk upgrade")
}

# =============================================================================
# Helper Functions
# =============================================================================

# Convert string to number safely
to_number(str) := num if {
    num := to_number(str)
} else := 0

# Check if value is in array
contains_value(array, value) if {
    array[_] == value
}