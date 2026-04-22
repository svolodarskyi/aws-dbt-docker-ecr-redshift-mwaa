# Sprint 7 - Day 1: MWAA Infrastructure & S3 Bucket Setup

**Goal**: Create Terraform module for AWS MWAA and prepare S3 structure

**Duration**: ~6 hours

**Outcome**: MWAA Terraform module ready, S3 buckets configured with DAG structure

---

## Morning Session (3 hours)

### Step 1: Create MWAA Terraform Module (1 hour 30 minutes)

```bash
cd terraform/modules

mkdir -p orchestration

cd orchestration

# Create main.tf for MWAA environment
cat > main.tf <<'EOF'
# MWAA Environment
resource "aws_mwaa_environment" "airflow" {
  name              = "${var.project_name}-airflow-${var.environment}"
  airflow_version   = "2.8.1"
  environment_class = var.environment_class

  # S3 bucket for DAGs
  source_bucket_arn = var.mwaa_bucket_arn
  dag_s3_path       = "dags"

  # Requirements file
  requirements_s3_path = "requirements.txt"

  # Execution role
  execution_role_arn = aws_iam_role.mwaa_execution.arn

  # Network configuration
  network_configuration {
    security_group_ids = [aws_security_group.mwaa.id]
    subnet_ids         = var.private_subnet_ids
  }

  # Logging configuration
  logging_configuration {
    dag_processing_logs {
      enabled   = true
      log_level = "INFO"
    }

    scheduler_logs {
      enabled   = true
      log_level = "INFO"
    }

    task_logs {
      enabled   = true
      log_level = "INFO"
    }

    webserver_logs {
      enabled   = true
      log_level = "INFO"
    }

    worker_logs {
      enabled   = true
      log_level = "INFO"
    }
  }

  # Airflow configuration options
  airflow_configuration_options = {
    "core.default_timezone"                     = "UTC"
    "logging.logging_level"                     = "INFO"
    "secrets.backend"                          = "airflow.providers.amazon.aws.secrets.secrets_manager.SecretsManagerBackend"
    "secrets.backend_kwargs"                   = jsonencode({
      connections_prefix = "airflow/connections"
      variables_prefix   = "airflow/variables"
    })
  }

  # Web server access mode
  webserver_access_mode = var.webserver_access_mode

  tags = {
    Name        = "${var.project_name}-airflow-${var.environment}"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# MWAA Execution Role
resource "aws_iam_role" "mwaa_execution" {
  name = "${var.project_name}-mwaa-execution-${var.environment}"

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
    Name = "${var.project_name}-mwaa-execution-${var.environment}"
  }
}

# MWAA Execution Policy
resource "aws_iam_role_policy" "mwaa_execution" {
  name = "mwaa-execution-policy"
  role = aws_iam_role.mwaa_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 access for DAGs and logs
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          var.mwaa_bucket_arn,
          "${var.mwaa_bucket_arn}/*"
        ]
      },
      # CloudWatch Logs
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
        Resource = "arn:aws:logs:${var.region}:${var.account_id}:log-group:airflow-${var.project_name}-${var.environment}-*"
      },
      # CloudWatch Metrics
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
      # SQS for Airflow internals
      {
        Effect = "Allow"
        Action = [
          "sqs:ChangeMessageVisibility",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage",
          "sqs:SendMessage"
        ]
        Resource = "arn:aws:sqs:${var.region}:*:airflow-celery-*"
      },
      # KMS for encryption (if used)
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey*",
          "kms:Encrypt"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "sqs.${var.region}.amazonaws.com"
          }
        }
      },
      # Secrets Manager access
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets"
        ]
        Resource = "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:airflow/*"
      },
      # Additional Redshift access for connections
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${var.project_name}/${var.environment}/redshift/*"
      }
    ]
  })
}

# Security Group for MWAA
resource "aws_security_group" "mwaa" {
  name        = "${var.project_name}-mwaa-${var.environment}"
  description = "Security group for MWAA environment"
  vpc_id      = var.vpc_id

  # Self-referencing rule for Airflow components
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
    description = "Allow all traffic within MWAA security group"
  }

  # Egress to VPC endpoints
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "HTTPS to VPC endpoints"
  }

  # Egress to internet via NAT (for external packages)
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS to internet for Python packages"
  }

  tags = {
    Name = "${var.project_name}-mwaa-${var.environment}"
  }
}

# CloudWatch Log Groups (created explicitly for better control)
resource "aws_cloudwatch_log_group" "mwaa_dag_processing" {
  name              = "airflow-${var.project_name}-${var.environment}-DAG"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-mwaa-dag-logs-${var.environment}"
  }
}

resource "aws_cloudwatch_log_group" "mwaa_scheduler" {
  name              = "airflow-${var.project_name}-${var.environment}-Scheduler"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-mwaa-scheduler-logs-${var.environment}"
  }
}

resource "aws_cloudwatch_log_group" "mwaa_task" {
  name              = "airflow-${var.project_name}-${var.environment}-Task"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-mwaa-task-logs-${var.environment}"
  }
}

resource "aws_cloudwatch_log_group" "mwaa_webserver" {
  name              = "airflow-${var.project_name}-${var.environment}-WebServer"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-mwaa-webserver-logs-${var.environment}"
  }
}

resource "aws_cloudwatch_log_group" "mwaa_worker" {
  name              = "airflow-${var.project_name}-${var.environment}-Worker"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-mwaa-worker-logs-${var.environment}"
  }
}
EOF

# Create variables.tf
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

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for MWAA"
  type        = list(string)
}

variable "mwaa_bucket_arn" {
  description = "ARN of S3 bucket for MWAA DAGs"
  type        = string
}

variable "environment_class" {
  description = "MWAA environment class (mw1.small, mw1.medium, mw1.large)"
  type        = string
  default     = "mw1.medium"
}

variable "webserver_access_mode" {
  description = "Web server access mode (PUBLIC_ONLY or PRIVATE_ONLY)"
  type        = string
  default     = "PUBLIC_ONLY"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}
EOF

# Create outputs.tf
cat > outputs.tf <<'EOF'
output "mwaa_environment_arn" {
  description = "ARN of the MWAA environment"
  value       = aws_mwaa_environment.airflow.arn
}

output "mwaa_environment_name" {
  description = "Name of the MWAA environment"
  value       = aws_mwaa_environment.airflow.name
}

output "mwaa_webserver_url" {
  description = "URL of the MWAA webserver"
  value       = aws_mwaa_environment.airflow.webserver_url
}

output "mwaa_execution_role_arn" {
  description = "ARN of the MWAA execution role"
  value       = aws_iam_role.mwaa_execution.arn
}

output "mwaa_security_group_id" {
  description = "ID of the MWAA security group"
  value       = aws_security_group.mwaa.id
}

output "mwaa_status" {
  description = "Status of the MWAA environment"
  value       = aws_mwaa_environment.airflow.status
}
EOF
```

