# ==============================================================================
# TERRAFORM OUTPUTS
# ==============================================================================

# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "database_subnets" {
  description = "List of IDs of database subnets"
  value       = module.vpc.database_subnets
}

# EKS Cluster Outputs
output "cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_iam_role_name" {
  description = "IAM role name associated with EKS cluster"
  value       = module.eks.cluster_iam_role_name
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN associated with EKS cluster"
  value       = module.eks.cluster_iam_role_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_primary_security_group_id" {
  description = "The cluster primary security group ID created by EKS"
  value       = module.eks.cluster_primary_security_group_id
}

# Node Groups Outputs
output "node_groups" {
  description = "EKS node groups"
  value       = module.eks.node_groups
  sensitive   = true
}

output "eks_managed_node_groups" {
  description = "Map of attribute maps for all EKS managed node groups created"
  value       = module.eks.eks_managed_node_groups
  sensitive   = true
}

# OIDC Provider Outputs
output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider" {
  description = "The OpenID Connect identity provider (issuer URL without leading `https://`)"
  value       = module.eks.oidc_provider
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider if `enable_irsa = true`"
  value       = module.eks.oidc_provider_arn
}

# Container Registry Outputs
output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.app_repository.repository_url
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.app_repository.arn
}

output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.app_repository.name
}

# KMS Key Outputs
output "eks_kms_key_arn" {
  description = "ARN of the EKS KMS key"
  value       = aws_kms_key.eks.arn
}

output "eks_kms_key_id" {
  description = "ID of the EKS KMS key"
  value       = aws_kms_key.eks.key_id
}

output "ebs_kms_key_arn" {
  description = "ARN of the EBS KMS key"
  value       = aws_kms_key.ebs.arn
}

output "ebs_kms_key_id" {
  description = "ID of the EBS KMS key"
  value       = aws_kms_key.ebs.key_id
}

output "ecr_kms_key_arn" {
  description = "ARN of the ECR KMS key"
  value       = aws_kms_key.ecr.arn
}

output "ecr_kms_key_id" {
  description = "ID of the ECR KMS key"
  value       = aws_kms_key.ecr.key_id
}

# Security Group Outputs
output "vpc_endpoints_security_group_id" {
  description = "Security group ID for VPC endpoints"
  value       = aws_security_group.vpc_endpoints.id
}

output "additional_cluster_security_group_id" {
  description = "Additional security group ID for the EKS cluster"
  value       = aws_security_group.additional_cluster_sg.id
}

# IAM Role Outputs
output "eks_admin_role_arn" {
  description = "ARN of the EKS admin role"
  value       = aws_iam_role.eks_admin.arn
}

output "eks_admin_role_name" {
  description = "Name of the EKS admin role"
  value       = aws_iam_role.eks_admin.name
}

# VPC Endpoint Outputs
output "vpc_endpoint_s3_id" {
  description = "ID of the S3 VPC endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "vpc_endpoint_ecr_api_id" {
  description = "ID of the ECR API VPC endpoint"
  value       = aws_vpc_endpoint.ecr_api.id
}

# Application Configuration Outputs
output "application_namespace" {
  description = "Kubernetes namespace for the application"
  value       = var.environment == "prod" ? "secure-app" : "secure-app-${var.environment}"
}

output "application_name" {
  description = "Name of the deployed application"
  value       = "secure-app"
}

# Monitoring Configuration Outputs
output "monitoring_namespace" {
  description = "Kubernetes namespace for monitoring components"
  value       = "monitoring"
}

output "prometheus_service_name" {
  description = "Service name for Prometheus"
  value       = var.enable_prometheus ? "prometheus" : null
}

output "grafana_service_name" {
  description = "Service name for Grafana"
  value       = var.enable_grafana ? "grafana" : null
}

# Security Tools Outputs
output "security_namespace" {
  description = "Kubernetes namespace for security tools"
  value       = "security-system"
}

