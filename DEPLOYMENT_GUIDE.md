# Deployment Guide - Simplified (2 Environments, Manual Triggers)

## Overview

This guide covers the **simplified deployment strategy**:
- ✅ **2 Environments**: DEV and PROD only (no staging)
- ✅ **Manual Airflow Triggers**: UI/CLI/script based (no EventBridge automation)
- ✅ **GitHub Actions Only**: No CodeBuild or CodePipeline

## Environment Strategy

### Development (DEV)
- **AWS Account**: Can be same or separate from prod
- **Purpose**: Development and integration testing
- **Deployment**: Auto-deploy on merge to `develop` branch
- **Data**: Sample or anonymized data
- **Airflow URL**: `https://xxxxx-dev.airflow.us-east-1.amazonaws.com`
- **Cost**: ~$800-1000/month
- **Uptime**: Business hours (9-5, pause Redshift nights/weekends)

### Production (PROD)
- **AWS Account**: Separate recommended for security
- **Purpose**: Production workloads
- **Deployment**: Manual approval required on merge to `main`
- **Data**: Real production data
- **Airflow URL**: `https://xxxxx-prod.airflow.us-east-1.amazonaws.com`
- **Cost**: ~$2500-3000/month
- **Uptime**: 24/7 with high availability

## Git Branching Strategy

```
main (prod)
  ↑
  └─ feature branches merge via PR
       ↓
    develop (dev)
       ↑
       └─ feature/* branches
```

**Workflow**:
1. Create feature branch from `develop`
2. Develop and test locally
3. Create PR to `develop`
4. CI runs (lint, test, validate)
5. Merge to `develop` → Auto-deploy to DEV
6. Test in DEV environment
7. Create PR from `develop` to `main`
8. Manual approval required
9. Merge to `main` → Deploy to PROD

## CI/CD Pipelines (GitHub Actions Only)

### Pipeline 1: Pull Request Validation

**File**: `.github/workflows/ci.yml`
**Trigger**: Pull request to `develop` or `main`

```yaml
name: CI - Validate

on:
  pull_request:
    branches: [develop, main]

jobs:
  terraform-validate:
    runs-on: ubuntu-latest
    steps:
      - Checkout code
      - terraform fmt -check
      - terraform validate
      - tflint
      - checkov (security scan)

  dbt-test:
    runs-on: ubuntu-latest
    steps:
      - Checkout code
      - dbt deps
      - dbt compile
      - sqlfluff lint
      - dbt test (using dev credentials)

  docker-build-test:
    runs-on: ubuntu-latest
    steps:
      - Checkout code
      - Build dbt Docker image
      - Scan with Trivy
      - (No push, just validation)
```

**Status**: Must pass before merge allowed

### Pipeline 2: Deploy to DEV

**File**: `.github/workflows/deploy-dev.yml`
**Trigger**: Merge to `develop` branch

```yaml
name: Deploy to DEV

on:
  push:
    branches: [develop]

jobs:
  build-dbt-image:
    runs-on: ubuntu-latest
    steps:
      - Checkout code
      - Configure AWS credentials (OIDC)
      - Login to ECR
      - Build dbt Docker image
      - Tag: {git-sha}, develop-latest
      - Scan with Trivy
      - Push to ECR (dev account/repository)

  deploy-infrastructure:
    needs: build-dbt-image
    runs-on: ubuntu-latest
    steps:
      - Checkout code
      - Configure AWS credentials (OIDC)
      - cd terraform/environments/dev
      - terraform init
      - terraform plan
      - terraform apply -auto-approve
      - Output infrastructure details

  deploy-dags:
    needs: deploy-infrastructure
    runs-on: ubuntu-latest
    steps:
      - Checkout code
      - Configure AWS credentials
      - Sync DAGs to S3: aws s3 sync ./airflow/dags/ s3://mwaa-dev-bucket/dags/
      - Sync plugins: aws s3 sync ./airflow/plugins/ s3://mwaa-dev-bucket/plugins/
      - Update requirements.txt
      - Wait 5 minutes (MWAA sync time)

  verify-deployment:
    needs: deploy-dags
    runs-on: ubuntu-latest
    steps:
      - Verify ECR image exists
      - Check MWAA environment healthy
      - List DAGs in S3
      - Send Slack notification (optional)
```

