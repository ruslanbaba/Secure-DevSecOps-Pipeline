# ==============================================================================
# TERRAFORM MAIN CONFIGURATION - DEVSECOPS INFRASTRUCTURE
# ==============================================================================
# Complete infrastructure-as-code for secure cloud-native applications
# Supports: AWS, Azure, GCP with security hardening and compliance

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Remote state configuration
  backend "s3" {
    bucket         = "devsecops-terraform-state"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
    
    # Enhanced security
    server_side_encryption_configuration {
      rule {
        apply_server_side_encryption_by_default {
          sse_algorithm = "AES256"
        }
      }
    }
  }
}

# ==============================================================================
# LOCAL VALUES AND DATA SOURCES
# ==============================================================================

locals {
  # Environment configuration
  environment = var.environment
  project     = var.project_name
  region      = var.aws_region
  
  # Common tags
  common_tags = {
    Environment        = local.environment
    Project           = local.project
    ManagedBy         = "terraform"
    SecurityPolicy    = "restricted"
    Compliance        = "soc2,nist,cis"
    BackupRequired    = "true"
    MonitoringEnabled = "true"
    CostCenter        = var.cost_center
    Owner             = var.team_email
  }
  
  # Network configuration
  vpc_cidr = var.vpc_cidr
  availability_zones = data.aws_availability_zones.available.names
  
  # Security configuration
  enable_encryption = true
  enable_logging    = true
  enable_monitoring = true
  
  # Kubernetes configuration
  cluster_name    = "${local.project}-${local.environment}-cluster"
  cluster_version = var.k8s_version
  
  # Node groups configuration
  node_groups = {
    system = {
      instance_types = ["t3.medium"]
      min_size      = 1
      max_size      = 3
      desired_size  = 2
      capacity_type = "ON_DEMAND"
      taints = {
        "CriticalAddonsOnly" = {
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
    
    application = {
      instance_types = ["t3.large"]
      min_size      = 2
      max_size      = 10
      desired_size  = 3
      capacity_type = "SPOT"
      taints        = {}
    }
    
    security = {
      instance_types = ["t3.medium"]
      min_size      = 1
      max_size      = 2
      desired_size  = 1
      capacity_type = "ON_DEMAND"
      taints = {
        "SecurityWorkloads" = {
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# ==============================================================================
# VPC AND NETWORKING
# ==============================================================================

module "vpc" {
  source = "./modules/vpc"
  
  name = "${local.project}-${local.environment}-vpc"
  cidr = local.vpc_cidr
  
  azs             = local.availability_zones
  private_subnets = [for i, az in local.availability_zones : cidrsubnet(local.vpc_cidr, 8, i)]
  public_subnets  = [for i, az in local.availability_zones : cidrsubnet(local.vpc_cidr, 8, i + 100)]
  database_subnets = [for i, az in local.availability_zones : cidrsubnet(local.vpc_cidr, 8, i + 200)]
  
  # Enhanced security features
  enable_nat_gateway     = true
  enable_vpn_gateway     = false
  enable_dns_hostnames   = true
  enable_dns_support     = true
  enable_flow_log        = true
  flow_log_destination   = "cloud-watch-logs"
  
  # Network ACLs for additional security
  manage_default_network_acl = true
  default_network_acl_tags = {
    Name = "${local.project}-${local.environment}-default-nacl"
  }
  
  # Security groups
  manage_default_security_group = true
  default_security_group_rules = {
    ingress_rules = []
    egress_rules = [
      {
        description = "All outbound traffic"
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
      }
    ]
  }
  
  tags = local.common_tags
}

# VPC Endpoints for enhanced security
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.${local.region}.s3"
  
  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-s3-endpoint"
  })
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${local.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  policy = jsonencode({
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-ecr-api-endpoint"
  })
}

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${local.project}-${local.environment}-vpc-endpoints"
  vpc_id      = module.vpc.vpc_id
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-vpc-endpoints-sg"
  })
}

# ==============================================================================
# EKS CLUSTER
# ==============================================================================

module "eks" {
  source = "./modules/eks"
  
  cluster_name    = local.cluster_name
  cluster_version = local.cluster_version
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  
  # Enhanced security configuration
  cluster_endpoint_public_access       = false
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access_cidrs = []
  
  # Encryption
  cluster_encryption_config = [
    {
      provider_key_arn = aws_kms_key.eks.arn
      resources        = ["secrets"]
    }
  ]
  
  # Logging
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  
  # Node groups
  node_groups = {
    for name, config in local.node_groups : name => {
      instance_types = config.instance_types
      min_size      = config.min_size
      max_size      = config.max_size
      desired_size  = config.desired_size
      capacity_type = config.capacity_type
      
      # Enhanced security
      ami_type       = "AL2_x86_64_GPU"
      disk_size      = 50
      disk_type      = "gp3"
      disk_encrypted = true
      disk_kms_key_id = aws_kms_key.ebs.arn
      
      # Taints and labels
      taints = config.taints
      labels = {
        Environment = local.environment
        NodeGroup   = name
        Purpose     = name == "system" ? "system" : "workload"
      }
      
      # Instance metadata options (IMDSv2)
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
      }
      
      # User data for additional security hardening
      user_data_base64 = base64encode(templatefile("${path.module}/user-data.sh", {
        cluster_name = local.cluster_name
        environment  = local.environment
      }))
    }
  }
  
  # RBAC configuration
  manage_aws_auth_configmap = true
  aws_auth_roles = [
    {
      rolearn  = aws_iam_role.eks_admin.arn
      username = "admin"
      groups   = ["system:masters"]
    }
  ]
  
  aws_auth_users = var.authorized_users
  
  tags = local.common_tags
}

# ==============================================================================
# KMS KEYS FOR ENCRYPTION
# ==============================================================================

# EKS encryption key
resource "aws_kms_key" "eks" {
  description             = "EKS Secret Encryption Key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  
  policy = jsonencode({
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow use of the key"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-eks-key"
  })
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${local.project}-${local.environment}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# EBS encryption key
resource "aws_kms_key" "ebs" {
  description             = "EBS Volume Encryption Key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  
  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-ebs-key"
  })
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/${local.project}-${local.environment}-ebs"
  target_key_id = aws_kms_key.ebs.key_id
}

# ==============================================================================
# IAM ROLES AND POLICIES
# ==============================================================================

# EKS Admin Role
resource "aws_iam_role" "eks_admin" {
  name = "${local.project}-${local.environment}-eks-admin"
  
  assume_role_policy = jsonencode({
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = var.admin_role_arns
        }
      }
    ]
  })
  
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_admin_policy" {
  role       = aws_iam_role.eks_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ==============================================================================
