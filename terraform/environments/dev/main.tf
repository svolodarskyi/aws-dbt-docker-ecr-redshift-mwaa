terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "data-platform-terraform-state"
    key            = "env/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "DataEngineering"
    }
  }
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# Networking Module
module "networking" {
  source = "../../modules/networking"

  project_name = var.project_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr
  azs          = var.availability_zones
}

# Storage Module (S3 buckets)
module "storage" {
  source = "../../modules/storage"

  project_name = var.project_name
  environment  = var.environment
}

# IAM Roles Module
module "iam" {
  source = "../../modules/iam"

  project_name          = var.project_name
  environment           = var.environment
  raw_data_bucket_arn   = module.storage.raw_data_bucket_arn
  mwaa_bucket_arn       = module.storage.mwaa_bucket_arn
  ecr_repository_arn    = module.compute.ecr_repository_arn
}

# Compute Module (ECS, ECR)
module "compute" {
  source = "../../modules/compute"

  project_name            = var.project_name
  environment             = var.environment
  vpc_id                  = module.networking.vpc_id
  private_subnet_ids      = module.networking.private_subnet_ids
  task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  task_role_arn           = module.iam.ecs_task_role_arn
}

# Data Module (Redshift, Glue)
module "data" {
  source = "../../modules/data"

  project_name              = var.project_name
  environment               = var.environment
  vpc_id                    = module.networking.vpc_id
  private_subnet_ids        = module.networking.private_subnet_ids
  redshift_node_type        = var.redshift_node_type
  redshift_number_of_nodes  = var.redshift_number_of_nodes
  spectrum_role_arn         = module.iam.redshift_spectrum_role_arn
  raw_data_bucket_name      = module.storage.raw_data_bucket_name
}

# Orchestration Module (MWAA)
module "orchestration" {
  source = "../../modules/orchestration"

  project_name        = var.project_name
  environment         = var.environment
  vpc_id              = module.networking.vpc_id
  private_subnet_ids  = module.networking.private_subnet_ids
  mwaa_bucket_name    = module.storage.mwaa_bucket_name
  mwaa_execution_role = module.iam.mwaa_execution_role_arn
}

# Monitoring Module (CloudWatch, SNS)
module "monitoring" {
  source = "../../modules/monitoring"

  project_name  = var.project_name
  environment   = var.environment
  alert_emails  = var.alert_emails
  ecs_cluster_name = module.compute.ecs_cluster_name
  mwaa_environment_name = module.orchestration.mwaa_environment_name
}
