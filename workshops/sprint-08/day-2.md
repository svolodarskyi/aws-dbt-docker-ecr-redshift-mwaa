# Sprint 8 - Day 2: ECS Task Definition & Manual Testing

**Goal**: Deploy ECS cluster, create dbt task definition, test Fargate execution

**Duration**: ~6 hours

**Outcome**: dbt running successfully in ECS Fargate, CloudWatch logging operational

---

## Morning Session (3 hours)

### Step 1: Complete ECS Task Definition in Terraform (1 hour 30 minutes)

```bash
cd terraform/modules/compute

# Add task definition to main.tf
cat >> main.tf <<'EOF'

# ECS Task Definition for dbt
resource "aws_ecs_task_definition" "dbt_transformation" {
  family                   = "${var.project_name}-dbt-transformation-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory

  execution_role_arn = aws_iam_role.dbt_task_execution.arn
  task_role_arn      = aws_iam_role.dbt_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "dbt"
      image     = "${var.ecr_repository_url}:${var.dbt_image_tag}"
      essential = true

      # Command override (can be overridden at runtime)
      command = ["dbt", "run", "--target", "dev"]

      # Environment variables
      environment = [
        {
          name  = "DBT_PROFILES_DIR"
          value = "/usr/app/dbt/profiles"
        },
        {
          name  = "DBT_TARGET"
          value = var.dbt_target
        }
      ]

      # Secrets from Secrets Manager
      secrets = [
        {
          name      = "REDSHIFT_HOST"
          valueFrom = "${var.redshift_secret_arn}:host::"
        },
        {
          name      = "REDSHIFT_PORT"
          valueFrom = "${var.redshift_secret_arn}:port::"
        },
        {
          name      = "REDSHIFT_USER"
          valueFrom = "${var.redshift_secret_arn}:username::"
        },
        {
          name      = "REDSHIFT_PASSWORD"
          valueFrom = "${var.redshift_secret_arn}:password::"
        },
        {
          name      = "REDSHIFT_DBNAME"
          valueFrom = "${var.redshift_secret_arn}:dbname::"
        }
      ]

      # CloudWatch Logs
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.dbt_tasks.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "dbt"
        }
      }

      # Health check (optional)
      # healthCheck = {
      #   command     = ["CMD-SHELL", "dbt --version || exit 1"]
      #   interval    = 30
      #   timeout     = 5
      #   retries     = 3
      #   startPeriod = 60
      # }
    }
  ])

  tags = {
    Name = "${var.project_name}-dbt-transformation-${var.environment}"
  }
}
EOF

# Add new variables to variables.tf
cat >> variables.tf <<'EOF'

variable "ecr_repository_url" {
  description = "URL of ECR repository containing dbt image"
  type        = string
}

variable "dbt_image_tag" {
  description = "Tag of dbt image to use"
  type        = string
  default     = "latest"
}

variable "task_cpu" {
  description = "CPU units for ECS task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 2048
}

variable "task_memory" {
  description = "Memory for ECS task in MB (512, 1024, 2048, 4096, 8192)"
  type        = number
  default     = 4096
}

variable "dbt_target" {
  description = "dbt target environment (dev, prod)"
  type        = string
  default     = "dev"
}

variable "redshift_secret_arn" {
  description = "ARN of Secrets Manager secret containing Redshift credentials"
  type        = string
}
EOF

# Add outputs
cat >> outputs.tf <<'EOF'

output "dbt_task_definition_arn" {
  description = "ARN of the dbt task definition"
  value       = aws_ecs_task_definition.dbt_transformation.arn
}

output "dbt_task_definition_family" {
  description = "Family of the dbt task definition"
  value       = aws_ecs_task_definition.dbt_transformation.family
}

output "dbt_task_definition_revision" {
  description = "Revision of the dbt task definition"
  value       = aws_ecs_task_definition.dbt_transformation.revision
}
EOF

# Format
terraform fmt -recursive ../../
terraform -chdir=. validate
```

### Step 2: Update Environment Configuration (30 minutes)

