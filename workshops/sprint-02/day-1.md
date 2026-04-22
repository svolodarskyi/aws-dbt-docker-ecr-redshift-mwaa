# Sprint 2 - Day 1: AWS Setup & Terraform Backend

**Goal**: Configure AWS account and Terraform state management

**Duration**: ~6 hours

**Outcome**: AWS account configured, Terraform backend operational

---

## Morning Session (3 hours)

### Step 1: AWS Account Access Verification (30 minutes)

Verify you have proper AWS access:

```bash
# Configure AWS CLI (if not already done)
aws configure

# Enter when prompted:
# - AWS Access Key ID: [provided by admin]
# - AWS Secret Access Key: [provided by admin]
# - Default region name: us-east-1
# - Default output format: json

# Verify credentials
aws sts get-caller-identity

# Expected output:
# {
#     "UserId": "AIDAI...",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/your-name"
# }

# List available regions
aws ec2 describe-regions --output table

# Check current region
aws configure get region
```

Enable MFA (if not already enabled):

```bash
# List MFA devices
aws iam list-mfa-devices

# If no MFA, enable it:
# 1. Go to AWS Console → IAM → Users → [Your User]
# 2. Security credentials tab
# 3. Assign MFA device
# 4. Follow prompts with authenticator app
```

**✅ Validation**: `aws sts get-caller-identity` returns your account info

### Step 2: Configure Billing Alerts (30 minutes)

Set up budget alerts to avoid cost surprises:

```bash
# Create budget configuration
cat > /tmp/budget-config.json <<'EOF'
{
  "BudgetName": "data-platform-dev-monthly",
  "BudgetLimit": {
    "Amount": "500",
    "Unit": "USD"
  },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST",
  "CostFilters": {
    "TagKeyValue": ["user:Environment$dev"]
  }
}
EOF

cat > /tmp/notifications.json <<'EOF'
[
  {
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 80,
      "ThresholdType": "PERCENTAGE"
    },
    "Subscribers": [
      {
        "SubscriptionType": "EMAIL",
        "Address": "your-email@example.com"
      }
    ]
  }
]
EOF

# Create budget
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget file:///tmp/budget-config.json \
  --notifications-with-subscribers file:///tmp/notifications.json

# Clean up
rm /tmp/budget-config.json /tmp/notifications.json

# Verify budget created
aws budgets describe-budgets \
  --account-id $(aws sts get-caller-identity --query Account --output text)
```

**✅ Validation**: Budget appears in AWS Console → Billing → Budgets

### Step 3: Create Terraform State S3 Bucket (Manually) (1 hour)

The Terraform state bucket must be created manually (chicken-and-egg problem):

```bash
# Set variables
export AWS_REGION=us-east-1
export PROJECT_NAME=data-platform
export ENVIRONMENT=dev
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create S3 bucket for Terraform state
aws s3api create-bucket \
  --bucket ${PROJECT_NAME}-terraform-state-${ACCOUNT_ID} \
  --region ${AWS_REGION}

# Enable versioning (critical for state recovery)
aws s3api put-bucket-versioning \
  --bucket ${PROJECT_NAME}-terraform-state-${ACCOUNT_ID} \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket ${PROJECT_NAME}-terraform-state-${ACCOUNT_ID} \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket ${PROJECT_NAME}-terraform-state-${ACCOUNT_ID} \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Add lifecycle policy (keep 90 days of versions)
aws s3api put-bucket-lifecycle-configuration \
  --bucket ${PROJECT_NAME}-terraform-state-${ACCOUNT_ID} \
  --lifecycle-configuration '{
    "Rules": [{
      "Id": "ExpireOldVersions",
      "Status": "Enabled",
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 90
      }
    }]
  }'

# Verify bucket created
aws s3 ls | grep terraform-state
```

**✅ Validation**: Bucket exists with versioning and encryption enabled

### Step 4: Create DynamoDB Table for State Locking (30 minutes)

```bash
# Create DynamoDB table for Terraform state locks
aws dynamodb create-table \
  --table-name ${PROJECT_NAME}-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --tags Key=Project,Value=${PROJECT_NAME} Key=Environment,Value=${ENVIRONMENT} Key=ManagedBy,Value=manual \
  --region ${AWS_REGION}

# Wait for table to be active
aws dynamodb wait table-exists \
  --table-name ${PROJECT_NAME}-terraform-locks \
  --region ${AWS_REGION}

# Verify table created
aws dynamodb describe-table \
  --table-name ${PROJECT_NAME}-terraform-locks \
  --query 'Table.[TableName,TableStatus,BillingModeSummary.BillingMode]' \
  --output table
```

**✅ Validation**: Table status shows "ACTIVE"

---

## Afternoon Session (3 hours)

### Step 5: Configure Terraform Backend (1 hour)

Update Terraform configuration to use S3 backend:

```bash
cd terraform/environments/dev

# Create backend configuration
cat > backend.tf <<EOF
terraform {
  backend "s3" {
    bucket         = "${PROJECT_NAME}-terraform-state-${ACCOUNT_ID}"
    key            = "dev/terraform.tfstate"
    region         = "${AWS_REGION}"
    dynamodb_table = "${PROJECT_NAME}-terraform-locks"
    encrypt        = true

    # Optional: Enable state locking logs
    # kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/..."
  }

  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
EOF

# Create variables file
cat > variables.tf <<'EOF'
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "data-platform"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}
EOF

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
aws_region         = "${AWS_REGION}"
project_name       = "${PROJECT_NAME}"
environment        = "${ENVIRONMENT}"
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]
EOF
```

Initialize Terraform:

