# ==============================================================================
# TERRAFORM VARIABLES CONFIGURATION
# ==============================================================================

# Environment Configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "secure-devsecops"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

# Kubernetes Configuration
variable "k8s_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
  validation {
    condition     = can(regex("^1\\.(2[4-9]|[3-9][0-9])$", var.k8s_version))
    error_message = "Kubernetes version must be 1.24 or higher."
  }
}

variable "node_group_instance_types" {
  description = "EC2 instance types for EKS node groups"
  type        = map(list(string))
  default = {
    system      = ["t3.medium"]
    application = ["t3.large", "t3.xlarge"]
    security    = ["t3.medium"]
  }
}

variable "node_group_scaling" {
  description = "Scaling configuration for node groups"
  type = map(object({
    min_size     = number
    max_size     = number
    desired_size = number
  }))
  default = {
    system = {
      min_size     = 1
      max_size     = 3
      desired_size = 2
    }
    application = {
      min_size     = 2
      max_size     = 10
      desired_size = 3
    }
    security = {
      min_size     = 1
      max_size     = 2
      desired_size = 1
    }
  }
}

# Security Configuration
variable "authorized_users" {
  description = "List of authorized IAM users for EKS access"
  type = list(object({
    userarn  = string
    username = string
    groups   = list(string)
  }))
  default = []
}

variable "admin_role_arns" {
  description = "List of IAM role ARNs that can assume EKS admin role"
  type        = list(string)
  default     = []
}

variable "enable_cluster_logging" {
  description = "Enable EKS cluster logging"
  type        = bool
  default     = true
}

variable "cluster_log_types" {
  description = "List of EKS cluster log types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "enable_prometheus" {
  description = "Enable Prometheus monitoring"
  type        = bool
  default     = true
}

variable "enable_grafana" {
  description = "Enable Grafana dashboards"
  type        = bool
  default     = true
}

variable "enable_alertmanager" {
  description = "Enable AlertManager"
  type        = bool
  default     = true
}

variable "prometheus_retention" {
  description = "Prometheus data retention period"
  type        = string
  default     = "15d"
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
  default     = ""
}

# Security Tools Configuration
variable "enable_falco" {
  description = "Enable Falco runtime security"
  type        = bool
  default     = true
}

variable "enable_trivy_operator" {
  description = "Enable Trivy Operator for vulnerability scanning"
  type        = bool
  default     = true
}

variable "enable_opa_gatekeeper" {
  description = "Enable OPA Gatekeeper for policy enforcement"
  type        = bool
  default     = true
}

variable "enable_network_policies" {
  description = "Enable Kubernetes Network Policies"
  type        = bool
  default     = true
}

variable "enable_pod_security_standards" {
  description = "Enable Pod Security Standards"
  type        = bool
  default     = true
}

# Backup Configuration
variable "enable_velero" {
  description = "Enable Velero for backup and disaster recovery"
  type        = bool
  default     = true
}

variable "backup_schedule" {
  description = "Backup schedule in cron format"
  type        = string
  default     = "0 2 * * *" # Daily at 2 AM
}

variable "backup_retention" {
  description = "Backup retention period in hours"
  type        = number
  default     = 720 # 30 days
}

# Certificate Management
variable "enable_cert_manager" {
  description = "Enable cert-manager for TLS certificate management"
  type        = bool
  default     = true
}

variable "acme_email" {
  description = "Email address for ACME certificate requests"
  type        = string
  default     = ""
}

variable "cluster_issuer_name" {
  description = "Name of the cluster certificate issuer"
  type        = string
  default     = "letsencrypt-prod"
}

# Ingress Configuration
variable "enable_nginx_ingress" {
  description = "Enable NGINX Ingress Controller"
  type        = bool
  default     = true
}

variable "ingress_class_name" {
  description = "Ingress class name"
  type        = string
  default     = "nginx"
}

variable "enable_external_dns" {
  description = "Enable ExternalDNS for automatic DNS management"
  type        = bool
  default     = false
}

variable "external_dns_domain" {
  description = "Domain for ExternalDNS management"
  type        = string
  default     = ""
}