```bash
cd ../../environments/dev

# Update compute.tf to include new variables
cat > compute.tf <<'EOF'
module "compute" {
  source = "../../modules/compute"

  project_name = var.project_name
  environment  = var.environment
  region       = data.aws_region.current.name
  account_id   = data.aws_caller_identity.current.account_id

  # S3 buckets
  dbt_artifacts_bucket_arn = module.storage.dbt_artifacts_bucket_arn
  raw_data_bucket_arn      = module.storage.raw_data_bucket_arn

  # ECR repository
  ecr_repository_url = module.ecr.repository_url
  dbt_image_tag      = "latest"

  # Task sizing
  task_cpu    = 2048  # 2 vCPU
  task_memory = 4096  # 4 GB

  # dbt configuration
  dbt_target = "dev"

  # Secrets Manager
  redshift_secret_arn = module.data.redshift_master_secret_arn

  # Logging
  log_retention_days = 7
}

output "compute" {
  value = {
    ecs_cluster_name         = module.compute.ecs_cluster_name
    ecs_cluster_arn          = module.compute.ecs_cluster_arn
    task_execution_role_arn  = module.compute.dbt_task_execution_role_arn
    task_role_arn            = module.compute.dbt_task_role_arn
    task_definition_arn      = module.compute.dbt_task_definition_arn
    task_definition_family   = module.compute.dbt_task_definition_family
    log_group_name           = module.compute.dbt_log_group_name
  }
  sensitive = false
}
EOF

# Validate
terraform fmt -recursive ../../
terraform validate
```

### Step 3: Apply Compute Module (Deploys ECS Cluster & Task Definition) (1 hour)

```bash
# Still in terraform/environments/dev

# Plan
terraform plan -target=module.compute

# Review the plan - should create:
# - ECS cluster
# - CloudWatch log group
# - IAM roles (execution + task)
# - ECS task definition

# Apply
echo "🚀 Creating ECS cluster and task definition..."
terraform apply -target=module.compute

# Save outputs
terraform output compute

# Get task definition details
TASK_DEF_ARN=$(terraform output -json compute | jq -r '.task_definition_arn')
TASK_DEF_FAMILY=$(terraform output -json compute | jq -r '.task_definition_family')
CLUSTER_NAME=$(terraform output -json compute | jq -r '.ecs_cluster_name')

echo "✅ ECS Infrastructure Created"
echo "Cluster: ${CLUSTER_NAME}"
echo "Task Definition: ${TASK_DEF_FAMILY}"
echo "Task ARN: ${TASK_DEF_ARN}"
```

---

## Afternoon Session (3 hours)

### Step 4: Prepare for Manual ECS Task Execution (30 minutes)

```bash
cd ../../../

# Create script to run dbt task manually
cat > scripts/ecs/run-dbt-task.sh <<'EOF'
#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}
DBT_COMMAND=${2:-"dbt run"}

echo "🚀 Running dbt task in ECS Fargate..."

# Get values from Terraform
cd terraform/environments/${ENVIRONMENT}

CLUSTER_NAME=$(terraform output -json compute | jq -r '.ecs_cluster_name')
TASK_DEFINITION=$(terraform output -json compute | jq -r '.task_definition_family')
SUBNET_IDS=$(terraform output -json networking | jq -r '.private_subnet_ids | join(",")')
SECURITY_GROUP=$(terraform output -json networking | jq -r '.default_security_group_id')

cd -

echo "📋 Configuration:"
echo "  Cluster: ${CLUSTER_NAME}"
echo "  Task Definition: ${TASK_DEFINITION}"
echo "  Subnets: ${SUBNET_IDS}"
echo "  Security Group: ${SECURITY_GROUP}"
echo "  Command: ${DBT_COMMAND}"
echo ""

# Convert subnet IDs to JSON array
SUBNET_ARRAY=$(echo $SUBNET_IDS | jq -R 'split(",")' | jq -c .)

# Run task
echo "▶️  Starting ECS task..."
TASK_ARN=$(aws ecs run-task \
    --cluster ${CLUSTER_NAME} \
    --task-definition ${TASK_DEFINITION} \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=${SUBNET_ARRAY},securityGroups=[\"${SECURITY_GROUP}\"],assignPublicIp=DISABLED}" \
    --overrides "{\"containerOverrides\":[{\"name\":\"dbt\",\"command\":[\"sh\",\"-c\",\"${DBT_COMMAND}\"]}]}" \
    --query 'tasks[0].taskArn' \
    --output text)

if [ -z "$TASK_ARN" ]; then
    echo "❌ Failed to start task"
    exit 1
fi

echo "✅ Task started: ${TASK_ARN}"
echo ""

# Wait for task to complete
echo "⏰ Waiting for task to complete..."
aws ecs wait tasks-stopped --cluster ${CLUSTER_NAME} --tasks ${TASK_ARN}

# Get exit code
EXIT_CODE=$(aws ecs describe-tasks \
    --cluster ${CLUSTER_NAME} \
    --tasks ${TASK_ARN} \
    --query 'tasks[0].containers[0].exitCode' \
    --output text)

echo ""
if [ "$EXIT_CODE" = "0" ]; then
    echo "✅ Task completed successfully (exit code: 0)"
else
    echo "❌ Task failed (exit code: ${EXIT_CODE})"
fi

echo ""
echo "📊 View logs:"
echo "  aws logs tail /ecs/${CLUSTER_NAME} --follow --filter-pattern dbt"
echo ""
echo "🔍 Task details:"
aws ecs describe-tasks \
    --cluster ${CLUSTER_NAME} \
    --tasks ${TASK_ARN} \
    --query 'tasks[0].{Status:lastStatus,ExitCode:containers[0].exitCode,StartedAt:startedAt,StoppedAt:stoppedAt}'

exit $EXIT_CODE
EOF

chmod +x scripts/ecs/run-dbt-task.sh

# Create log viewing script
cat > scripts/ecs/view-dbt-logs.sh <<'EOF'
#!/bin/bash

ENVIRONMENT=${1:-dev}

# Get log group name from Terraform
cd terraform/environments/${ENVIRONMENT}
LOG_GROUP=$(terraform output -json compute | jq -r '.log_group_name')
cd -

echo "📋 Viewing dbt task logs from: ${LOG_GROUP}"
echo "Press Ctrl+C to stop"
echo ""

aws logs tail ${LOG_GROUP} --follow --format short
EOF

chmod +x scripts/ecs/view-dbt-logs.sh
```

