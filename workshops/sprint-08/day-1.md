# Sprint 8 - Day 1: Cosmos Setup & IAM Configuration

**Goal**: Configure Cosmos library in MWAA and set up IAM permissions for ECS integration

**Duration**: ~6 hours

**Outcome**: MWAA with Cosmos installed, IAM roles configured for Airflow→ECS→dbt

---

## Morning Session (3 hours)

### Step 1: Update MWAA Requirements (1 hour)

```bash
cd airflow

# Backup current requirements
cp requirements.txt requirements.txt.backup

# Update requirements.txt with Cosmos and dbt
cat > requirements.txt <<'EOF'
# Apache Airflow Providers
apache-airflow-providers-amazon==8.13.0
apache-airflow-providers-postgres==5.8.0

# Astronomer Cosmos for dbt integration
astronomer-cosmos==1.4.0

# dbt adapters (needed by Cosmos)
dbt-core==1.7.4
dbt-redshift==1.7.1

# Additional utilities
boto3==1.34.0
psycopg2-binary==2.9.9

# AWS SDK
aws-sdk==1.0.0
EOF

# Upload to S3
cd ..
MWAA_BUCKET=$(cd terraform/environments/dev && terraform output -json storage | jq -r '.mwaa_bucket_id')

echo "📦 Uploading updated requirements.txt to S3..."
aws s3 cp airflow/requirements.txt s3://${MWAA_BUCKET}/requirements.txt

# Verify upload
aws s3 ls s3://${MWAA_BUCKET}/requirements.txt --human-readable

echo ""
echo "⏰ MWAA will now update environment (takes 15-20 minutes)"
echo "Monitor status with:"
echo "  watch -n 30 'aws mwaa get-environment --name data-platform-airflow-dev --query Environment.Status --output text'"
```

**Monitor MWAA update**:
```bash
# In a separate terminal, watch the update
watch -n 30 'aws mwaa get-environment \
    --name data-platform-airflow-dev \
    --query "Environment.{Status:Status,LastUpdate:LastUpdate}" \
    --output table'

# Status progression:
# - UPDATING (15-20 minutes)
# - AVAILABLE (update complete)
```

**Create requirements documentation**:
```bash
cat > docs/MWAA_REQUIREMENTS.md <<'EOF'
# MWAA Requirements Management

## Current Requirements

```txt
# Apache Airflow Providers
apache-airflow-providers-amazon==8.13.0
apache-airflow-providers-postgres==5.8.0

# Astronomer Cosmos for dbt integration
astronomer-cosmos==1.4.0

# dbt adapters
dbt-core==1.7.4
dbt-redshift==1.7.1

# Additional utilities
boto3==1.34.0
psycopg2-binary==2.9.9
```

## Update Process

### 1. Edit requirements.txt

```bash
vim airflow/requirements.txt
```

### 2. Upload to S3

```bash
MWAA_BUCKET=$(cd terraform/environments/dev && terraform output -json storage | jq -r '.mwaa_bucket_id')
aws s3 cp airflow/requirements.txt s3://${MWAA_BUCKET}/requirements.txt
```

### 3. Wait for MWAA Update

**Duration**: 15-20 minutes

**Monitor**:
```bash
aws mwaa get-environment --name data-platform-airflow-dev \
    --query 'Environment.Status'
```

**Status**: UPDATING → AVAILABLE

### 4. Verify Installation

In Airflow UI:
- Admin → System → Packages
- Search for package (e.g., "cosmos")
- Verify version matches requirements.txt

## Package Guidelines

### Version Pinning

✅ **Always pin versions**:
```txt
astronomer-cosmos==1.4.0  # Good
```

❌ **Never use unpinned**:
```txt
astronomer-cosmos  # Bad - will use latest, may break
```

### Compatibility

- Check Airflow version compatibility
- MWAA 2.8.1 uses Python 3.11
- Test packages in dev before prod

### Common Packages

**AWS Integration**:
- `apache-airflow-providers-amazon` - AWS operators/sensors
- `boto3` - AWS SDK
- `aws-sdk` - Additional AWS utilities

**dbt Integration**:
- `astronomer-cosmos` - dbt orchestration
- `dbt-core` - dbt core library
- `dbt-redshift` - Redshift adapter

**Database**:
- `apache-airflow-providers-postgres` - Postgres operators
- `psycopg2-binary` - Postgres driver

## Troubleshooting

### Update Failed

**Check Logs**:
```bash
aws logs tail airflow-data-platform-dev-Scheduler --follow
```

**Common Issues**:
- Package conflict (incompatible versions)
- Package not found in PyPI
- Python version incompatibility

**Solution**: Revert to previous requirements.txt

### Package Not Available in DAG

**Check**:
1. MWAA status = AVAILABLE
2. Package in Admin → System → Packages
3. Restart web server (pause/unpause DAG)

**Import Test**:
```python
# In Airflow UI: Admin → Python Shell
import astronomer_cosmos
print(cosmos.__version__)
```

EOF
```

