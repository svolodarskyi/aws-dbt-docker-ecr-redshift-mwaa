# How to Use This Repository - Complete Guide

## 📋 What You Have

This repository contains a **complete AWS data engineering platform** with:
- Infrastructure code (Terraform)
- Data transformation (dbt)
- Orchestration (Airflow DAGs)
- CI/CD pipelines (GitHub Actions)
- Documentation and guides

## 🎯 Quick Start (5 Steps)

### Step 1: Read Documentation (30 minutes)

**Start here** - Read these files in order:

```bash
# 1. Project overview
cat README.md

# 2. What changed based on your requirements
cat CHANGES_SUMMARY.md

# 3. Architecture design
cat SIMPLIFIED_ARCHITECTURE.md

# 4. This file - how to use everything
# (you're reading it now!)
```

### Step 2: Set Up Your Local Environment (15 minutes)

```bash
# Run the setup script
./scripts/setup/local-setup.sh

# This will:
# - Create Python virtual environment
# - Install dependencies
# - Set up pre-commit hooks
# - Create .env.local from template
# - Initialize dbt project
```

### Step 3: Configure AWS (10 minutes)

```bash
# Configure AWS CLI with your credentials
aws configure --profile data-platform-dev

# Test connectivity
aws sts get-caller-identity --profile data-platform-dev
```

### Step 4: Bootstrap Terraform State Backend (5 minutes)

```bash
# Create S3 + DynamoDB for Terraform state
cd terraform/bootstrap
terraform init
terraform apply

# Back up the bootstrap state
cp terraform.tfstate ~/backups/terraform-bootstrap-$(date +%Y%m%d).tfstate

# Return to root
cd ../..
```

### Step 5: Initialize Git Repository

```bash
# Initialize Git
git init

# Add all files
git add .

# Initial commit
git commit -m "Initial setup: AWS Data Platform"

# Create GitHub repo and push
git remote add origin https://github.com/your-org/aws-data-platform.git
git branch -M main
git push -u origin main

# Create develop branch
git checkout -b develop
git push -u origin develop
```

**You're now ready to start Sprint 1!** 🎉

---

## 📖 Detailed Usage Guide

### Phase 1: Initial Setup (Day 1-3)

#### 1.1 Clone and Set Up Locally

```bash
# If starting from GitHub
git clone https://github.com/your-org/aws-data-platform.git
cd aws-data-platform

# Run setup
./scripts/setup/local-setup.sh

# Activate virtual environment
source venv/bin/activate

# Verify setup
./scripts/setup/verify-setup.sh
```

#### 1.2 Configure Environment Variables

```bash
# Edit .env.local with your values
vim .env.local

# Required values:
# - AWS_ACCOUNT_ID
# - AWS_REGION
# - REDSHIFT_* (after Redshift is created)
# - S3 bucket names
```

#### 1.3 Test dbt Locally

```bash
cd dbt

# Install dbt packages
dbt deps

# Test connection (will fail until Redshift exists - that's OK)
dbt debug --profiles-dir ./profiles --target dev

# Compile models (doesn't need database)
dbt compile --profiles-dir ./profiles --target dev
```

### Phase 2: Deploy Infrastructure (Day 4-12)

#### 2.1 Bootstrap Terraform Backend

```bash
cd terraform/bootstrap

# Initialize
terraform init

# Review plan
terraform plan

# Apply
terraform apply

# IMPORTANT: Back up state
cp terraform.tfstate ~/backups/terraform-bootstrap-$(date +%Y%m%d).tfstate
```

#### 2.2 Deploy DEV Environment

```bash
cd ../environments/dev

# Initialize (now uses remote state)
terraform init

# Review what will be created
terraform plan

# Apply infrastructure
terraform apply

# This creates:
# - VPC and networking
# - S3 buckets
# - Redshift cluster
# - MWAA environment
# - ECS cluster
# - ECR repository
# - CloudWatch monitoring
# - IAM roles
```

**Note**: This takes ~30-45 minutes to complete.

#### 2.3 Save Outputs

```bash
# Save outputs for reference
terraform output > ../../outputs-dev.txt

# Important outputs:
# - Redshift endpoint
# - MWAA Airflow URL
# - ECR repository URL
# - S3 bucket names
```

#### 2.4 Update .env.local with Real Values