### Step 5: Test Running dbt in ECS (1 hour 30 minutes)

**Test 1: dbt debug**:
```bash
# Test basic connectivity
./scripts/ecs/run-dbt-task.sh dev "dbt debug"

# In another terminal, watch logs
./scripts/ecs/view-dbt-logs.sh dev
```

**Expected output**:
- Connection to Redshift successful
- dbt profiles loaded
- All checks passing

**Test 2: dbt run (small subset)**:
```bash
# Run specific model
./scripts/ecs/run-dbt-task.sh dev "dbt run --select stg_customers"

# Check logs for success
```

**Test 3: dbt run (full pipeline)**:
```bash
# Run all models
./scripts/ecs/run-dbt-task.sh dev "dbt run"

# Watch logs in real-time
./scripts/ecs/view-dbt-logs.sh dev
```

**Expected output**:
- All external tables refreshed
- Staging models created
- Intermediate models created
- Mart models created
- All tests passing

**Verify in Redshift**:
```bash
# Connect to Redshift
cd dbt
source ../.venv/bin/activate

# Check that tables exist
dbt run-operation query \
    --args "{sql: \"SELECT schemaname, tablename FROM pg_tables WHERE schemaname IN ('staging', 'analytics') ORDER BY schemaname, tablename\"}"

# Count records in mart tables
dbt run-operation query \
    --args "{sql: \"SELECT COUNT(*) FROM analytics.customers_dim\"}"
```

### Step 6: Create ECS Operations Documentation (1 hour)

```bash
cd docs

cat > ECS_DBT_OPERATIONS.md <<'EOF'
# ECS dbt Operations Guide

## Architecture

**Components**:
- **ECS Cluster**: `data-platform-dbt-dev`
- **Task Definition**: `data-platform-dbt-transformation-dev`
- **Launch Type**: Fargate (serverless)
- **Network**: Private subnets, no public IP
- **Resources**: 2 vCPU, 4 GB RAM
- **Logging**: CloudWatch Logs (`/ecs/data-platform-dbt-dev`)

---

## Running dbt Tasks

### Via Script (Recommended)

```bash
# Run full pipeline
./scripts/ecs/run-dbt-task.sh dev "dbt run"

# Run specific model
./scripts/ecs/run-dbt-task.sh dev "dbt run --select stg_customers"

# Run tests
./scripts/ecs/run-dbt-task.sh dev "dbt test"

# Run and test
./scripts/ecs/run-dbt-task.sh dev "dbt build"
```

### Via AWS CLI

```bash
# Get configuration
cd terraform/environments/dev
CLUSTER=$(terraform output -json compute | jq -r '.ecs_cluster_name')
TASK_DEF=$(terraform output -json compute | jq -r '.task_definition_family')
SUBNETS=$(terraform output -json networking | jq -r '.private_subnet_ids | join(",")')
SG=$(terraform output -json networking | jq -r '.default_security_group_id')