### Pipeline 3: Deploy to PROD

**File**: `.github/workflows/deploy-prod.yml`
**Trigger**: Merge to `main` branch
**Special**: Requires manual approval

```yaml
name: Deploy to PROD

on:
  push:
    branches: [main]

jobs:
  build-dbt-image:
    runs-on: ubuntu-latest
    steps:
      - Checkout code
      - Configure AWS credentials (prod OIDC)
      - Login to ECR (prod)
      - Build dbt Docker image
      - Tag: {git-sha}, prod-latest, v{version}
      - Scan with Trivy (fail on HIGH/CRITICAL)
      - Push to ECR (prod account/repository)

  plan-infrastructure:
    needs: build-dbt-image
    runs-on: ubuntu-latest
    steps:
      - Checkout code
      - Configure AWS credentials
      - cd terraform/environments/prod
      - terraform init
      - terraform plan -out=tfplan
      - Save plan artifact

  manual-approval:
    needs: plan-infrastructure
    runs-on: ubuntu-latest
    environment: production  # Requires manual approval
    steps:
      - Display terraform plan
      - Wait for approval (2 reviewers required)

  deploy-infrastructure:
    needs: manual-approval
    runs-on: ubuntu-latest
    steps:
      - Checkout code
      - Configure AWS credentials
      - cd terraform/environments/prod
      - terraform init
      - terraform apply tfplan

  deploy-dags:
    needs: deploy-infrastructure
    runs-on: ubuntu-latest
    steps:
      - Checkout code
      - Configure AWS credentials
      - Sync DAGs to S3: aws s3 sync ./airflow/dags/ s3://mwaa-prod-bucket/dags/
      - Sync plugins
      - Update requirements.txt
      - Wait for MWAA sync

  smoke-tests:
    needs: deploy-dags
    runs-on: ubuntu-latest
    steps:
      - Verify all components healthy
      - Check monitoring/alerting
      - Send deployment notification
      - Create GitHub release
```

## Triggering Airflow DAGs Manually

### Method 1: Airflow UI (Easiest)

1. **Access Airflow UI**:
   ```bash
   # DEV
   Open: https://your-mwaa-dev-env.airflow.us-east-1.amazonaws.com

   # PROD
   Open: https://your-mwaa-prod-env.airflow.us-east-1.amazonaws.com
   ```

2. **Login**: Uses AWS IAM authentication (automatic if using AWS Console)

3. **Trigger DAG**:
   - Navigate to "DAGs" page
   - Find your DAG (e.g., `dbt_transform_daily`)
   - Click the "Play" button
   - (Optional) Add configuration JSON
   - Click "Trigger"

4. **Monitor Execution**:
   - Click on DAG run to see task details
   - View logs for each task
   - Check task status (success/failed)

### Method 2: AWS CLI

```bash
# Install AWS CLI
pip install awscli

# Configure profile
aws configure --profile data-platform-dev

# Trigger DAG using helper script
./scripts/trigger-dag.sh dbt_transform_daily dev

# Or manually:
aws mwaa create-cli-token \
  --name data-platform-airflow-dev \
  --region us-east-1 \
  --profile data-platform-dev \
  --query WebToken \
  --output text > /tmp/web_token.txt

# Use token to call Airflow API
# (See full script in scripts/trigger-dag.sh)
```

### Method 3: Python Script

**File**: `scripts/trigger_dag.py`