**Validation**:
```bash
terraform fmt -recursive ../../
terraform -chdir=../../modules/orchestration validate
```

### Step 2: Create MWAA S3 Bucket Structure (1 hour)

```bash
cd ../../environments/dev

# Update storage.tf to add MWAA bucket
cat >> storage.tf <<'EOF'

# Additional S3 bucket for MWAA (separate from existing mwaa bucket)
# This ensures proper structure for Airflow
resource "aws_s3_object" "mwaa_dags_folder" {
  bucket = module.storage.mwaa_bucket_id
  key    = "dags/"
  source = "/dev/null"
}

resource "aws_s3_object" "mwaa_plugins_folder" {
  bucket = module.storage.mwaa_bucket_id
  key    = "plugins/"
  source = "/dev/null"
}
EOF

# Verify MWAA bucket structure
terraform plan
```

**Create local Airflow directory structure**:
```bash
cd ../../../

mkdir -p airflow/{dags,plugins}

# Create .gitkeep files
touch airflow/dags/.gitkeep
touch airflow/plugins/.gitkeep

# Create initial requirements.txt for MWAA
cat > airflow/requirements.txt <<'EOF'
# Apache Airflow Providers
apache-airflow-providers-amazon==8.13.0
apache-airflow-providers-postgres==5.8.0

# Astronomer Cosmos for dbt integration
astronomer-cosmos==1.4.0

# Additional utilities
boto3==1.34.0
psycopg2-binary==2.9.9
EOF
```