# Application Configuration
variable "application_replicas" {
  description = "Number of application replicas"
  type        = number
  default     = 3
  validation {
    condition     = var.application_replicas >= 1 && var.application_replicas <= 100
    error_message = "Application replicas must be between 1 and 100."
  }
}

variable "application_resources" {
  description = "Resource limits and requests for the application"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "128Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }
}

variable "application_image" {
  description = "Container image for the application"
  type        = string
  default     = "secure-app:latest"
}

variable "application_port" {
  description = "Port on which the application listens"
  type        = number
  default     = 3000
  validation {
    condition     = var.application_port >= 1 && var.application_port <= 65535
    error_message = "Application port must be between 1 and 65535."
  }
}

# Database Configuration
variable "enable_database" {
  description = "Enable database deployment"
  type        = bool
  default     = false
}

variable "database_type" {
  description = "Type of database (postgresql, mysql, mongodb)"
  type        = string
  default     = "postgresql"
  validation {
    condition     = contains(["postgresql", "mysql", "mongodb"], var.database_type)
    error_message = "Database type must be one of: postgresql, mysql, mongodb."
  }
}

variable "database_storage_size" {
  description = "Database storage size"
  type        = string
  default     = "20Gi"
}

variable "database_backup_enabled" {
  description = "Enable database backups"
  type        = bool
  default     = true
}

# Cache Configuration
variable "enable_redis" {
  description = "Enable Redis cache"
  type        = bool
  default     = false
}

variable "redis_memory_size" {
  description = "Redis memory size"
  type        = string
  default     = "1Gi"
}

# Cost and Management
variable "cost_center" {
  description = "Cost center for resource tagging"
  type        = string
  default     = ""
}

variable "team_email" {
  description = "Team email for resource ownership"
  type        = string
  default     = ""
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.team_email)) || var.team_email == ""
    error_message = "Team email must be a valid email address."
  }
}

variable "enable_cost_monitoring" {
  description = "Enable cost monitoring and alerting"
  type        = bool
  default     = true
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD"
  type        = number
  default     = 1000
}

# Compliance Configuration
variable "compliance_frameworks" {
  description = "List of compliance frameworks to enforce"
  type        = list(string)
  default     = ["soc2", "nist", "cis"]
  validation {
    condition = alltrue([
      for framework in var.compliance_frameworks : contains(["soc2", "nist", "cis", "pci", "hipaa"], framework)
    ])
    error_message = "Compliance frameworks must be from: soc2, nist, cis, pci, hipaa."
  }
}

variable "enable_audit_logging" {
  description = "Enable comprehensive audit logging"
  type        = bool
  default     = true
}

variable "audit_log_retention_days" {
  description = "Audit log retention period in days"
  type        = number
  default     = 90
}

# Disaster Recovery Configuration
variable "enable_multi_region" {
  description = "Enable multi-region deployment for disaster recovery"
  type        = bool
  default     = false
}

variable "secondary_regions" {
  description = "List of secondary regions for disaster recovery"
  type        = list(string)
  default     = []
}

variable "rpo_hours" {
  description = "Recovery Point Objective in hours"
  type        = number
  default     = 4
}

variable "rto_hours" {
  description = "Recovery Time Objective in hours"
  type        = number
  default     = 2
}

# Performance Configuration
variable "enable_hpa" {
  description = "Enable Horizontal Pod Autoscaler"
  type        = bool
  default     = true
}

variable "hpa_target_cpu" {
  description = "Target CPU utilization for HPA"
  type        = number
  default     = 70
  validation {
    condition     = var.hpa_target_cpu >= 1 && var.hpa_target_cpu <= 100
    error_message = "HPA target CPU must be between 1 and 100."
  }
}

variable "enable_vpa" {
  description = "Enable Vertical Pod Autoscaler"
  type        = bool
  default     = false
}

variable "enable_cluster_autoscaler" {
  description = "Enable Cluster Autoscaler"
  type        = bool
  default     = true
}

# Development Configuration
variable "enable_development_tools" {
  description = "Enable development and debugging tools"
  type        = bool
  default     = false
}

variable "enable_k9s" {
  description = "Enable k9s for cluster management"
  type        = bool
  default     = false
}

variable "enable_lens" {
  description = "Enable Lens IDE integration"
  type        = bool
  default     = false
}