output "falco_enabled" {
  description = "Whether Falco is enabled"
  value       = var.enable_falco
}

output "trivy_operator_enabled" {
  description = "Whether Trivy Operator is enabled"
  value       = var.enable_trivy_operator
}

output "opa_gatekeeper_enabled" {
  description = "Whether OPA Gatekeeper is enabled"
  value       = var.enable_opa_gatekeeper
}

# Certificate Management Outputs
output "cert_manager_enabled" {
  description = "Whether cert-manager is enabled"
  value       = var.enable_cert_manager
}

output "cluster_issuer_name" {
  description = "Name of the cluster certificate issuer"
  value       = var.cluster_issuer_name
}

# Ingress Configuration Outputs
output "ingress_controller_enabled" {
  description = "Whether NGINX Ingress Controller is enabled"
  value       = var.enable_nginx_ingress
}

output "ingress_class_name" {
  description = "Ingress class name"
  value       = var.ingress_class_name
}

# Backup Configuration Outputs
output "backup_enabled" {
  description = "Whether backup is enabled"
  value       = var.enable_velero
}

output "backup_schedule" {
  description = "Backup schedule"
  value       = var.backup_schedule
}

# Database Configuration Outputs
output "database_enabled" {
  description = "Whether database is enabled"
  value       = var.enable_database
}

output "database_type" {
  description = "Type of database deployed"
  value       = var.enable_database ? var.database_type : null
}

# Cache Configuration Outputs
output "redis_enabled" {
  description = "Whether Redis cache is enabled"
  value       = var.enable_redis
}

# Compliance and Audit Outputs
output "compliance_frameworks" {
  description = "List of enabled compliance frameworks"
  value       = var.compliance_frameworks
}

output "audit_logging_enabled" {
  description = "Whether audit logging is enabled"
  value       = var.enable_audit_logging
}

# Cost Management Outputs
output "cost_monitoring_enabled" {
  description = "Whether cost monitoring is enabled"
  value       = var.enable_cost_monitoring
}

output "monthly_budget_limit" {
  description = "Monthly budget limit in USD"
  value       = var.monthly_budget_limit
}

# Performance Configuration Outputs
output "hpa_enabled" {
  description = "Whether Horizontal Pod Autoscaler is enabled"
  value       = var.enable_hpa
}

output "cluster_autoscaler_enabled" {
  description = "Whether Cluster Autoscaler is enabled"
  value       = var.enable_cluster_autoscaler
}

# Environment Information
output "environment" {
  description = "Current environment"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

# Cluster Access Information
output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${local.cluster_name}"
}

output "cluster_access_role_arn" {
  description = "ARN of the role to assume for cluster access"
  value       = aws_iam_role.eks_admin.arn
}

# Resource Tags
output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Networking Information
output "nat_gateway_ips" {
  description = "List of public Elastic IPs for AWS NAT Gateway"
  value       = module.vpc.nat_public_ips
}

output "availability_zones" {
  description = "List of availability zones used"
  value       = local.availability_zones
}

# Security Information
output "cluster_encryption_enabled" {
  description = "Whether cluster encryption is enabled"
  value       = true
}

output "node_groups_encrypted" {
  description = "Whether node group storage is encrypted"
  value       = true
}

output "network_policies_enabled" {
  description = "Whether network policies are enabled"
  value       = var.enable_network_policies
}

output "pod_security_standards_enabled" {
  description = "Whether Pod Security Standards are enabled"
  value       = var.enable_pod_security_standards
}

# Multi-Region Configuration
output "multi_region_enabled" {
  description = "Whether multi-region deployment is enabled"
  value       = var.enable_multi_region
}

output "secondary_regions" {
  description = "List of secondary regions for disaster recovery"
  value       = var.secondary_regions
}

# Development Tools
output "development_tools_enabled" {
  description = "Whether development tools are enabled"
  value       = var.enable_development_tools
}