### Step 3: Upload requirements.txt to S3 (30 minutes)

```bash
# Get MWAA bucket name
cd terraform/environments/dev
MWAA_BUCKET=$(terraform output -json storage | jq -r '.mwaa_bucket_id')

echo "MWAA Bucket: ${MWAA_BUCKET}"

# Upload requirements.txt to S3
cd ../../../
aws s3 cp airflow/requirements.txt s3://${MWAA_BUCKET}/requirements.txt

# Verify upload
aws s3 ls s3://${MWAA_BUCKET}/

# Should show:
# - requirements.txt
# - dags/
# - plugins/
```

**Create upload script for future use**:
```bash
mkdir -p scripts/airflow

cat > scripts/airflow/sync-to-mwaa.sh <<'EOF'
#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}

echo "🚀 Syncing Airflow files to MWAA S3 bucket..."

# Get MWAA bucket from Terraform
cd terraform/environments/${ENVIRONMENT}
MWAA_BUCKET=$(terraform output -json storage | jq -r '.mwaa_bucket_id')
cd -

if [ -z "$MWAA_BUCKET" ]; then
    echo "❌ Error: Could not get MWAA bucket name"
    exit 1
fi

echo "📦 MWAA Bucket: ${MWAA_BUCKET}"

# Sync DAGs
echo "📁 Syncing DAGs..."
aws s3 sync airflow/dags/ s3://${MWAA_BUCKET}/dags/ \
    --delete \
    --exclude "*.pyc" \
    --exclude "__pycache__/*" \
    --exclude ".gitkeep"

# Sync plugins (if any)
if [ "$(ls -A airflow/plugins)" ]; then
    echo "🔌 Syncing plugins..."
    aws s3 sync airflow/plugins/ s3://${MWAA_BUCKET}/plugins/ \
        --delete \
        --exclude ".gitkeep"
fi

# Upload requirements.txt
echo "📋 Uploading requirements.txt..."
aws s3 cp airflow/requirements.txt s3://${MWAA_BUCKET}/requirements.txt

echo ""
echo "✅ Sync complete!"
echo ""
echo "📊 Files in S3:"
aws s3 ls s3://${MWAA_BUCKET}/ --recursive --human-readable

echo ""
echo "⏰ Note: MWAA picks up changes every ~5 minutes"
EOF

chmod +x scripts/airflow/sync-to-mwaa.sh

# Test the script
./scripts/airflow/sync-to-mwaa.sh dev
```

---

## Afternoon Session (3 hours)

### Step 4: Add MWAA Module to Environment (1 hour)

```bash
cd terraform/environments/dev

# Create orchestration.tf
cat > orchestration.tf <<'EOF'
# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

module "orchestration" {
  source = "../../modules/orchestration"

  project_name = var.project_name
  environment  = var.environment
  region       = data.aws_region.current.name
  account_id   = data.aws_caller_identity.current.account_id

  # Networking
  vpc_id             = module.networking.vpc_id
  vpc_cidr           = module.networking.vpc_cidr
  private_subnet_ids = module.networking.private_subnet_ids

  # S3 bucket for MWAA
  mwaa_bucket_arn = module.storage.mwaa_bucket_arn

  # MWAA configuration
  environment_class      = "mw1.medium"  # Medium = 1 worker, ~$700/month
  webserver_access_mode  = "PUBLIC_ONLY"  # Change to PRIVATE_ONLY for production
  log_retention_days     = 7
}

output "mwaa" {
  value = {
    environment_name  = module.orchestration.mwaa_environment_name
    webserver_url     = module.orchestration.mwaa_webserver_url
    execution_role    = module.orchestration.mwaa_execution_role_arn
    status            = module.orchestration.mwaa_status
  }
  sensitive = false
}
EOF

# Format and validate
terraform fmt -recursive ../../
terraform validate
```