```python
#!/usr/bin/env python3
import sys
import boto3
import requests
import json

def trigger_dag(environment, dag_id, conf=None):
    """
    Trigger Airflow DAG in MWAA environment

    Args:
        environment: 'dev' or 'prod'
        dag_id: Name of the DAG to trigger
        conf: Optional configuration dictionary
    """
    # MWAA environment name
    env_name = f"data-platform-airflow-{environment}"
    region = "us-east-1"

    # Create MWAA client
    mwaa = boto3.client('mwaa', region_name=region)

    # Get CLI token
    try:
        response = mwaa.create_cli_token(Name=env_name)
        web_server_url = response['WebServerHostname']
        token = response['WebToken']
    except Exception as e:
        print(f"Error getting MWAA token: {e}")
        return None

    # Trigger DAG via Airflow REST API
    url = f"https://{web_server_url}/api/v1/dags/{dag_id}/dagRuns"
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }
    data = {
        'conf': conf or {},
        'note': f'Triggered via script by {boto3.client("sts").get_caller_identity()["Arn"]}'
    }

    try:
        response = requests.post(url, headers=headers, json=data, verify=True)
        response.raise_for_status()
        result = response.json()
        print(f"✅ DAG triggered successfully!")
        print(f"   DAG Run ID: {result.get('dag_run_id')}")
        print(f"   State: {result.get('state')}")
        print(f"   Execution Date: {result.get('execution_date')}")
        return result
    except requests.exceptions.RequestException as e:
        print(f"❌ Error triggering DAG: {e}")
        if hasattr(e, 'response') and e.response:
            print(f"   Response: {e.response.text}")
        return None

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python trigger_dag.py <environment> <dag_id> [conf_json]")
        print("Example: python trigger_dag.py dev dbt_transform_daily")
        print('Example with config: python trigger_dag.py prod dbt_transform_daily \'{"full_refresh": true}\'')
        sys.exit(1)

    environment = sys.argv[1]
    dag_id = sys.argv[2]
    conf = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None

    if environment not in ['dev', 'prod']:
        print("Error: environment must be 'dev' or 'prod'")
        sys.exit(1)

    trigger_dag(environment, dag_id, conf)
```

**Usage**:
```bash
# Basic trigger
python scripts/trigger_dag.py dev dbt_transform_daily

# With configuration
python scripts/trigger_dag.py prod dbt_transform_daily '{"full_refresh": true}'

# Trigger specific model
python scripts/trigger_dag.py dev dbt_transform_daily '{"models": "customers_dim"}'
```

### Method 4: Scheduled Runs (Optional)

While this guide focuses on manual triggers, you can still schedule DAGs:

```python
# In your DAG file
dag = DAG(
    dag_id='dbt_transform_daily',
    schedule_interval='0 2 * * *',  # 2 AM daily
    # OR
    schedule_interval=None,  # Manual trigger only
)
```

**Recommendation**: Start with `schedule_interval=None` for manual control, add scheduling later.

## Deployment Checklist

### Pre-Deployment (DEV)

- [ ] Create feature branch from `develop`
- [ ] Develop changes locally
- [ ] Test dbt models locally
- [ ] Run pre-commit hooks
- [ ] Create PR to `develop`
- [ ] CI passes (lint, test, validate)
- [ ] Code review approved
- [ ] Merge to `develop`

### During Deployment (DEV - Automatic)

- [ ] GitHub Actions builds Docker image
- [ ] Image pushed to ECR (dev)
- [ ] Terraform applies infrastructure changes
- [ ] DAGs synced to S3
- [ ] Verify in Slack notification

### Post-Deployment (DEV - Manual)

- [ ] Access Airflow UI
- [ ] Verify new DAGs visible
- [ ] Trigger DAG manually
- [ ] Monitor execution
- [ ] Verify data in Redshift
- [ ] Check CloudWatch logs
- [ ] Confirm no errors

### Pre-Deployment (PROD)

- [ ] Test thoroughly in DEV
- [ ] Create PR from `develop` to `main`
- [ ] Update CHANGELOG.md
- [ ] Get 2 approvals on PR
- [ ] Notify stakeholders of deployment window
- [ ] Merge to `main`

### During Deployment (PROD - Semi-Automatic)

- [ ] GitHub Actions builds Docker image
- [ ] Image scanned (must pass security scan)
- [ ] Image pushed to ECR (prod)
- [ ] Terraform plan generated
- [ ] Review terraform plan
- [ ] **MANUAL APPROVAL REQUIRED**
- [ ] Terraform applies (after approval)
- [ ] DAGs synced to S3
- [ ] Smoke tests run

### Post-Deployment (PROD - Manual)

- [ ] Verify Airflow UI shows new DAGs
- [ ] Trigger DAG manually or wait for schedule
- [ ] Monitor execution closely
- [ ] Verify data quality
- [ ] Check monitoring dashboards
- [ ] Confirm alerts working
- [ ] Notify stakeholders of completion
- [ ] Document any issues

## Rollback Procedures

### Rollback Infrastructure