# SECURITY CONFIGURATIONS
# ==============================================================================

# Security group for additional cluster security
resource "aws_security_group" "additional_cluster_sg" {
  name_prefix = "${local.project}-${local.environment}-cluster-additional"
  vpc_id      = module.vpc.vpc_id
  
  ingress {
    description = "Webhook admission controllers"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }
  
  ingress {
    description = "Metrics server"
    from_port   = 4443
    to_port     = 4443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-cluster-additional-sg"
  })
}

# ==============================================================================
# CONTAINER REGISTRY (ECR)
# ==============================================================================

resource "aws_ecr_repository" "app_repository" {
  name                 = "${local.project}/${local.environment}/secure-app"
  image_tag_mutability = "IMMUTABLE"
  
  encryption_configuration {
    encryption_type = "KMS"
    kms_key        = aws_kms_key.ecr.arn
  }
  
  image_scanning_configuration {
    scan_on_push = true
  }
  
  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "app_repository_policy" {
  repository = aws_ecr_repository.app_repository.name
  
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 production images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "release"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images older than 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ECR KMS key
resource "aws_kms_key" "ecr" {
  description             = "ECR Repository Encryption Key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  
  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-ecr-key"
  })
}

resource "aws_kms_alias" "ecr" {
  name          = "alias/${local.project}-${local.environment}-ecr"
  target_key_id = aws_kms_key.ecr.key_id
}