**Important**: Don't run `terraform apply` yet - we'll do that on Day 2 (it takes ~30 minutes)

### Step 5: Create Sample DAG (1 hour)

```bash
cd ../../../airflow/dags

# Create a simple hello world DAG
cat > sample_hello_world.py <<'EOF'
"""
Sample Hello World DAG

This is a simple DAG to verify MWAA setup.
"""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator

# Default arguments
default_args = {
    'owner': 'data-platform',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

# Define DAG
dag = DAG(
    'sample_hello_world',
    default_args=default_args,
    description='A simple hello world DAG',
    schedule_interval='@daily',
    catchup=False,
    tags=['sample', 'hello-world'],
)

# Task 1: Print hello
task_hello = BashOperator(
    task_id='hello',
    bash_command='echo "Hello from MWAA!"',
    dag=dag,
)

# Task 2: Print environment info
def print_env_info():
    import platform
    import sys
    print(f"Python version: {sys.version}")
    print(f"Platform: {platform.platform()}")
    print(f"Processor: {platform.processor()}")

task_env_info = PythonOperator(
    task_id='environment_info',
    python_callable=print_env_info,
    dag=dag,
)

# Task 3: Print Airflow variables
task_airflow_info = BashOperator(
    task_id='airflow_info',
    bash_command='echo "Airflow home: $AIRFLOW_HOME"',
    dag=dag,
)

# Set task dependencies
task_hello >> task_env_info >> task_airflow_info
EOF

# Create a DAG to test AWS connections
cat > sample_aws_test.py <<'EOF'
"""
Sample AWS Connection Test DAG

Tests AWS connectivity from MWAA.
"""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator

default_args = {
    'owner': 'data-platform',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'sample_aws_test',
    default_args=default_args,
    description='Test AWS connectivity from MWAA',
    schedule_interval=None,  # Manual trigger only
    catchup=False,
    tags=['sample', 'aws', 'test'],
)

def test_s3_access():
    """Test S3 access"""
    import boto3
    s3 = boto3.client('s3')

    # List first 5 buckets
    response = s3.list_buckets()
    buckets = response['Buckets'][:5]

    print("S3 Buckets accessible:")
    for bucket in buckets:
        print(f"  - {bucket['Name']}")

    return f"Successfully accessed {len(buckets)} buckets"

def test_secrets_manager():
    """Test Secrets Manager access"""
    import boto3

    secrets = boto3.client('secretsmanager')

    # List secrets (first 5)
    response = secrets.list_secrets(MaxResults=5)

    print("Secrets Manager accessible:")
    print(f"  Found {len(response.get('SecretList', []))} secrets")

    return "Secrets Manager access successful"

def test_cloudwatch_logs():
    """Test CloudWatch Logs access"""
    import boto3

    logs = boto3.client('logs')

    # List log groups (first 5)
    response = logs.describe_log_groups(limit=5)

    print("CloudWatch Logs accessible:")
    print(f"  Found {len(response.get('logGroups', []))} log groups")

    return "CloudWatch Logs access successful"

# Create tasks
task_s3 = PythonOperator(
    task_id='test_s3',
    python_callable=test_s3_access,
    dag=dag,
)

task_secrets = PythonOperator(
    task_id='test_secrets_manager',
    python_callable=test_secrets_manager,
    dag=dag,
)

task_logs = PythonOperator(
    task_id='test_cloudwatch_logs',
    python_callable=test_cloudwatch_logs,
    dag=dag,
)

# Run in parallel
[task_s3, task_secrets, task_logs]
EOF

# Validate DAGs locally (if airflow installed)
if command -v airflow &> /dev/null; then
    echo "Validating DAGs..."
    python sample_hello_world.py
    python sample_aws_test.py
    echo "✅ DAGs validated successfully"
else
    echo "⚠️  Airflow not installed locally - will validate after upload to MWAA"
fi
```

### Step 6: Create MWAA Documentation (1 hour)

