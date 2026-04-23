# Sprint 11 - Day 1: Production Environment Setup

**Goal**: Create production Terraform environment with enhanced configuration

**Duration**: ~6 hours

**Outcome**: Production infrastructure ready for deployment

---

## Morning Session (3 hours)

### Step 1: Create Production Environment (1 hour 30 minutes)

```bash
cd terraform/environments
cp -r dev prod

cd prod

# Update variables for production
cat > terraform.tfvars <<'EOF'
project_name = "data-platform"
environment  = "prod"

# Larger instance sizes for production
redshift_node_type  = "ra3.xlplus"
redshift_nodes      = 3  # Multi-node for HA

# MWAA production sizing
mwaa_environment_class = "mw1.large"
mwaa_max_workers      = 25

# Enhanced monitoring
enable_enhanced_monitoring = true
log_retention_days        = 30  # Longer retention for prod

# Backup configuration
enable_automated_backups = true
backup_retention_days    = 7
cross_region_backup     = true
EOF

# Update backend configuration
cat > backend.tf <<'EOF'
terraform {
  backend "s3" {
    bucket         = "data-platform-terraform-state-prod"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "data-platform-terraform-locks-prod"
    encrypt        = true
  }
}
EOF
```

### Step 2: Create Production S3 Backend (30 minutes)

```bash
# Create production state bucket
aws s3 mb s3://data-platform-terraform-state-prod --region us-east-1

aws s3api put-bucket-versioning \
  --bucket data-platform-terraform-state-prod \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket data-platform-terraform-state-prod \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Create DynamoDB lock table
aws dynamodb create-table \
  --table-name data-platform-terraform-locks-prod \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### Step 3: Update dbt for Production (1 hour)

```bash
cd ../../../dbt

# Update profiles.yml for production target
cat > profiles/profiles.yml <<'EOF'
data_platform:
  target: "{{ env_var('DBT_TARGET', 'dev') }}"
  outputs:
    dev:
      type: redshift
      host: "{{ env_var('REDSHIFT_HOST') }}"
      port: 5439
      user: "{{ env_var('REDSHIFT_USER') }}"
      password: "{{ env_var('REDSHIFT_PASSWORD') }}"
      dbname: dev
      schema: analytics
      threads: 4

    prod:
      type: redshift
      host: "{{ env_var('REDSHIFT_HOST') }}"
      port: 5439
      user: "{{ env_var('REDSHIFT_USER') }}"
      password: "{{ env_var('REDSHIFT_PASSWORD') }}"
      dbname: prod
      schema: analytics
      threads: 8
      keepalives_idle: 0
      connect_timeout: 10
EOF
```

---

## Afternoon Session (3 hours)

### Step 4: Create Production IAM Roles (1 hour)

```bash
cd ../../terraform/environments/prod

# Production has stricter IAM policies
cat > iam-prod.tf <<'EOF'
# Production-specific IAM restrictions
resource "aws_iam_role_policy" "prod_restrictions" {
  name = "production-restrictions"
  role = module.iam.admin_role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Deny"
        Action = [
          "s3:DeleteBucket",
          "dynamodb:DeleteTable",
          "rds:DeleteDBInstance"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = "us-east-1"
          }
        }
      }
    ]
  })
}
EOF
```

### Step 5: Configure Enhanced Monitoring (1 hour)

```bash
# Enable CloudWatch detailed monitoring
cat >> main.tf <<'EOF'

# Enhanced CloudWatch monitoring for production
resource "aws_cloudwatch_log_metric_filter" "error_rate" {
  name           = "prod-error-rate"
  log_group_name = "/aws/mwaa/data-platform-airflow-prod"

  pattern = "[ERROR]"

  metric_transformation {
    name      = "ErrorCount"
    namespace = "DataPlatform/Prod"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  alarm_name          = "prod-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ErrorCount"
  namespace           = "DataPlatform/Prod"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "Alert when error rate exceeds threshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_sns_topic" "alerts" {
  name = "data-platform-prod-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
EOF
```

### Step 6: Document Production Deployment (1 hour)

```bash
cd ../../../docs

cat > PRODUCTION_DEPLOYMENT.md <<'EOF'
# Production Deployment Guide

## Prerequisites

- [ ] All dev testing complete
- [ ] Security audit passed
- [ ] Performance testing completed
- [ ] Runbooks prepared
- [ ] Team trained

## Deployment Steps

### 1. Create Production Backend

```bash
cd terraform/environments/prod
terraform init
```

### 2. Review Plan

```bash
terraform plan -out=prod.tfplan
# Review thoroughly with team
```

### 3. Apply (Requires Approval)

```bash
# In GitHub: Create PR to main branch
# Requires 2 approvals
# Manual deployment trigger after approval
```

### 4. Smoke Tests

- Upload test file to prod S3
- Verify EventBridge triggers
- Check dbt runs successfully
- Validate data in Redshift

## Production Safeguards

- Branch protection on main
- Required approvals (2+)
- Manual deployment trigger
- Automated rollback on failure
- Cross-region backups
- Enhanced monitoring

## Production vs Dev

| Feature | Dev | Prod |
|---------|-----|------|
| Redshift | dc2.large (1 node) | ra3.xlplus (3 nodes) |
| MWAA | Small (1 worker) | Large (1-25 workers) |
| Backups | Daily, 1 day | Daily, 7 days, cross-region |
| Monitoring | Basic | Enhanced + PagerDuty |
| Cost | ~$500/month | ~$2,500/month |

EOF
```

---

## End of Day 1 Checklist

- [x] Production environment directory created
- [x] Production variables configured
- [x] S3 backend for prod state
- [x] dbt production profile
- [x] Production IAM policies
- [x] Enhanced monitoring configured
- [x] Deployment documentation

---

## 📝 Daily Standup Notes

**Completed Today**:
- Production Terraform environment scaffolding
- Enhanced configuration (larger instances, HA)
- Production-specific IAM policies
- CloudWatch enhanced monitoring
- Deployment procedures documented

**Blockers**:
- None (ready for Day 2 deployment)

**Tomorrow's Plan**:
- Apply production infrastructure
- Security hardening
- Bastion host setup
- VPN configuration

---

## 🎯 Success Metrics

```bash
# Production environment validates
cd terraform/environments/prod
terraform validate

# Backend configured
terraform init
# Should initialize without errors

# Variables set correctly
grep prod terraform.tfvars
# Should show prod-specific values
```

---

## ⏭️ Next: Day 2

Tomorrow: Deploy production, security hardening, access controls

**See [day-2.md](./day-2.md)** 🚀