### Step 2: Create IAM Policy for MWAA→ECS (1 hour)

**While MWAA is updating**, create IAM policies:

```bash
cd terraform/modules/orchestration

# Update main.tf to add ECS permissions to MWAA execution role
cat >> main.tf <<'EOF'

# Additional IAM policy for ECS task execution
resource "aws_iam_role_policy" "mwaa_ecs_execution" {
  name = "mwaa-ecs-execution-policy"
  role = aws_iam_role.mwaa_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ECS task execution
      {
        Effect = "Allow"
        Action = [
          "ecs:RunTask",
          "ecs:DescribeTasks",
          "ecs:StopTask"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ecs:cluster" = "arn:aws:ecs:${var.region}:${var.account_id}:cluster/dbt-cluster"
          }
        }
      },
      # Pass role to ECS task
      {
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          "arn:aws:iam::${var.account_id}:role/${var.project_name}-dbt-task-execution-${var.environment}",
          "arn:aws:iam::${var.account_id}:role/${var.project_name}-dbt-task-role-${var.environment}"
        ]
      },
      # ECR image pull
      {
        Effect = "Allow"
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
}
EOF

# Format
terraform fmt main.tf
```

### Step 3: Create ECS Task IAM Roles (1 hour)

```bash
cd ../../modules

mkdir -p compute

cd compute

cat > main.tf <<'EOF'
# ECS Cluster for dbt tasks
resource "aws_ecs_cluster" "dbt" {
  name = "${var.project_name}-dbt-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.project_name}-dbt-${var.environment}"
  }
}

# CloudWatch Log Group for dbt tasks
resource "aws_cloudwatch_log_group" "dbt_tasks" {
  name              = "/ecs/${var.project_name}-dbt-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-dbt-logs-${var.environment}"
  }
}

# IAM Role: ECS Task Execution Role (for ECR pull, CloudWatch logs)
resource "aws_iam_role" "dbt_task_execution" {
  name = "${var.project_name}-dbt-task-execution-${var.environment}"

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
    Name = "${var.project_name}-dbt-task-execution-${var.environment}"
  }
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "dbt_task_execution" {
  role       = aws_iam_role.dbt_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for Secrets Manager access
resource "aws_iam_role_policy" "dbt_task_execution_secrets" {
  name = "secrets-access"
  role = aws_iam_role.dbt_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${var.project_name}/${var.environment}/*",
          "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:airflow/*"
        ]
      }
    ]
  })
}

# IAM Role: ECS Task Role (for application permissions - S3, Redshift, etc.)
resource "aws_iam_role" "dbt_task_role" {
  name = "${var.project_name}-dbt-task-role-${var.environment}"

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
    Name = "${var.project_name}-dbt-task-role-${var.environment}"
  }
}

# IAM Policy: dbt Task Permissions
resource "aws_iam_role_policy" "dbt_task_permissions" {
  name = "dbt-task-permissions"
  role = aws_iam_role.dbt_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 access for dbt artifacts
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.dbt_artifacts_bucket_arn,
          "${var.dbt_artifacts_bucket_arn}/*"
        ]
      },
      # S3 access for raw data (Redshift Spectrum)
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.raw_data_bucket_arn,
          "${var.raw_data_bucket_arn}/*"
        ]
      },
      # Secrets Manager for Redshift credentials
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${var.project_name}/${var.environment}/redshift/*"
      },
      # CloudWatch Logs
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.dbt_tasks.arn}:*"
      },
      # Glue Data Catalog (for Redshift Spectrum)
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

variable "region" {
  description = "AWS region"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "dbt_artifacts_bucket_arn" {
  description = "ARN of S3 bucket for dbt artifacts"
  type        = string
}

variable "raw_data_bucket_arn" {
  description = "ARN of S3 bucket for raw data"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}
EOF

cat > outputs.tf <<'EOF'
output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.dbt.name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.dbt.arn
}

output "dbt_task_execution_role_arn" {
  description = "ARN of the dbt task execution role"
  value       = aws_iam_role.dbt_task_execution.arn
}

output "dbt_task_role_arn" {
  description = "ARN of the dbt task role"
  value       = aws_iam_role.dbt_task_role.arn
}

output "dbt_log_group_name" {
  description = "Name of the CloudWatch log group for dbt tasks"
  value       = aws_cloudwatch_log_group.dbt_tasks.name
}
EOF

# Validate module
terraform fmt -recursive ../../
terraform -chdir=. validate
```

---

## Afternoon Session (3 hours)

### Step 4: Apply IAM Updates (30 minutes)