```bash
cd ../../docs

cat > MWAA_SETUP.md <<'EOF'
# AWS MWAA Setup Guide

## Overview

AWS Managed Workflows for Apache Airflow (MWAA) provides a managed Airflow environment.

**Environment**: `data-platform-airflow-dev`
**Version**: Apache Airflow 2.8.1
**Size**: Medium (mw1.medium)

---

## Architecture

### Components

1. **MWAA Environment**:
   - Webserver (UI)
   - Scheduler
   - Workers (1 for medium)
   - Database (managed PostgreSQL)

2. **S3 Bucket** (`data-platform-mwaa-dev`):
   - `/dags/` - DAG files
   - `/plugins/` - Custom plugins
   - `requirements.txt` - Python dependencies

3. **CloudWatch Log Groups**:
   - DAG processing logs
   - Scheduler logs
   - Task logs
   - Webserver logs
   - Worker logs

4. **IAM Role**:
   - S3 access (DAGs, logs)
   - CloudWatch Logs
   - Secrets Manager
   - Redshift (via Secrets Manager)

---

## Environment Classes

| Class | Workers | vCPU | Memory | Cost/month |
|-------|---------|------|--------|------------|
| mw1.small | 1-2 | 1 | 2 GB | ~$350 |
| mw1.medium | 1-10 | 2 | 4 GB | ~$700 |
| mw1.large | 1-25 | 4 | 8 GB | ~$1,400 |

**Current**: `mw1.medium` (good for development/testing)

---

## DAG Deployment Process

### Automatic Sync (Every 5 Minutes)

MWAA automatically checks S3 for changes every ~5 minutes.

### Manual Sync

```bash
# Sync all files
./scripts/airflow/sync-to-mwaa.sh dev

# Manual S3 sync
MWAA_BUCKET=$(cd terraform/environments/dev && terraform output -json storage | jq -r '.mwaa_bucket_id')

aws s3 sync airflow/dags/ s3://${MWAA_BUCKET}/dags/ --delete
```

### DAG Development Workflow

1. **Write DAG** in `airflow/dags/`
2. **Test locally** (optional): `python your_dag.py`
3. **Sync to S3**: `./scripts/airflow/sync-to-mwaa.sh dev`
4. **Wait 5 minutes** for MWAA to pick up
5. **Check Airflow UI** for DAG appearance
6. **Trigger manually** or wait for schedule

---

## Accessing Airflow UI

### Via AWS Console

1. Go to **MWAA console**
2. Click environment: `data-platform-airflow-dev`
3. Click **Open Airflow UI** button
4. Authenticate with AWS credentials

### Direct URL

```bash
# Get webserver URL
cd terraform/environments/dev
terraform output -json mwaa | jq -r '.webserver_url'

# Open in browser (will redirect to AWS SSO)
```

### Access Control

**Current**: `PUBLIC_ONLY` (accessible from internet via AWS SSO)
**Production**: Change to `PRIVATE_ONLY` (VPN or bastion required)

---

## CloudWatch Logs

### Log Groups

```
airflow-data-platform-dev-DAG         # DAG processing
airflow-data-platform-dev-Scheduler   # Scheduler logs
airflow-data-platform-dev-Task        # Task execution
airflow-data-platform-dev-WebServer   # UI logs
airflow-data-platform-dev-Worker      # Worker logs
```

### Viewing Logs

```bash
# DAG processing logs
aws logs tail airflow-data-platform-dev-DAG --follow

