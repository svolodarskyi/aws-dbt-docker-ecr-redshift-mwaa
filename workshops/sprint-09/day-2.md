# Sprint 9 - Day 2: GitHub OIDC & CD Workflows

**Goal**: Configure GitHub OIDC authentication and create CD pipelines

**Duration**: ~6 hours

**Outcome**: Automated deployment to dev on merge, Docker images built and pushed automatically

---

## Morning Session (3 hours)

### Step 1: Create GitHub OIDC Provider in AWS (1 hour)

```bash
cd terraform/modules

# Update github-actions module (created in Sprint 2)
cd iam

# Add OIDC provider and role to main.tf
cat >> main.tf <<'EOF'

# GitHub OIDC Provider
resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name = "${var.project_name}-github-actions-oidc"
  }
}

# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-github-actions-role"
  }
}

# Attach policies for GitHub Actions
resource "aws_iam_role_policy" "github_actions_terraform" {
  name = "terraform-permissions"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Terraform state access
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-terraform-state-${var.environment}",
          "arn:aws:s3:::${var.project_name}-terraform-state-${var.environment}/*"
        ]
      },
      # DynamoDB for state locking
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:*:*:table/${var.project_name}-terraform-locks-${var.environment}"
      },
      # Read-only for terraform plan
      {
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "s3:List*",
          "s3:Get*",
          "iam:List*",
          "iam:Get*",
          "mwaa:Get*",
          "ecs:Describe*",
          "ecr:Describe*",
          "secretsmanager:ListSecrets",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "*"
      }
    ]
  })
}

# ECR permissions for Docker push
resource "aws_iam_role_policy" "github_actions_ecr" {
  name = "ecr-permissions"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      }
    ]
  })
}

# S3 permissions for DAG sync
resource "aws_iam_role_policy" "github_actions_s3" {
  name = "s3-sync-permissions"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-mwaa-${var.environment}",
          "arn:aws:s3:::${var.project_name}-mwaa-${var.environment}/*"
        ]
      }
    ]
  })
}
EOF

# Add variables
cat >> variables.tf <<'EOF'

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}
EOF

# Add outputs
cat >> outputs.tf <<'EOF'

output "github_actions_role_arn" {
  description = "ARN of IAM role for GitHub Actions"
  value       = aws_iam_role.github_actions.arn
}

output "github_oidc_provider_arn" {
  description = "ARN of GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github_actions.arn
}
EOF

# Format
terraform fmt -recursive ../../
```

### Step 2: Apply GitHub OIDC Configuration (30 minutes)

```bash
cd ../../environments/dev

# Update main.tf to use iam module with GitHub variables
cat >> main.tf <<'EOF'

# GitHub Actions configuration
variable "github_org" {
  description = "GitHub organization"
  type        = string
  default     = "your-github-org"  # UPDATE THIS
}

variable "github_repo" {
  description = "GitHub repository"
  type        = string
  default     = "data-platform"  # UPDATE THIS
}
EOF

# Update iam module call to include GitHub variables
# (Already exists, just add these inputs)

# Apply
terraform apply -target=module.iam

# Get role ARN
GITHUB_ROLE_ARN=$(terraform output -json iam | jq -r '.github_actions_role_arn')
echo "GitHub Actions Role ARN: ${GITHUB_ROLE_ARN}"
echo ""
echo "⚠️  ACTION REQUIRED:"
echo "Add this to GitHub Secrets as 'AWS_GITHUB_ACTIONS_ROLE':"
echo "${GITHUB_ROLE_ARN}"
```

### Step 3: Create Docker Build & Push Workflow (1 hour 30 minutes)