```bash
cd ../../..

# Edit .env.local with actual values from terraform output
vim .env.local

# Update:
REDSHIFT_HOST_DEV=<from terraform output>
S3_RAW_DATA_BUCKET=<from terraform output>
S3_MWAA_BUCKET=<from terraform output>
ECR_REPOSITORY=<from terraform output>
```

### Phase 3: Build and Deploy dbt (Day 13-18)

#### 3.1 Develop dbt Models Locally

```bash
cd dbt

# Create a sample model
cat > models/staging/stg_sample.sql <<EOF
{{ config(materialized='view') }}

SELECT
    1 as id,
    'sample' as name,
    current_timestamp as created_at
EOF

# Run locally
dbt run --profiles-dir ./profiles --target dev --select stg_sample

# Test
dbt test --profiles-dir ./profiles --target dev --select stg_sample
```

#### 3.2 Build dbt Docker Image

```bash
# Build Docker image
docker build -t dbt-project:local ./dbt

# Test the container
docker run --rm \
  -e DBT_TARGET=dev \
  -e REDSHIFT_HOST_DEV=$REDSHIFT_HOST_DEV \
  -e REDSHIFT_USER_DEV=$REDSHIFT_USER_DEV \
  -e REDSHIFT_PASSWORD_DEV=$REDSHIFT_PASSWORD_DEV \
  dbt-project:local compile
```

#### 3.3 Push to ECR

```bash
# Get ECR repository URL from terraform output
ECR_REPO=$(cd terraform/environments/dev && terraform output -raw ecr_repository_url)

# Login to ECR
aws ecr get-login-password --region us-east-1 --profile data-platform-dev | \
  docker login --username AWS --password-stdin $ECR_REPO

# Tag image
docker tag dbt-project:local $ECR_REPO:latest

# Push to ECR
docker push $ECR_REPO:latest
```

### Phase 4: Deploy Airflow DAGs (Day 19-24)

#### 4.1 Test DAG Locally

```bash
# Test DAG imports without errors
python airflow/dags/sample_dag.py

# If no errors, the DAG is valid
echo "DAG is valid!"
```

#### 4.2 Deploy DAGs to MWAA

```bash
# Get MWAA bucket from terraform output
MWAA_BUCKET=$(cd terraform/environments/dev && terraform output -raw mwaa_bucket_name)

# Sync DAGs to S3
aws s3 sync ./airflow/dags/ s3://$MWAA_BUCKET/dags/ --profile data-platform-dev

# Sync plugins (if any)
aws s3 sync ./airflow/plugins/ s3://$MWAA_BUCKET/plugins/ --profile data-platform-dev

# Upload requirements.txt
aws s3 cp ./airflow/requirements.txt s3://$MWAA_BUCKET/requirements.txt --profile data-platform-dev

# Wait for MWAA to sync (takes ~5 minutes)
sleep 300
```

#### 4.3 Access Airflow UI

```bash
# Get MWAA environment name
MWAA_ENV=$(cd terraform/environments/dev && terraform output -raw mwaa_environment_name)

# Get Airflow web server URL
aws mwaa get-environment --name $MWAA_ENV --query 'Environment.WebserverUrl' --output text --profile data-platform-dev

# Open the URL in your browser
# Login uses AWS IAM authentication (automatic if using AWS Console)
```

#### 4.4 Trigger DAG Manually

**Method 1: Airflow UI**
1. Open Airflow URL
2. Find your DAG
3. Click the "Play" button

**Method 2: Script**
```bash
# Using bash script
./scripts/trigger-dag.sh sample_hello_world dev

# Using Python script
python scripts/trigger_dag.py dev sample_hello_world
```

### Phase 5: Set Up CI/CD (Day 25-27)

#### 5.1 Configure GitHub Secrets

Go to GitHub repo → Settings → Secrets and variables → Actions

Add these secrets:
```
AWS_ROLE_TO_ASSUME_DEV=arn:aws:iam::ACCOUNT:role/github-actions-role
AWS_ROLE_TO_ASSUME_PROD=arn:aws:iam::ACCOUNT:role/github-actions-role
MWAA_BUCKET_DEV=data-platform-mwaa-dev
MWAA_BUCKET_PROD=data-platform-mwaa-prod
REDSHIFT_HOST_DEV=dev-cluster.redshift.amazonaws.com
REDSHIFT_USER_DEV=dbt_dev_user
REDSHIFT_PASSWORD_DEV=<from-secrets-manager>
```