# Task logs for specific DAG run
aws logs tail airflow-data-platform-dev-Task --follow --filter-pattern "sample_hello_world"
```

**Retention**: 7 days (configurable in Terraform)

---

## Python Dependencies

### requirements.txt

Located at: `airflow/requirements.txt`

```
apache-airflow-providers-amazon==8.13.0
apache-airflow-providers-postgres==5.8.0
astronomer-cosmos==1.4.0
boto3==1.34.0
psycopg2-binary==2.9.9
```

### Updating Dependencies

1. Edit `airflow/requirements.txt`
2. Upload to S3:
   ```bash
   aws s3 cp airflow/requirements.txt s3://${MWAA_BUCKET}/requirements.txt
   ```
3. MWAA will automatically update (takes 10-20 minutes)
4. Monitor in AWS console: Environment status will show "Updating"

### Version Pinning

✅ **Always pin versions** to avoid breaking changes
❌ **Never use** unpinned packages like `boto3` (use `boto3==1.34.0`)

---

## Secrets Management

### Airflow Connections via Secrets Manager

MWAA is configured to use Secrets Manager for connections:

**Secret Naming**:
- Prefix: `airflow/connections/`
- Example: `airflow/connections/redshift_default`

**Secret Format** (JSON):
```json
{
  "conn_type": "redshift",
  "host": "cluster-endpoint.region.redshift.amazonaws.com",
  "port": 5439,
  "schema": "analytics",
  "login": "admin",
  "password": "secret-password"
}
```

### Airflow Variables via Secrets Manager

**Secret Naming**:
- Prefix: `airflow/variables/`
- Example: `airflow/variables/dbt_project_dir`

**Usage in DAG**:
```python
from airflow.models import Variable

project_dir = Variable.get("dbt_project_dir")
```

---

## Troubleshooting

### DAG Not Appearing in UI

1. **Check S3**: Verify file uploaded
   ```bash
   aws s3 ls s3://${MWAA_BUCKET}/dags/
   ```

2. **Check DAG Processing Logs**:
   ```bash
   aws logs tail airflow-data-platform-dev-DAG --follow
   ```

3. **Look for Python errors**: Syntax errors prevent DAG from loading

4. **Wait 5 minutes**: Auto-sync interval

### MWAA Environment Creation Failed

1. **Check subnet configuration**: Must be private subnets
2. **Check security group**: Self-referencing rule required
3. **Check S3 bucket**: Must exist with proper structure
4. **Check IAM role**: Execution role needs proper permissions

### Task Failures

1. **Check Task Logs**:
   ```bash
   aws logs tail airflow-data-platform-dev-Task --follow
   ```

2. **Check Worker Logs**:
   ```bash
   aws logs tail airflow-data-platform-dev-Worker --follow
   ```

3. **Verify IAM permissions**: Task execution role needs resource access

### requirements.txt Update Failed

1. **Check syntax**: Must be valid pip format
2. **Check package availability**: All packages must exist in PyPI
3. **Check for conflicts**: Version conflicts cause failures
4. **Monitor status**: AWS console shows update progress

---

## Cost Optimization

### Development Environment

- Use `mw1.small` if possible (~$350/month vs $700/month)
- Set `max_workers = 1` for dev
- Reduce log retention to 3-7 days

### Stopping MWAA (Not Recommended)

MWAA doesn't support stop/start. To save costs:

1. **Destroy environment**: `terraform destroy -target=module.orchestration`
2. **DAGs preserved** in S3
3. **Recreate** when needed (~30 min setup time)

**Better approach**: Use small environment for dev, scale up for production

---

## Best Practices

### DAG Development

✅ Use `catchup=False` to prevent backfill on deploy
✅ Set reasonable `retries` and `retry_delay`
✅ Use `tags` to organize DAGs
✅ Add docstrings to DAGs and tasks
✅ Test DAGs locally before upload

### Resource Management

✅ Monitor CloudWatch metrics
✅ Set appropriate `max_workers` for environment class
✅ Use task pools for rate limiting
✅ Set SLAs for critical DAGs

### Security

✅ Use `PRIVATE_ONLY` webserver access for production
✅ Store credentials in Secrets Manager, not code
✅ Rotate secrets regularly
✅ Limit IAM role permissions (principle of least privilege)

---

## Monitoring

### Key Metrics (CloudWatch)

- `QueuedTasks` - Tasks waiting to run
- `RunningTasks` - Currently executing tasks
- `WorkersRunning` - Active workers
- `WorkersAvailable` - Available worker slots

### Alarms to Create

1. **High queue depth**: `QueuedTasks > 10` for 5 minutes
2. **No workers**: `WorkersRunning = 0` for 5 minutes
3. **Environment unhealthy**: `EnvironmentStatus != AVAILABLE`

---

## Next Steps

After MWAA is deployed:

1. **Sprint 8**: Integrate dbt with Cosmos
2. **Sprint 9**: Add CI/CD for DAG deployment
3. **Sprint 10**: Event-driven pipelines
4. **Sprint 12**: Monitoring and alerting

EOF

# Create MWAA operations guide
cat > MWAA_OPERATIONS.md <<'EOF'
# MWAA Operations Guide

## Daily Operations

### Checking MWAA Health

```bash
# Via AWS CLI
aws mwaa get-environment --name data-platform-airflow-dev \
    --query 'Environment.Status'