```bash
cd ../../../.github/workflows

cat > docker-build.yml <<'EOF'
name: Docker Build & Push

on:
  push:
    branches: [main, develop]
    paths:
      - 'dbt/**'
      - '.github/workflows/docker-build.yml'

env:
  AWS_REGION: us-east-1
  ECR_REPOSITORY: data-platform-dbt-dev

jobs:
  build-and-push:
    name: Build and Push dbt Image
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_GITHUB_ACTIONS_ROLE }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Get Git SHA
        id: vars
        run: echo "sha_short=$(git rev-parse --short HEAD)" >> $GITHUB_OUTPUT

      - name: Build dbt Docker image
        id: build
        run: |
          cd dbt
          docker build -t $ECR_REPOSITORY:${{ steps.vars.outputs.sha_short }} .
          docker tag $ECR_REPOSITORY:${{ steps.vars.outputs.sha_short }} $ECR_REPOSITORY:latest

      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.ECR_REPOSITORY }}:${{ steps.vars.outputs.sha_short }}
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'CRITICAL,HIGH'

      - name: Upload Trivy results to GitHub Security
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: 'trivy-results.sarif'

      - name: Check for CRITICAL vulnerabilities
        run: |
          docker run --rm aquasec/trivy image \
            --severity CRITICAL \
            --exit-code 1 \
            ${{ env.ECR_REPOSITORY }}:${{ steps.vars.outputs.sha_short }}

      - name: Push to ECR
        id: push
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
        run: |
          docker tag $ECR_REPOSITORY:${{ steps.vars.outputs.sha_short }} \
            $ECR_REGISTRY/$ECR_REPOSITORY:${{ steps.vars.outputs.sha_short }}

          docker tag $ECR_REPOSITORY:latest \
            $ECR_REGISTRY/$ECR_REPOSITORY:latest

          docker push $ECR_REGISTRY/$ECR_REPOSITORY:${{ steps.vars.outputs.sha_short }}
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest

          echo "image=$ECR_REGISTRY/$ECR_REPOSITORY:${{ steps.vars.outputs.sha_short }}" >> $GITHUB_OUTPUT

      - name: Output summary
        run: |
          echo "### Docker Build & Push Summary" >> $GITHUB_STEP_SUMMARY
          echo "- **Image**: ${{ steps.push.outputs.image }}" >> $GITHUB_STEP_SUMMARY
          echo "- **SHA**: ${{ steps.vars.outputs.sha_short }}" >> $GITHUB_STEP_SUMMARY
          echo "- **Branch**: ${{ github.ref_name }}" >> $GITHUB_STEP_SUMMARY
          echo "- **Vulnerabilities**: None (CRITICAL check passed)" >> $GITHUB_STEP_SUMMARY
EOF
```

---

## Afternoon Session (3 hours)

### Step 4: Create Deploy to Dev Workflow (1 hour 30 minutes)

```bash
cat > deploy-dev.yml <<'EOF'
name: Deploy to Dev

on:
  push:
    branches: [develop]
  workflow_dispatch:  # Allow manual trigger

env:
  AWS_REGION: us-east-1
  ENVIRONMENT: dev

jobs:
  deploy-infrastructure:
    name: Deploy Infrastructure
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_GITHUB_ACTIONS_ROLE }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: '1.6.0'

      - name: Terraform Init
        run: |
          cd terraform/environments/${{ env.ENVIRONMENT }}
          terraform init

      - name: Terraform Apply
        run: |
          cd terraform/environments/${{ env.ENVIRONMENT }}
          terraform apply -auto-approve

      - name: Get Terraform Outputs
        id: outputs
        run: |
          cd terraform/environments/${{ env.ENVIRONMENT }}
          echo "mwaa_bucket=$(terraform output -json storage | jq -r '.mwaa_bucket_id')" >> $GITHUB_OUTPUT
          echo "ecs_cluster=$(terraform output -json compute | jq -r '.ecs_cluster_name')" >> $GITHUB_OUTPUT

  deploy-dags:
    name: Deploy Airflow DAGs
    runs-on: ubuntu-latest
    needs: deploy-infrastructure
    permissions:
      id-token: write
      contents: read
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_GITHUB_ACTIONS_ROLE }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Get MWAA bucket
        id: mwaa
        run: |
          BUCKET=$(aws s3 ls | grep mwaa-dev | awk '{print $3}')
          echo "bucket=$BUCKET" >> $GITHUB_OUTPUT

      - name: Sync DAGs to S3
        run: |
          aws s3 sync airflow/dags/ s3://${{ steps.mwaa.outputs.bucket }}/dags/ \
            --delete \
            --exclude "*.pyc" \
            --exclude "__pycache__/*"

      - name: Upload requirements.txt
        run: |
          aws s3 cp airflow/requirements.txt s3://${{ steps.mwaa.outputs.bucket }}/requirements.txt

      - name: Output summary
        run: |
          echo "### DAG Deployment Summary" >> $GITHUB_STEP_SUMMARY
          echo "- **Bucket**: ${{ steps.mwaa.outputs.bucket }}" >> $GITHUB_STEP_SUMMARY
          echo "- **DAGs synced**: $(ls airflow/dags/*.py | wc -l)" >> $GITHUB_STEP_SUMMARY
          echo "- **Environment**: ${{ env.ENVIRONMENT }}" >> $GITHUB_STEP_SUMMARY

  update-ecs-task:
    name: Update ECS Task Definition
    runs-on: ubuntu-latest
    needs: deploy-infrastructure
    permissions:
      id-token: write
      contents: read
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_GITHUB_ACTIONS_ROLE }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Force new ECS deployment
        run: |
          CLUSTER=$(aws ecs list-clusters | grep dbt-dev | head -1 | cut -d'/' -f2 | tr -d '"')
          SERVICE=$(aws ecs list-services --cluster $CLUSTER | grep dbt | head -1 | cut -d'/' -f3 | tr -d '",')

          if [ -n "$SERVICE" ]; then
            aws ecs update-service --cluster $CLUSTER --service $SERVICE --force-new-deployment
          else
            echo "No ECS service found - task definition updated via Terraform"
          fi

      - name: Output summary
        run: |
          echo "### ECS Update Summary" >> $GITHUB_STEP_SUMMARY
          echo "- **Environment**: ${{ env.ENVIRONMENT }}" >> $GITHUB_STEP_SUMMARY
          echo "- **Status**: Task definition updated" >> $GITHUB_STEP_SUMMARY
EOF
```