#### 5.2 Create GitHub OIDC Provider in AWS

```bash
# Create OIDC provider for GitHub Actions
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
  --profile data-platform-dev

# Create IAM role for GitHub Actions
# (Use Terraform module or create manually - see documentation)
```

#### 5.3 Test CI/CD Pipeline

```bash
# Create a feature branch
git checkout -b feature/test-cicd

# Make a small change
echo "# Test" >> test.txt

# Commit and push
git add test.txt
git commit -m "test: CI/CD pipeline"
git push origin feature/test-cicd

# Create PR on GitHub
# - CI will run (lint, test, validate)
# - Merge to develop
# - CD will auto-deploy to DEV
```

### Phase 6: Deploy to Production (Day 31-33)

#### 6.1 Deploy PROD Infrastructure

```bash
cd terraform/environments/prod

# Initialize
terraform init

# Plan
terraform plan -out=tfplan

# Review plan carefully!
cat tfplan

# Apply (requires manual approval in GitHub Actions)
terraform apply tfplan
```

#### 6.2 Deploy dbt to PROD

```bash
# Merge develop to main (via PR)
git checkout main
git pull origin main

# GitHub Actions will:
# 1. Build dbt Docker image
# 2. Scan for vulnerabilities
# 3. Wait for manual approval
# 4. Push to PROD ECR
# 5. Sync DAGs to PROD MWAA
```

#### 6.3 Verify PROD Deployment

```bash
# Access PROD Airflow UI
# (URL from terraform output)

# Trigger test DAG
./scripts/trigger-dag.sh sample_hello_world prod

# Monitor execution
# Check CloudWatch logs
# Verify data in Redshift
```

---

## 🔄 Daily Development Workflow

### Working on dbt Models

```bash
# 1. Create feature branch
git checkout develop
git pull origin develop
git checkout -b feature/add-customer-model

# 2. Create/edit dbt model
vim dbt/models/marts/customers_dim.sql

# 3. Test locally
cd dbt
dbt run --profiles-dir ./profiles --target dev --select customers_dim
dbt test --profiles-dir ./profiles --target dev --select customers_dim

# 4. Add documentation
vim dbt/models/marts/schema.yml

# 5. Run pre-commit hooks
cd ..
pre-commit run --all-files

# 6. Commit and push
git add dbt/models/marts/
git commit -m "feat: add customer dimension model"
git push origin feature/add-customer-model

# 7. Create PR on GitHub
# 8. After CI passes and approval, merge to develop
# 9. Auto-deploys to DEV
# 10. Test in DEV environment
# 11. Create PR to main for PROD deployment
```

### Working on Airflow DAGs

```bash
# 1. Create feature branch
git checkout -b feature/add-data-pipeline

# 2. Create/edit DAG
vim airflow/dags/customer_pipeline.py

# 3. Test syntax locally
python airflow/dags/customer_pipeline.py

# 4. Commit and push
git add airflow/dags/customer_pipeline.py
git commit -m "feat: add customer data pipeline"
git push origin feature/add-data-pipeline

# 5. Create PR, merge to develop
# 6. Auto-deploys to DEV MWAA
# 7. Test by triggering in Airflow UI
```

### Working on Infrastructure

```bash
# 1. Create feature branch
git checkout -b feature/add-monitoring

# 2. Edit Terraform
vim terraform/modules/monitoring/cloudwatch.tf

# 3. Validate
cd terraform/environments/dev
terraform fmt
terraform validate
terraform plan

# 4. Commit
git add terraform/modules/monitoring/
git commit -m "feat: add CloudWatch dashboard"
git push origin feature/add-monitoring

# 5. Create PR
# 6. After approval, merge to develop
# 7. Auto-deploys infrastructure to DEV
```

---

## 🛠️ Common Tasks

### Trigger a DAG Manually

```bash
# Method 1: Airflow UI (easiest)
# Open MWAA URL → DAGs → Click "Play"

# Method 2: Bash script
./scripts/trigger-dag.sh dbt_transform_daily dev

# Method 3: Python script
python scripts/trigger_dag.py dev dbt_transform_daily

# With configuration
python scripts/trigger_dag.py prod dbt_transform_daily '{"full_refresh": true}'
```