# Should return: "AVAILABLE"
```

### Deploying New DAGs

```bash
# 1. Create/edit DAG in airflow/dags/
# 2. Sync to S3
./scripts/airflow/sync-to-mwaa.sh dev

# 3. Wait 5 minutes
# 4. Check Airflow UI
```

### Triggering DAGs

**Via UI**:
1. Open Airflow UI
2. Find DAG
3. Click play button (▶)
4. Confirm

**Via CLI**:
```bash
# Trigger DAG run
aws mwaa create-cli-token --name data-platform-airflow-dev \
    | jq -r '.CliToken' \
    | xargs -I {} curl -X POST "https://WEBSERVER_URL/api/v1/dags/sample_hello_world/dagRuns" \
    -H "Authorization: Bearer {}"
```

### Viewing Logs

```bash
# Follow DAG processing logs
aws logs tail airflow-data-platform-dev-DAG --follow

# Follow task logs
aws logs tail airflow-data-platform-dev-Task --follow

# Filter for specific DAG
aws logs tail airflow-data-platform-dev-Task \
    --follow \
    --filter-pattern "sample_hello_world"
```

---

## Updating Dependencies

### Update requirements.txt

```bash
# 1. Edit airflow/requirements.txt
vim airflow/requirements.txt

# 2. Upload to S3
MWAA_BUCKET=$(cd terraform/environments/dev && terraform output -json storage | jq -r '.mwaa_bucket_id')
aws s3 cp airflow/requirements.txt s3://${MWAA_BUCKET}/requirements.txt

# 3. Monitor update (AWS Console)
# Environment status: "Updating" → "Available" (10-20 minutes)

# 4. Verify via Airflow UI
# Admin → System → Packages
```

---

## Managing Connections

### Create Redshift Connection

```bash
# Create secret in Secrets Manager
aws secretsmanager create-secret \
    --name airflow/connections/redshift_default \
    --secret-string '{
        "conn_type": "redshift",
        "host": "your-cluster.us-east-1.redshift.amazonaws.com",
        "port": 5439,
        "schema": "analytics",
        "login": "airflow_user",
        "password": "your-password"
    }'

# Use in DAG
from airflow.providers.amazon.aws.hooks.redshift_sql import RedshiftSQLHook

hook = RedshiftSQLHook(redshift_conn_id='redshift_default')
```

### List All Connections

```bash
# In Airflow UI: Admin → Connections
# Via Secrets Manager:
aws secretsmanager list-secrets \
    --filters Key=name,Values=airflow/connections/ \
    --query 'SecretList[*].Name'
```

---

## Troubleshooting

### DAG Import Errors

**Symptom**: DAG not showing in UI

**Debug**:
```bash
# Check DAG processing logs
aws logs tail airflow-data-platform-dev-DAG --follow

# Look for Python errors, missing imports
```

**Common Issues**:
- Syntax errors in DAG file
- Missing package in requirements.txt
- Circular imports

### Task Stuck in Queue

**Symptom**: Task shows "scheduled" or "queued" for long time

**Debug**:
```bash
# Check worker capacity
# Via Airflow UI: Browse → Task Instances → State = queued

