# Quick Start Guide

This guide will help you get the AWS Data Platform up and running in your local development environment.

## Prerequisites

Before you begin, ensure you have the following installed:

- **Python 3.11+**: `python --version`
- **Docker Desktop**: `docker --version`
- **Terraform 1.6+**: `terraform --version`
- **AWS CLI v2**: `aws --version`
- **Git**: `git --version`

## Initial Setup (15 minutes)

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/aws-data-platform.git
cd aws-data-platform
```

### 2. Run Setup Script

```bash
./scripts/setup/local-setup.sh
```

This script will:
- Create Python virtual environment
- Install all dependencies
- Set up pre-commit hooks
- Create `.env.local` from template
- Initialize dbt project

### 3. Configure AWS Credentials

```bash
# Configure AWS CLI with your dev account
aws configure --profile data-platform-dev

# Test connectivity
aws s3 ls --profile data-platform-dev
```

### 4. Update Environment Variables

Edit `.env.local` with your actual values:

```bash
# Copy from example
cp .env.example .env.local

# Edit with your values
vim .env.local
```

Required values:
- `AWS_ACCOUNT_ID`: Your AWS account ID
- `REDSHIFT_*`: Redshift connection details (once cluster is created)

### 5. Initialize Terraform

```bash
cd terraform/environments/dev

# Initialize (first time only)
terraform init

# Review plan
terraform plan

# Apply infrastructure (requires approval)
terraform apply
```

**Note**: Infrastructure provisioning takes ~30-45 minutes for all services.

### 6. Test dbt Locally

```bash
cd ../../../dbt

# Install dbt packages
dbt deps

# Test connection
dbt debug --profiles-dir ./profiles --target dev

# Compile models (no data needed)
dbt compile --profiles-dir ./profiles --target dev
```

### 7. Build and Test Docker Container

```bash
# Build dbt container
docker build -t dbt-project:local ./dbt

# Test container
docker run --rm \
  -e REDSHIFT_HOST_DEV=$REDSHIFT_HOST_DEV \
  -e REDSHIFT_USER_DEV=$REDSHIFT_USER_DEV \
  -e REDSHIFT_PASSWORD_DEV=$REDSHIFT_PASSWORD_DEV \
  -e DBT_TARGET=dev \
  dbt-project:local compile
```

### 8. Verify Everything Works

Run the verification script:

```bash
./scripts/setup/verify-setup.sh
```

This checks:
- ✅ Python environment
- ✅ AWS connectivity
- ✅ Terraform state
- ✅ dbt compilation
- ✅ Docker build

## Daily Development Workflow

### Working on dbt Models

```bash
# 1. Create feature branch
git checkout -b feature/add-customer-model

# 2. Create or edit dbt model
vim dbt/models/marts/customers_dim.sql

# 3. Test locally
cd dbt
dbt run --profiles-dir ./profiles --target dev --select customers_dim
dbt test --profiles-dir ./profiles --target dev --select customers_dim

# 4. Commit changes
git add dbt/models/marts/customers_dim.sql
git commit -m "feat: add customer dimension model"

# 5. Push and create PR
git push origin feature/add-customer-model
```

### Working on Airflow DAGs

```bash
# 1. Create or edit DAG
vim airflow/dags/my_new_dag.py

# 2. Test DAG syntax (locally)
python airflow/dags/my_new_dag.py

# 3. Commit and push (will auto-deploy to dev after merge)
git add airflow/dags/my_new_dag.py
git commit -m "feat: add new data ingestion DAG"
git push origin feature/add-ingestion-dag
```

### Working on Infrastructure

```bash
# 1. Create feature branch
git checkout -b feature/add-monitoring

# 2. Edit Terraform
vim terraform/modules/monitoring/cloudwatch.tf

# 3. Validate and plan
cd terraform/environments/dev
terraform fmt
terraform validate
terraform plan