### Check DAG Status

```bash
# View in Airflow UI
# Or check CloudWatch logs
aws logs tail /aws/mwaa/data-platform-airflow-dev/scheduler --follow --profile data-platform-dev
```

### Update dbt Models

```bash
cd dbt

# Run specific model
dbt run --select customers_dim

# Run model and all downstream models
dbt run --select customers_dim+

# Full refresh (drop and recreate)
dbt run --select customers_dim --full-refresh

# Run tests
dbt test --select customers_dim
```

### View dbt Documentation

```bash
cd dbt

# Generate docs
dbt docs generate --profiles-dir ./profiles --target dev

# Serve docs locally
dbt docs serve

# Open browser to http://localhost:8080
```

### Check CloudWatch Logs

```bash
# MWAA scheduler logs
aws logs tail /aws/mwaa/data-platform-airflow-dev/scheduler --follow

# MWAA worker logs
aws logs tail /aws/mwaa/data-platform-airflow-dev/worker --follow

# ECS dbt task logs
aws logs tail /ecs/dbt-transformation --follow

# Redshift logs
aws logs tail /aws/redshift/cluster/data-platform-dev --follow
```

### Pause/Resume Redshift (Cost Savings)

```bash
# Pause Redshift cluster (DEV only, saves ~$350/month)
aws redshift pause-cluster --cluster-identifier data-platform-dev --profile data-platform-dev

# Resume when needed
aws redshift resume-cluster --cluster-identifier data-platform-dev --profile data-platform-dev
```

### Deploy New DAG

```bash
# 1. Create DAG file
vim airflow/dags/my_new_dag.py

# 2. Test syntax
python airflow/dags/my_new_dag.py

# 3. Deploy to DEV
aws s3 cp airflow/dags/my_new_dag.py s3://mwaa-dev-bucket/dags/

# 4. Wait 5 minutes for MWAA to pick it up

# 5. Trigger in Airflow UI or via script
./scripts/trigger-dag.sh my_new_dag dev
```

---

## 📊 Monitoring & Operations

### Check System Health

```bash
# Check MWAA environment
aws mwaa get-environment --name data-platform-airflow-dev --profile data-platform-dev

# Check Redshift cluster
aws redshift describe-clusters --cluster-identifier data-platform-dev --profile data-platform-dev

# Check ECS cluster
aws ecs describe-clusters --clusters dbt-cluster-dev --profile data-platform-dev

# Check CloudWatch alarms
aws cloudwatch describe-alarms --profile data-platform-dev
```

### View Costs

```bash
# Get cost by service (last 30 days)
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --profile data-platform-dev
```

### Backup and Restore

```bash
# Backup Redshift
aws redshift create-cluster-snapshot \
  --cluster-identifier data-platform-dev \
  --snapshot-identifier manual-backup-$(date +%Y%m%d) \
  --profile data-platform-dev

# List snapshots
aws redshift describe-cluster-snapshots --profile data-platform-dev

# Restore from snapshot
aws redshift restore-from-cluster-snapshot \
  --cluster-identifier data-platform-dev-restored \
  --snapshot-identifier manual-backup-20240101 \
  --profile data-platform-dev
```

---

## 🆘 Troubleshooting

### Issue: DAG not showing in Airflow UI

**Solutions**:
```bash
# 1. Check if DAG uploaded to S3
aws s3 ls s3://mwaa-dev-bucket/dags/

# 2. Check DAG syntax
python airflow/dags/your_dag.py

# 3. Check MWAA scheduler logs
aws logs tail /aws/mwaa/data-platform-airflow-dev/scheduler --follow

# 4. Wait 5-10 minutes for MWAA to sync
```

### Issue: dbt run fails

**Solutions**:
```bash
# 1. Check Redshift connection
dbt debug --profiles-dir ./profiles --target dev

# 2. Check ECS task logs
aws logs tail /ecs/dbt-transformation --follow

# 3. Check IAM permissions
aws ecs describe-task-definition --task-definition dbt-transformation-task

# 4. Test manually
docker run --rm -e DBT_TARGET=dev dbt-project:latest run
```

### Issue: Terraform apply fails