# Check scheduler logs
aws logs tail airflow-data-platform-dev-Scheduler --follow
```

**Solutions**:
- Increase `max_workers` in environment
- Check if previous task failed (blocking)
- Verify task pool limits

### High Costs

**Symptom**: Unexpected AWS bill

**Investigate**:
```bash
# Check environment class
aws mwaa get-environment --name data-platform-airflow-dev \
    --query 'Environment.EnvironmentClass'

# Check CloudWatch metrics for worker usage
```

**Solutions**:
- Downsize environment class
- Reduce log retention
- Delete old log groups
- Set `max_workers` appropriately

---

## Maintenance

### Weekly Tasks

- [ ] Review failed DAG runs
- [ ] Check CloudWatch logs for errors
- [ ] Verify no DAGs in "import error" state
- [ ] Review task execution times

### Monthly Tasks

- [ ] Update Python dependencies (security patches)
- [ ] Review CloudWatch metrics (worker utilization)
- [ ] Clean up old DAGs from S3
- [ ] Review IAM role permissions

---

## Emergency Procedures

### MWAA Environment Down

1. **Check AWS Service Health Dashboard**
2. **Review CloudWatch Logs** for errors
3. **Contact AWS Support** if service issue
4. **Consider recreating environment**:
   ```bash
   cd terraform/environments/dev
   terraform destroy -target=module.orchestration
   terraform apply -target=module.orchestration
   # Takes ~30 minutes
   ```

### All Tasks Failing

1. **Check IAM permissions** on execution role
2. **Verify network connectivity** (security groups, VPC endpoints)
3. **Check Secrets Manager access**
4. **Review recent requirements.txt changes**

---

## Scaling

### Increasing Capacity

**Edit Terraform** (`terraform/environments/dev/orchestration.tf`):

```hcl
module "orchestration" {
  # ...
  environment_class = "mw1.large"  # Was: mw1.medium
}
```

**Apply**:
```bash
cd terraform/environments/dev
terraform apply
# Takes ~20 minutes
```

### Auto-scaling Workers

MWAA auto-scales workers within environment class limits:
- Small: 1-2 workers
- Medium: 1-10 workers
- Large: 1-25 workers

**Configure** via Airflow config:
```hcl
airflow_configuration_options = {
  "celery.worker_autoscale" = "10,1"  # max,min
}
```

EOF
```

---

## End of Day 1 Checklist

- [x] MWAA Terraform module created
- [x] MWAA S3 bucket structure configured
- [x] requirements.txt uploaded to S3
- [x] Sample DAGs created (hello_world, aws_test)
- [x] Sync script automated
- [x] MWAA module added to dev environment (not applied yet)
- [x] MWAA documentation created

---

## 📝 Daily Standup Notes

**Completed Today**:
- Created MWAA orchestration Terraform module
- Configured MWAA S3 bucket with DAGs/plugins structure
- Uploaded requirements.txt with Airflow providers and Cosmos
- Created sample DAGs for testing
- Automated DAG sync script
- Comprehensive MWAA documentation

**Blockers**:
- None (MWAA deployment will happen tomorrow)

**Tomorrow's Plan**:
- Apply Terraform to create MWAA environment (~30 min)
- While waiting: Test DAG syntax
- Sync DAGs to S3 and verify auto-detection
- Access Airflow UI and trigger sample DAGs
- Configure IAM access for team

---

## 🎯 Success Metrics

```bash
# Terraform module validates
terraform -chdir=terraform/modules/orchestration validate
# Should show: Success! The configuration is valid.

# S3 bucket has correct structure
MWAA_BUCKET=$(cd terraform/environments/dev && terraform output -json storage | jq -r '.mwaa_bucket_id')
aws s3 ls s3://${MWAA_BUCKET}/
# Should show:
# - requirements.txt
# - dags/
# - plugins/

# Sample DAGs exist locally
ls airflow/dags/
# Should show:
# - sample_hello_world.py
# - sample_aws_test.py

# Sync script works
./scripts/airflow/sync-to-mwaa.sh dev
# Should successfully upload files
```

---

## ⏭️ Next: Day 2

Tomorrow: Deploy MWAA environment, sync DAGs, access Airflow UI

**See [day-2.md](./day-2.md)** 🚀