# 4. Commit (apply happens in CI after merge)
git add terraform/modules/monitoring/
git commit -m "feat: add CloudWatch dashboard for ECS tasks"
git push origin feature/add-monitoring
```

## Troubleshooting

### Issue: `dbt debug` fails with connection error

**Solution**:
1. Check VPN/bastion connection to private Redshift
2. Verify security group allows your IP
3. Test with psql: `psql -h $REDSHIFT_HOST -U $REDSHIFT_USER -d analytics_dev`

### Issue: Terraform apply fails with "state locked"

**Solution**:
```bash
# Check who has the lock
aws dynamodb get-item \
  --table-name terraform-state-locks \
  --key '{"LockID":{"S":"data-platform-dev/terraform.tfstate-md5"}}'

# If stale, force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

### Issue: Docker build fails on M1/M2 Mac

**Solution**:
```bash
# Build for linux/amd64 (ECS platform)
docker buildx build --platform linux/amd64 -t dbt-project:local ./dbt
```

### Issue: Pre-commit hooks fail

**Solution**:
```bash
# Update hooks
pre-commit autoupdate

# Run manually to see errors
pre-commit run --all-files

# Fix issues and re-commit
git add .
git commit -m "fix: resolve linting issues"
```

## Common Commands Cheat Sheet

### dbt

```bash
# Install packages
dbt deps

# Compile models
dbt compile --target dev

# Run all models
dbt run --target dev

# Run specific model
dbt run --target dev --select customers_dim

# Run models and downstream
dbt run --target dev --select customers_dim+

# Test all
dbt test --target dev

# Generate documentation
dbt docs generate
dbt docs serve
```

### Terraform

```bash
# Format code
terraform fmt -recursive

# Validate configuration
terraform validate

# Plan changes
terraform plan -out=tfplan

# Apply changes
terraform apply tfplan

# Show current state
terraform show

# List resources
terraform state list
```

### AWS CLI

```bash
# Sync DAGs to MWAA
aws s3 sync ./airflow/dags/ s3://mwaa-bucket/dags/

# Push Docker image to ECR
aws ecr get-login-password | docker login --username AWS --password-stdin <ecr-url>
docker push <ecr-url>/dbt-project:latest

# Run ECS task manually
aws ecs run-task \
  --cluster dbt-cluster \
  --task-definition dbt-transformation-task \
  --launch-type FARGATE

# Check CloudWatch logs
aws logs tail /ecs/dbt-transformation --follow
```

### Git

```bash
# Create feature branch
git checkout -b feature/my-feature

# Commit with conventional commits
git commit -m "feat: add new feature"
git commit -m "fix: resolve bug"
git commit -m "docs: update README"

# Push and create PR
git push origin feature/my-feature

# Sync with main
git checkout main
git pull origin main
git checkout feature/my-feature
git rebase main
```

## Next Steps

1. **Review Architecture**: Read [ARCHITECTURE.md](../ARCHITECTURE.md)
2. **Understand Sprints**: Review [SPRINT_PLANNING.md](../SPRINT_PLANNING.md)
3. **Read Playbook**: Study [TECH_LEAD_PLAYBOOK.md](../TECH_LEAD_PLAYBOOK.md)
4. **Join Team Meeting**: Attend daily standup and sprint planning
5. **Pick First Task**: Choose a starter task from Sprint 1 backlog

## Getting Help

- **Documentation**: Check `/docs` folder
- **Team Chat**: #data-engineering Slack channel
- **Issues**: GitHub Issues for bugs and features
- **On-call**: See TECH_LEAD_PLAYBOOK.md for escalation path

## Resources

- [dbt Documentation](https://docs.getdbt.com/)
- [Airflow Documentation](https://airflow.apache.org/docs/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS MWAA User Guide](https://docs.aws.amazon.com/mwaa/latest/userguide/what-is-mwaa.html)
- [Cosmos Documentation](https://astronomer.github.io/astronomer-cosmos/)

---

**Welcome to the team! Let's build something amazing together! 🚀**