**First, check if MWAA update is complete**:
```bash
MWAA_STATUS=$(aws mwaa get-environment --name data-platform-airflow-dev --query 'Environment.Status' --output text)
echo "MWAA Status: ${MWAA_STATUS}"

if [ "$MWAA_STATUS" != "AVAILABLE" ]; then
    echo "⏰ MWAA still updating... waiting"
    # Continue with IAM updates, they're independent
fi
```

**Apply orchestration module updates** (MWAA ECS permissions):
```bash
cd ../../environments/dev

# Plan the orchestration update
terraform plan -target=module.orchestration

# Apply
terraform apply -target=module.orchestration

echo "✅ MWAA execution role now has ECS permissions"
```

### Step 5: Add Compute Module to Environment (1 hour)

```bash
# Still in terraform/environments/dev

cat > compute.tf <<'EOF'
# Get current AWS account ID and region
# (already defined in orchestration.tf, but shown here for clarity)

module "compute" {
  source = "../../modules/compute"

  project_name = var.project_name
  environment  = var.environment
  region       = data.aws_region.current.name
  account_id   = data.aws_caller_identity.current.account_id

  # S3 buckets
  dbt_artifacts_bucket_arn = module.storage.dbt_artifacts_bucket_arn
  raw_data_bucket_arn      = module.storage.raw_data_bucket_arn

  # Logging
  log_retention_days = 7
}

output "compute" {
  value = {
    ecs_cluster_name         = module.compute.ecs_cluster_name
    task_execution_role_arn  = module.compute.dbt_task_execution_role_arn
    task_role_arn            = module.compute.dbt_task_role_arn
    log_group_name           = module.compute.dbt_log_group_name
  }
  sensitive = false
}
EOF

# Format and validate
terraform fmt -recursive ../../
terraform validate

# Plan (don't apply yet - will do on Day 2 with task definition)
terraform plan -target=module.compute

echo "✅ Compute module ready (will apply on Day 2)"
```

### Step 6: Verify MWAA Update and Test Cosmos Import (1 hour 30 minutes)

**Check MWAA status**:
```bash
MWAA_STATUS=$(aws mwaa get-environment \
    --name data-platform-airflow-dev \
    --query 'Environment.Status' \
    --output text)

if [ "$MWAA_STATUS" = "AVAILABLE" ]; then
    echo "✅ MWAA environment updated successfully"
else
    echo "❌ MWAA status: ${MWAA_STATUS}"
    echo "Wait for AVAILABLE status before proceeding"
    exit 1
fi
```

**Create test DAG to verify Cosmos**:
```bash
cd ../../../airflow/dags

cat > test_cosmos_import.py <<'EOF'
"""
Test Cosmos Import

Verifies that Cosmos is installed and importable.
"""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator

default_args = {
    'owner': 'data-platform',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'test_cosmos_import',
    default_args=default_args,
    description='Test Cosmos library import',
    schedule_interval=None,
    catchup=False,
    tags=['test', 'cosmos'],
)

def test_cosmos_import():
    """Test importing Cosmos"""
    try:
        import cosmos
        print(f"✅ Cosmos version: {cosmos.__version__}")

        from cosmos import DbtTaskGroup, ProjectConfig, ProfileConfig, ExecutionConfig
        print("✅ Successfully imported Cosmos components:")
        print("  - DbtTaskGroup")
        print("  - ProjectConfig")
        print("  - ProfileConfig")
        print("  - ExecutionConfig")

        return "Cosmos import successful"
    except ImportError as e:
        print(f"❌ Failed to import Cosmos: {e}")
        raise

def test_dbt_import():
    """Test importing dbt"""
    try:
        import dbt
        print(f"✅ dbt-core version: {dbt.__version__}")

        import dbt.adapters.redshift
        print("✅ dbt-redshift adapter available")

        return "dbt import successful"
    except ImportError as e:
        print(f"❌ Failed to import dbt: {e}")
        raise

def test_aws_providers():
    """Test AWS providers"""
    try:
        from airflow.providers.amazon.aws.operators.ecs import EcsRunTaskOperator
        print("✅ EcsRunTaskOperator available")

        from airflow.providers.amazon.aws.hooks.base_aws import AwsBaseHook
        print("✅ AwsBaseHook available")

        return "AWS providers available"
    except ImportError as e:
        print(f"❌ Failed to import AWS providers: {e}")
        raise

task_cosmos = PythonOperator(
    task_id='test_cosmos',
    python_callable=test_cosmos_import,
    dag=dag,
)

task_dbt = PythonOperator(
    task_id='test_dbt',
    python_callable=test_dbt_import,
    dag=dag,
)

task_aws = PythonOperator(
    task_id='test_aws_providers',
    python_callable=test_aws_providers,
    dag=dag,
)

# Run in parallel
[task_cosmos, task_dbt, task_aws]
EOF

# Sync to MWAA
cd ../..
./scripts/airflow/sync-to-mwaa.sh dev

echo "⏰ Waiting 6 minutes for DAG sync..."
sleep 360

# Get Airflow UI URL
MWAA_URL=$(cd terraform/environments/dev && terraform output -json mwaa | jq -r '.webserver_url')
echo ""
echo "✅ Test DAG deployed!"
echo "Open Airflow UI: https://${MWAA_URL}"
echo "Trigger DAG: test_cosmos_import"
echo ""
echo "Expected output:"
echo "  - Cosmos version: 1.4.0"
echo "  - dbt-core version: 1.7.4"
echo "  - All imports successful"
```