# Run task
aws ecs run-task \
    --cluster ${CLUSTER} \
    --task-definition ${TASK_DEF} \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[${SUBNETS}],securityGroups=[\"${SG}\"],assignPublicIp=DISABLED}" \
    --overrides '{"containerOverrides":[{"name":"dbt","command":["dbt","run"]}]}'
```

---

## Monitoring

### View Logs

**Real-time**:
```bash
./scripts/ecs/view-dbt-logs.sh dev
```

**Specific time range**:
```bash
aws logs tail /ecs/data-platform-dbt-dev \
    --since 1h \
    --format short
```

**Filter for errors**:
```bash
aws logs tail /ecs/data-platform-dbt-dev \
    --follow \
    --filter-pattern "ERROR"
```

### Check Task Status

**List recent tasks**:
```bash
aws ecs list-tasks --cluster data-platform-dbt-dev --max-items 10
```

**Describe specific task**:
```bash
TASK_ARN=<task-arn-from-list>

aws ecs describe-tasks \
    --cluster data-platform-dbt-dev \
    --tasks ${TASK_ARN} \
    --query 'tasks[0].{Status:lastStatus,ExitCode:containers[0].exitCode,CPU:cpu,Memory:memory,StartedAt:startedAt,StoppedAt:stoppedAt}'
```

### CloudWatch Metrics

- **CPUUtilization**: Task CPU usage
- **MemoryUtilization**: Task memory usage
- **TaskCount**: Number of running tasks

---

## Troubleshooting

### Task Fails to Start

**Check**:
1. **ECR image exists**: `aws ecr describe-images --repository-name data-platform-dbt-dev`
2. **Subnets have NAT access**: Tasks need internet for ECR pull
3. **Security group allows outbound HTTPS**: For ECR and Secrets Manager
4. **IAM roles have correct permissions**

**Logs**:
```bash
aws ecs describe-tasks \
    --cluster data-platform-dbt-dev \
    --tasks <task-arn> \
    --query 'tasks[0].containers[0].reason'
```

### Task Starts but Fails Immediately

**Check logs**:
```bash
aws logs tail /ecs/data-platform-dbt-dev --since 5m
```

**Common issues**:
- Redshift credentials incorrect (check Secrets Manager)
- Network connectivity to Redshift
- dbt profiles.yml misconfigured
- Missing dbt models/files in Docker image

### Slow Task Execution

**Check CloudWatch metrics**:
- High CPU/Memory usage → Increase task resources
- Long-running queries → Optimize dbt models

**Update task definition resources**:
```hcl
# In terraform/environments/dev/compute.tf
task_cpu    = 4096  # Increase to 4 vCPU
task_memory = 8192  # Increase to 8 GB
```

---

## Cost Optimization

### Fargate Pricing (us-east-1)

**Current config** (2 vCPU, 4 GB):
- Per hour: ~$0.12
- Per run (30 min): ~$0.06

**Example monthly costs**:
- Daily runs (30 min each): ~$5.40/month
- Hourly runs: ~$162/month

### Optimization Tips

1. **Right-size resources**: Start small, increase if needed
2. **Run on schedule**: Avoid unnecessary runs
3. **Use spot capacity**: ~70% cost savings (coming in Sprint 10)
4. **Optimize dbt models**: Faster runs = lower costs

---

## Task Definition Updates

### Update dbt Image

```bash
# Build and push new image (Sprint 6 process)
cd dbt
./build-dbt-image.sh
./push-to-ecr.sh v1.1.0

# Update task definition to use new tag
cd ../terraform/environments/dev

# Edit compute.tf
vim compute.tf  # Change dbt_image_tag = "v1.1.0"

# Apply
terraform apply -target=module.compute
```

### Update Resources

```bash
cd terraform/environments/dev

# Edit compute.tf
vim compute.tf

# Change:
# task_cpu    = 4096  # 4 vCPU
# task_memory = 8192  # 8 GB

terraform apply -target=module.compute
```

### Update Environment Variables

Add to `terraform/modules/compute/main.tf`:

```hcl
environment = [
  {
    name  = "DBT_PROFILES_DIR"
    value = "/usr/app/dbt/profiles"
  },
  {
    name  = "DBT_TARGET"
    value = var.dbt_target
  },
  {
    name  = "NEW_VAR"
    value = "new_value"
  }
]
```

---

## Security

### Secrets Management

**Redshift credentials**:
- Stored in: AWS Secrets Manager
- Secret: `data-platform/dev/redshift/master`
- Accessed via: ECS task role permissions

**Never**:
- Hard-code credentials
- Log sensitive data
- Store secrets in code

### Network Security

**Current**:
- Tasks run in private subnets
- No public IP
- Outbound internet via NAT gateway (for ECR, Secrets Manager)

**Recommended for production**:
- VPC endpoints for ECR, Secrets Manager, CloudWatch Logs
- No internet access required

### IAM Permissions

**Task Execution Role**: Pulls image, gets secrets, sends logs
**Task Role**: Accesses S3, Redshift (via Secrets Manager), Glue Catalog

**Principle of least privilege**: Only grant necessary permissions

---

## Best Practices

✅ **Tag images** with semantic versions (not just `latest`)
✅ **Monitor task duration** and set appropriate timeouts
✅ **Use structured logging** in dbt (JSON format for easier parsing)
✅ **Set memory/CPU alerts** in CloudWatch
✅ **Test locally** before deploying to ECS
✅ **Version task definitions** (auto-incremented by Terraform)

❌ **Don't** use production credentials in dev environment
❌ **Don't** run tasks manually in production (use Airflow orchestration)
❌ **Don't** ignore task failures (set up alerts)

EOF

# Create quick reference card
cat > ECS_QUICK_REFERENCE.md <<'EOF'
# ECS dbt Quick Reference

## Common Commands

```bash
# Run full dbt pipeline
./scripts/ecs/run-dbt-task.sh dev "dbt run"

# Run specific model
./scripts/ecs/run-dbt-task.sh dev "dbt run --select my_model"

# Run tests only
./scripts/ecs/run-dbt-task.sh dev "dbt test"

# View logs
./scripts/ecs/view-dbt-logs.sh dev

# Debug connection
./scripts/ecs/run-dbt-task.sh dev "dbt debug"
```

## Task Lifecycle

1. **Provisioning**: ECS allocates Fargate resources (~30 sec)
2. **Pending**: Pulling Docker image from ECR (~15-30 sec)
3. **Running**: dbt executing (varies by workload)
4. **Deprovisioning**: Task cleanup (~10 sec)

## Resource Sizing Guide

| Workload | CPU | Memory | Typical Duration | Cost/run |
|----------|-----|--------|------------------|----------|
| Small (<10 models) | 1024 | 2048 | 5-10 min | $0.02 |
| Medium (10-50 models) | 2048 | 4096 | 15-30 min | $0.06 |
| Large (50+ models) | 4096 | 8192 | 30-60 min | $0.24 |

## Troubleshooting Checklist

- [ ] ECR image exists and is tagged correctly
- [ ] Task definition revision is latest
- [ ] Secrets Manager secret exists and is accessible
- [ ] Subnets have route to NAT gateway
- [ ] Security group allows outbound HTTPS (443)
- [ ] IAM roles have correct permissions
- [ ] CloudWatch log group exists

EOF
```

---

## End of Day 2 Checklist

- [x] ECS cluster created (`data-platform-dbt-dev`)
- [x] CloudWatch log group created
- [x] ECS task definition created with dbt image
- [x] Task definition configured with Secrets Manager integration
- [x] Compute module applied successfully
- [x] dbt debug test passed in ECS
- [x] dbt run executed successfully in Fargate
- [x] CloudWatch logs capturing dbt output
- [x] Data verified in Redshift
- [x] ECS operations documentation created

---

## 📝 Daily Standup Notes

**Completed Today**:
- Created ECS task definition for dbt in Terraform
- Deployed ECS cluster and task definition
- Successfully ran dbt in ECS Fargate
- Verified all dbt models execute correctly
- CloudWatch logging operational
- Created run and monitoring scripts
- Comprehensive ECS operations documentation

**Blockers**:
- None

**Tomorrow's Plan**:
- Create Airflow DAG with Cosmos library
- Integrate Airflow → ECS → dbt
- Test end-to-end orchestration
- Sprint demo and retrospective

---

## 🎯 Success Metrics

```bash
# ECS cluster exists
aws ecs describe-clusters --clusters data-platform-dbt-dev \
    --query 'clusters[0].status'
# Should output: ACTIVE

# Task definition exists
aws ecs describe-task-definition \
    --task-definition data-platform-dbt-transformation-dev \
    --query 'taskDefinition.{Family:family,Revision:revision,Status:status}'
# Should show latest revision

# Can run dbt task
./scripts/ecs/run-dbt-task.sh dev "dbt --version"
# Should complete successfully (exit code 0)

# Logs visible in CloudWatch
aws logs describe-log-streams \
    --log-group-name /ecs/data-platform-dbt-dev \
    --max-items 5
# Should show recent log streams

# Data in Redshift
# Query analytics.customers_dim should return rows
```

---

## ⏭️ Next: Day 3

Tomorrow: Cosmos DAG creation, Airflow→ECS integration, end-to-end demo

**See [day-3.md](./day-3.md)** 🚀