### Step 5: Test Workflows (1 hour)

```bash
# Create test files to trigger workflows
cd ../../

# Test 1: Trigger Docker build
git checkout -b test/docker-build
echo "# Test update" >> dbt/README.md
git add dbt/
git commit -m "test: Trigger Docker build workflow"
git push origin test/docker-build

# Merge to develop to trigger build
# (Do in GitHub UI or via gh CLI)
gh pr create --base develop --title "Test Docker Build" --body "Testing workflow"
gh pr merge --auto --squash

# Test 2: Trigger deploy-dev
# (Automatically triggered by merge to develop)

# Monitor workflows
gh run list
gh run watch
```

### Step 6: Create CD Documentation (30 minutes)

```bash
cd docs

cat > CD_WORKFLOWS.md <<'EOF'
# Continuous Deployment Workflows

## Overview

**CD** automatically deploys code when merged to specific branches.

---

## Workflows

### 1. Docker Build & Push

**Workflow**: `.github/workflows/docker-build.yml`
**Trigger**: Push to `main` or `develop`
**Paths**: Changes to `dbt/**`

**Steps**:
1. Build dbt Docker image
2. Run Trivy security scan
3. Check for CRITICAL vulnerabilities
4. Push to ECR with tags:
   - Git SHA (e.g., `abc123`)
   - `latest`

**Duration**: ~5 minutes

**Artifacts**:
- ECR image: `data-platform-dbt-dev:SHA`
- Security scan results in GitHub Security tab

### 2. Deploy to Dev

**Workflow**: `.github/workflows/deploy-dev.yml`
**Trigger**: Push to `develop`

**Jobs**:
1. **deploy-infrastructure**: Apply Terraform changes
2. **deploy-dags**: Sync Airflow DAGs to S3
3. **update-ecs-task**: Force ECS deployment

**Duration**: ~8 minutes

---

## Deployment Flow

```
Developer → Create PR → CI checks → Merge to develop
                                           ↓
                                    Deploy to Dev
                                           ├─ Terraform apply
                                           ├─ Sync DAGs
                                           └─ Update ECS
```

---

## Manual Deployment

**Via GitHub UI**:
1. Go to Actions tab
2. Select "Deploy to Dev" workflow
3. Click "Run workflow"
4. Select branch: `develop`
5. Click "Run workflow"

**Via GitHub CLI**:
```bash
gh workflow run deploy-dev.yml --ref develop
```

---

## Rollback Procedures

### Rollback Docker Image

```bash
# List recent images
aws ecr describe-images \
    --repository-name data-platform-dbt-dev \
    --query 'sort_by(imageDetails, &imagePushedAt)[-10:]' \
    --output table

# Update task definition to use specific SHA
# Edit terraform/environments/dev/compute.tf:
# dbt_image_tag = "abc123"  # Previous working SHA

# Apply
cd terraform/environments/dev
terraform apply -target=module.compute
```

### Rollback Terraform

```bash
# Revert Terraform changes
git revert <commit-sha>
git push origin develop

# Or manually fix and re-deploy
cd terraform/environments/dev
# Make changes
terraform plan
terraform apply
```

### Rollback DAGs

```bash
# Revert DAG changes in Git
git revert <commit-sha>
git push origin develop

# Or manually sync old version
git checkout <old-commit> -- airflow/dags/
aws s3 sync airflow/dags/ s3://MWAA_BUCKET/dags/ --delete
```

---

## Monitoring Deployments

### Via GitHub

**Actions tab**:
- View all workflow runs
- Check logs for each job
- See deployment duration

**Summary**: Each workflow creates a summary with:
- What was deployed
- Where it was deployed
- Key metrics

### Via AWS

**Terraform**:
```bash
# Check recent changes
cd terraform/environments/dev
terraform show
```

**MWAA**:
```bash
# List DAGs in S3
BUCKET=$(aws s3 ls | grep mwaa-dev | awk '{print $3}')
aws s3 ls s3://$BUCKET/dags/
```

**ECS**:
```bash
# Check task definition revision
aws ecs describe-task-definition \
    --task-definition data-platform-dbt-transformation-dev \
    --query 'taskDefinition.revision'
```

---

## Troubleshooting

### Deployment Failed

**Check**:
1. Workflow logs in GitHub Actions
2. IAM role permissions
3. AWS resource limits
4. Terraform state lock

**Common Issues**:
- **Terraform locked**: Wait or force-unlock
- **IAM denied**: Update role policy
- **Resource limit**: Request quota increase
- **Invalid configuration**: Validate locally first

### Partial Deployment

**Scenario**: Infrastructure deployed but DAGs failed to sync

**Resolution**:
1. Fix DAG sync issue
2. Re-run "Deploy to Dev" workflow
3. Or manually sync: `aws s3 sync airflow/dags/ s3://BUCKET/dags/`

---

## Best Practices

✅ **Test locally** before pushing
✅ **Use feature branches** for development
✅ **Merge to develop** for automatic deployment
✅ **Tag releases** when promoting to main
✅ **Monitor deployments** in GitHub Actions
✅ **Verify** in AWS after deployment

❌ **Don't push directly to develop/main**
❌ **Don't skip CI checks**
❌ **Don't deploy untested code**

---

## Production Deployment (Future)

**Sprint 11** will add:
- Manual approval for production
- Blue/green deployment
- Automated rollback on failure

EOF
```

---

## End of Day 2 Checklist

- [x] GitHub OIDC provider created in AWS
- [x] IAM role for GitHub Actions created
- [x] Docker build & push workflow created
- [x] Deploy to dev workflow created
- [x] Workflows tested
- [x] Role ARN added to GitHub Secrets
- [x] CD documentation created

---

## 📝 Daily Standup Notes

**Completed Today**:
- Configured GitHub OIDC authentication
- Created IAM role for GitHub Actions with proper permissions
- Built Docker build/push workflow with Trivy scanning
- Created deploy-to-dev workflow (Terraform + DAGs + ECS)
- Tested workflows successfully
- Comprehensive CD documentation

**Blockers**:
- None (manual GitHub secret setup required)

**Tomorrow's Plan**:
- Test CI/CD end-to-end
- Configure branch protection rules
- Sprint demo
- Milestone Release 2

---

## 🎯 Success Metrics

```bash
# OIDC provider exists
aws iam list-open-id-connect-providers | grep github

# GitHub Actions role exists
aws iam get-role --role-name data-platform-github-actions-role

# Workflows exist
ls -la .github/workflows/
# Should show: docker-build.yml, deploy-dev.yml

# Test workflow
gh workflow run deploy-dev.yml --ref develop
gh run watch
```

---

## ⏭️ Next: Day 3

Tomorrow: End-to-end testing, branch protection, Milestone Release 2

**See [day-3.md](./day-3.md)** 🚀