```bash
# Revert to previous Terraform version
cd terraform/environments/prod
git checkout <previous-commit> -- .
terraform plan
terraform apply

# OR restore from backup
terraform state pull > backup.tfstate
terraform apply -var-file=previous.tfvars
```

### Rollback Application (DAGs)

```bash
# Restore previous DAGs from S3 versioning
aws s3api list-object-versions \
  --bucket mwaa-prod-bucket \
  --prefix dags/

# Restore specific version
aws s3api get-object \
  --bucket mwaa-prod-bucket \
  --key dags/dbt_transform_daily.py \
  --version-id <version-id> \
  dbt_transform_daily.py

# Re-upload
aws s3 cp dbt_transform_daily.py s3://mwaa-prod-bucket/dags/
```

### Rollback Docker Image

```bash
# Update ECS task definition to previous image
aws ecs describe-task-definition \
  --task-definition dbt-transformation-task

# Register previous version
aws ecs register-task-definition \
  --cli-input-json file://previous-task-def.json

# Airflow will use previous image on next run
```

## Monitoring Deployments

### CloudWatch Logs

```bash
# View deployment logs
aws logs tail /aws/codebuild/dbt-build --follow

# View Airflow logs
aws logs tail /aws/mwaa/data-platform-airflow-prod/scheduler --follow
aws logs tail /aws/mwaa/data-platform-airflow-prod/worker --follow
```

### GitHub Actions

- View workflow runs in GitHub Actions tab
- Check deployment history
- Review artifacts and logs

### Deployment Notifications

Set up Slack/Email notifications:

```yaml
# Add to workflow
- name: Notify Slack
  uses: slackapi/slack-github-action@v1
  with:
    payload: |
      {
        "text": "Deployment to ${{ env.ENVIRONMENT }} completed",
        "blocks": [
          {
            "type": "section",
            "text": {
              "type": "mrkdwn",
              "text": "✅ Deployment successful!\n*Environment:* ${{ env.ENVIRONMENT }}\n*Commit:* ${{ github.sha }}"
            }
          }
        ]
      }
```

## Best Practices

### Development

1. ✅ Always test in DEV first
2. ✅ Use feature branches
3. ✅ Write tests for dbt models
4. ✅ Lint before committing (pre-commit hooks)
5. ✅ Document changes in PR description

### Deployment

1. ✅ Deploy to DEV frequently (daily)
2. ✅ Deploy to PROD during business hours
3. ✅ Never deploy to PROD on Fridays
4. ✅ Require 2 approvals for PROD
5. ✅ Have rollback plan ready
6. ✅ Monitor closely for 1 hour after deployment

### Manual Triggers

1. ✅ Document why you're triggering manually
2. ✅ Use configuration parameters when needed
3. ✅ Monitor execution to completion
4. ✅ Verify data quality after run
5. ✅ Check CloudWatch logs for errors

## Troubleshooting

### Issue: GitHub Actions deployment failed

**Check**:
```bash
# View workflow logs in GitHub
# Check IAM permissions for OIDC role
aws sts assume-role-with-web-identity ...

# Verify AWS credentials
aws sts get-caller-identity
```

### Issue: DAG not showing in Airflow UI

**Check**:
```bash
# Verify DAG uploaded to S3
aws s3 ls s3://mwaa-dev-bucket/dags/

# Check MWAA scheduler logs
aws logs tail /aws/mwaa/data-platform-airflow-dev/scheduler --follow

# Syntax errors in DAG
python airflow/dags/your_dag.py
```

### Issue: Manual trigger fails

**Check**:
- MWAA environment healthy
- IAM permissions for CLI token
- DAG ID spelled correctly
- Check Airflow UI for error messages

## Summary

**Simplified Architecture Benefits**:
- ✅ Fewer environments to manage (2 vs 4)
- ✅ Lower costs (~$2500/month saved)
- ✅ Simpler CI/CD (GitHub Actions only)
- ✅ More control (manual triggers)
- ✅ Faster to implement (~6 days saved)

**Trade-offs**:
- ⚠️ Manual effort to trigger DAGs
- ⚠️ No automated event-driven pipeline (can add later)
- ⚠️ No staging environment (DEV → PROD directly)

**When to Add Automation**:
- Once pipelines are stable and tested
- When manual triggering becomes burden
- When you have clear SLAs requiring automation
- Estimated: Sprint 15-16 (after initial 42 days)