```bash
# Initialize Terraform
terraform init

# Expected output:
# Initializing the backend...
# Successfully configured the backend "s3"!
# Terraform has been successfully initialized!

# Verify backend configuration
terraform version
terraform providers

# Check state file location
aws s3 ls s3://${PROJECT_NAME}-terraform-state-${ACCOUNT_ID}/dev/
# Should be empty (no state yet)
```

**✅ Validation**: `terraform init` succeeds, backend configured

### Step 6: Create IAM Roles and Policies (1 hour 30 minutes)

Create basic IAM structure:

```bash
# Create IAM module directory
mkdir -p ../../modules/iam

cd ../../modules/iam

# Create IAM roles for future services
cat > main.tf <<'EOF'
# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------
# Redshift IAM Role
# ---------------------------------------------------------

resource "aws_iam_role" "redshift_spectrum" {
  name = "${var.project_name}-${var.environment}-redshift-spectrum-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "redshift.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-redshift-spectrum-role"
  }
}

resource "aws_iam_role_policy" "redshift_s3_access" {
  name = "s3-access"
  role = aws_iam_role.redshift_spectrum.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-*",
          "arn:aws:s3:::${var.project_name}-*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetPartitions"
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------
# MWAA Execution Role (created now, used later)
# ---------------------------------------------------------

resource "aws_iam_role" "mwaa_execution" {
  name = "${var.project_name}-${var.environment}-mwaa-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "airflow.amazonaws.com",
            "airflow-env.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-mwaa-execution-role"
  }
}

resource "aws_iam_role_policy" "mwaa_execution_policy" {
  name = "mwaa-execution-policy"
  role = aws_iam_role.mwaa_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "airflow:PublishMetrics"
        Resource = "arn:aws:airflow:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:environment/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject*",
          "s3:GetBucket*",
          "s3:List*"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-mwaa-${var.environment}",
          "arn:aws:s3:::${var.project_name}-mwaa-${var.environment}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:CreateLogGroup",
          "logs:PutLogEvents",
          "logs:GetLogEvents",
          "logs:GetLogRecord",
          "logs:GetLogGroupFields",
          "logs:GetQueryResults"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:airflow-${var.project_name}-${var.environment}-*"
      },
      {
        Effect = "Allow"
        Action = "cloudwatch:PutMetricData"
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------
# ECS Task Execution Role
# ---------------------------------------------------------

resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-${var.environment}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-task-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------------------------------------------------------
# Outputs
# ---------------------------------------------------------

output "redshift_spectrum_role_arn" {
  value = aws_iam_role.redshift_spectrum.arn
}

output "mwaa_execution_role_arn" {
  value = aws_iam_role.mwaa_execution.arn
}

output "ecs_task_execution_role_arn" {
  value = aws_iam_role.ecs_task_execution.arn
}
EOF

cat > variables.tf <<'EOF'
variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}
EOF

cat > outputs.tf <<'EOF'
output "redshift_spectrum_role_arn" {
  description = "ARN of Redshift Spectrum IAM role"
  value       = aws_iam_role.redshift_spectrum.arn
}

output "mwaa_execution_role_arn" {
  description = "ARN of MWAA execution IAM role"
  value       = aws_iam_role.mwaa_execution.arn
}

output "ecs_task_execution_role_arn" {
  description = "ARN of ECS task execution IAM role"
  value       = aws_iam_role.ecs_task_execution.arn
}
EOF
```

**✅ Validation**: IAM module structure created

### Step 7: Validate Terraform Configuration (30 minutes)

```bash
cd ../../environments/dev

# Add IAM module reference
cat > iam.tf <<'EOF'
module "iam" {
  source = "../../modules/iam"

  project_name = var.project_name
  environment  = var.environment
}

output "iam_roles" {
  value = {
    redshift_spectrum_role_arn  = module.iam.redshift_spectrum_role_arn
    mwaa_execution_role_arn     = module.iam.mwaa_execution_role_arn
    ecs_task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  }
}
EOF

# Format all Terraform files
terraform fmt -recursive ../../

# Validate configuration
terraform validate

# Expected: Success! The configuration is valid.

# Create a plan (preview changes)
terraform plan

# Expected output shows:
# - 3 IAM roles to be created
# - 2 IAM policies to be created
# - 1 IAM policy attachment to be created

# Save plan for review
terraform plan -out=tfplan

# Review plan details
terraform show tfplan
```

**✅ Validation**: `terraform validate` succeeds, plan shows expected resources

---

## End of Day 1 Checklist

- [x] AWS CLI configured and working
- [x] MFA enabled on AWS account
- [x] Billing alerts configured ($500/month budget)
- [x] S3 bucket created for Terraform state
- [x] DynamoDB table created for state locking
- [x] Terraform backend configured
- [x] IAM module created with roles for Redshift, MWAA, ECS
- [x] Terraform validation successful

---

## 📝 Daily Standup Notes

**Completed Today**:
- Configured AWS account and billing alerts
- Created Terraform backend (S3 + DynamoDB)
- Built IAM module with service roles
- Validated Terraform configuration

**Blockers**:
- None (or list any issues)

**Tomorrow's Plan**:
- Create VPC and networking module
- Configure subnets and route tables
- Set up security groups
- Create VPC endpoints

---

## 🎯 Success Metric

**You're successful if**:

```bash
# Terraform validates
cd terraform/environments/dev
terraform validate

# State backend works
terraform state list  # (empty for now)

# Can create a plan
terraform plan

# AWS CLI works
aws sts get-caller-identity
```

---

## ⏭️ Next: Day 2

Tomorrow you'll create the networking infrastructure:
- VPC and subnets
- NAT gateways
- Security groups
- VPC endpoints

**See [day-2.md](./day-2.md)** 🚀