**Manual testing in Airflow UI**:
1. Open Airflow UI
2. Find DAG: `test_cosmos_import`
3. Trigger DAG
4. Check logs for all 3 tasks
5. Verify all show ✅ success and version numbers

**Create verification script**:
```bash
cat > scripts/airflow/verify-cosmos.sh <<'EOF'
#!/bin/bash
set -e

echo "🧪 Verifying Cosmos installation in MWAA..."

# Check MWAA status
MWAA_STATUS=$(aws mwaa get-environment \
    --name data-platform-airflow-dev \
    --query 'Environment.Status' \
    --output text)

if [ "$MWAA_STATUS" != "AVAILABLE" ]; then
    echo "❌ MWAA status: ${MWAA_STATUS} (expected AVAILABLE)"
    exit 1
fi

echo "✅ MWAA environment: AVAILABLE"

# Check if test DAG exists in S3
MWAA_BUCKET=$(cd terraform/environments/dev && terraform output -json storage | jq -r '.mwaa_bucket_id')
if aws s3 ls s3://${MWAA_BUCKET}/dags/test_cosmos_import.py > /dev/null 2>&1; then
    echo "✅ test_cosmos_import.py deployed to S3"
else
    echo "❌ test_cosmos_import.py not found in S3"
    exit 1
fi

# Check requirements.txt
echo ""
echo "📋 Current MWAA requirements:"
aws s3 cp s3://${MWAA_BUCKET}/requirements.txt - | grep -E "(cosmos|dbt)"

echo ""
echo "✅ Verification complete!"
echo ""
echo "Next steps:"
echo "1. Open Airflow UI"
echo "2. Trigger DAG: test_cosmos_import"
echo "3. Verify all tasks succeed"
echo "4. Check logs for version numbers"
EOF

chmod +x scripts/airflow/verify-cosmos.sh

# Run verification
./scripts/airflow/verify-cosmos.sh
```

---

## End of Day 1 Checklist

- [x] MWAA requirements.txt updated with Cosmos and dbt
- [x] Requirements uploaded to S3
- [x] MWAA environment updated (Status: AVAILABLE)
- [x] IAM policy created: MWAA → ECS permissions
- [x] IAM role created: dbt task execution role
- [x] IAM role created: dbt task role
- [x] Compute Terraform module created
- [x] Test DAG created to verify Cosmos import
- [x] Cosmos import test successful

---

## 📝 Daily Standup Notes

**Completed Today**:
- Updated MWAA requirements with Cosmos 1.4.0 and dbt 1.7.1
- Created IAM policies for Airflow→ECS integration
- Created ECS task execution and task roles
- Built compute Terraform module for ECS cluster
- Verified Cosmos installation with test DAG
- All imports successful (Cosmos, dbt, AWS providers)

**Blockers**:
- None (MWAA update took ~18 minutes as expected)

**Tomorrow's Plan**:
- Apply compute module (ECS cluster creation)
- Create ECS task definition for dbt
- Test running dbt in ECS Fargate manually
- Verify CloudWatch logging

---

## 🎯 Success Metrics

```bash
# MWAA updated with new requirements
aws mwaa get-environment --name data-platform-airflow-dev \
    --query 'Environment.Status' \
    --output text
# Should output: AVAILABLE

# Cosmos in requirements
MWAA_BUCKET=$(cd terraform/environments/dev && terraform output -json storage | jq -r '.mwaa_bucket_id')
aws s3 cp s3://${MWAA_BUCKET}/requirements.txt - | grep cosmos
# Should show: astronomer-cosmos==1.4.0

# IAM roles created
aws iam get-role --role-name data-platform-dbt-task-execution-dev
aws iam get-role --role-name data-platform-dbt-task-role-dev
# Should both exist

# Compute module validates
terraform -chdir=terraform/modules/compute validate
# Should show: Success!

# Test DAG synced
aws s3 ls s3://${MWAA_BUCKET}/dags/ | grep test_cosmos_import
# Should show the file
```

---

## ⏭️ Next: Day 2

Tomorrow: Deploy ECS cluster, create task definition, test dbt in Fargate

**See [day-2.md](./day-2.md)** 🚀