**Solutions**:
```bash
# 1. Check state lock
aws dynamodb get-item \
  --table-name terraform-state-locks \
  --key '{"LockID":{"S":"data-platform-dev/terraform.tfstate-md5"}}'

# 2. Force unlock if stale
terraform force-unlock <LOCK_ID>

# 3. Refresh state
terraform refresh

# 4. Re-plan and apply
terraform plan
terraform apply
```

### Issue: GitHub Actions fails

**Solutions**:
```bash
# 1. Check GitHub Actions logs in UI

# 2. Verify AWS OIDC setup
aws iam list-open-id-connect-providers

# 3. Check IAM role trust policy
aws iam get-role --role-name github-actions-role

# 4. Test AWS credentials locally
aws sts assume-role-with-web-identity ...
```

---

## 📚 Key Documentation Files

| File | Purpose | When to Read |
|------|---------|--------------|
| **README.md** | Project overview | First |
| **CHANGES_SUMMARY.md** | What was simplified | After README |
| **SIMPLIFIED_ARCHITECTURE.md** | Architecture design | Before implementing |
| **HOW_TO_USE.md** | This file - usage guide | Day 1 |
| **BOOTSTRAP_GUIDE.md** | Terraform backend setup | Before Terraform |
| **DEPLOYMENT_GUIDE.md** | Deployment workflows | Day 25+ |
| **TECH_LEAD_PLAYBOOK.md** | Operations guide | Ongoing reference |
| **SPRINT_PLANNING.md** | 42-day implementation plan | Daily during sprints |
| **terraform/bootstrap/README.md** | Bootstrap details | Before bootstrap |
| **docs/QUICKSTART.md** | Quick reference | When stuck |

---

## 🎯 Success Checklist

### Week 1: Setup
- [ ] Read all documentation
- [ ] Local environment set up
- [ ] AWS credentials configured
- [ ] Terraform bootstrap complete
- [ ] Git repository initialized

### Week 2: DEV Infrastructure
- [ ] DEV environment deployed
- [ ] Redshift cluster accessible
- [ ] MWAA environment healthy
- [ ] Sample DAG running
- [ ] dbt compiles successfully

### Week 3: Data Pipeline
- [ ] dbt models created
- [ ] Docker image builds
- [ ] Image pushed to ECR
- [ ] dbt runs in ECS container
- [ ] Data visible in Redshift

### Week 4: CI/CD
- [ ] GitHub Actions configured
- [ ] Auto-deploy to DEV works
- [ ] DAGs sync automatically
- [ ] Tests run in CI

### Week 5: Production
- [ ] PROD infrastructure deployed
- [ ] Manual approval workflow tested
- [ ] dbt runs in PROD
- [ ] Monitoring configured

### Week 6: Operations
- [ ] Team trained
- [ ] Documentation updated
- [ ] Runbooks tested
- [ ] On-call rotation ready

---

## 🚀 Next Steps

1. **Today**: Read this guide + CHANGES_SUMMARY.md
2. **Tomorrow**: Run local setup + bootstrap Terraform
3. **This Week**: Deploy DEV infrastructure
4. **Next Week**: Develop dbt models
5. **Week 3**: Set up CI/CD
6. **Week 4**: Deploy to PROD
7. **Week 5-6**: Optimize and train team

---

## 💡 Tips

- ✅ **Start small**: Get one model working end-to-end before scaling
- ✅ **Test locally**: Always test dbt and DAGs locally first
- ✅ **Use dev liberally**: Deploy to DEV often, PROD carefully
- ✅ **Monitor costs**: Check AWS billing daily, set budget alerts
- ✅ **Document decisions**: Update docs when you make changes
- ✅ **Ask questions**: Use GitHub Issues for team discussions
- ✅ **Follow sprints**: Use SPRINT_PLANNING.md as your guide

---

## 📞 Getting Help

**Stuck?** Try these in order:

1. **Search this repository**: `git grep <keyword>`
2. **Check documentation**: See table above
3. **Review logs**: CloudWatch, GitHub Actions
4. **Check issues**: GitHub Issues for known problems
5. **Ask team**: Slack, team meetings

**Still stuck?** Create a GitHub Issue with:
- What you're trying to do
- What you expected
- What actually happened
- Relevant logs/screenshots

---

**You're all set! Start with Sprint 1 and follow the sprint plan.** 🎉

**Questions? Read SPRINT_PLANNING.md for your daily guide.**
