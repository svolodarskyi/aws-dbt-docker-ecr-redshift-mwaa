# Sprint 6 - Day 2: ECR Setup & Image Publishing

**Goal**: Push Docker images to Amazon ECR

**Duration**: ~6 hours

**Outcome**: dbt image in ECR, automated tagging strategy

---

## Morning Session (3 hours)

### Step 1: Create ECR Terraform Module (1 hour)

```bash
cd terraform/modules

mkdir -p ecr

cd ecr

cat > main.tf <<'EOF'
resource "aws_ecr_repository" "dbt_project" {
  name                 = "${var.project_name}-dbt-${var.environment}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.project_name}-dbt-${var.environment}"
  }
}

resource "aws_ecr_lifecycle_policy" "dbt_project" {
  repository = aws_ecr_repository.dbt_project.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "prod-", "dev-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
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
EOF

cat > outputs.tf <<'EOF'
output "repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.dbt_project.repository_url
}

output "repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.dbt_project.arn
}

output "repository_name" {
  description = "ECR repository name"
  value       = aws_ecr_repository.dbt_project.name
}
EOF
```

### Step 2: Deploy ECR Repository (30 minutes)

```bash
cd ../../environments/dev

cat > ecr.tf <<'EOF'
module "ecr" {
  source = "../../modules/ecr"

  project_name = var.project_name
  environment  = var.environment
}

output "ecr" {
  value = {
    repository_url  = module.ecr.repository_url
    repository_name = module.ecr.repository_name
  }
}
EOF

# Format and apply
terraform fmt -recursive ../../
terraform validate
terraform plan
terraform apply

# Get repository URL
ECR_REPO_URL=$(terraform output -json ecr | jq -r '.repository_url')
echo "ECR Repository: ${ECR_REPO_URL}"
```

### Step 3: Push Image to ECR (1 hour 30 minutes)

```bash
cd ../../../dbt

# Get AWS account ID and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
REPO_NAME=$(cd ../terraform/environments/dev && terraform output -json ecr | jq -r '.repository_name')

# Authenticate Docker to ECR
aws ecr get-login-password --region ${REGION} | \
    docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# Build image
docker build -t dbt-project:latest .

# Tag for ECR - latest
docker tag dbt-project:latest \
    ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:latest

# Tag with git SHA
GIT_SHA=$(git rev-parse --short HEAD)
docker tag dbt-project:latest \
    ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:${GIT_SHA}

# Tag with version
VERSION="v1.0.0"
docker tag dbt-project:latest \
    ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:${VERSION}

# Push all tags
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:latest
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:${GIT_SHA}
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:${VERSION}

# Verify images in ECR
aws ecr describe-images \
    --repository-name ${REPO_NAME} \
    --query 'imageDetails[*].[imageTags[0],imagePushedAt,imageSizeInBytes]' \
    --output table
```

---

## Afternoon Session (3 hours)

### Step 4: Create Push Script (1 hour)

```bash
cd ../scripts/docker

cat > push-to-ecr.sh <<'EOF'
#!/bin/bash
set -e

VERSION=${1:-latest}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=${AWS_REGION:-us-east-1}

# Get ECR repo name from Terraform
cd ../../terraform/environments/dev
REPO_NAME=$(terraform output -json ecr | jq -r '.repository_name')
cd -

IMAGE_NAME="dbt-project"
ECR_URL="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}"

echo "📦 Pushing ${IMAGE_NAME}:${VERSION} to ECR..."

# Authenticate
echo "🔑 Authenticating with ECR..."
aws ecr get-login-password --region ${REGION} | \
    docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# Build image
echo "🏗️  Building image..."
cd ../../dbt
docker build -t ${IMAGE_NAME}:${VERSION} .

# Tag for ECR
echo "🏷️  Tagging image..."
docker tag ${IMAGE_NAME}:${VERSION} ${ECR_URL}:${VERSION}
docker tag ${IMAGE_NAME}:${VERSION} ${ECR_URL}:latest

# Get git SHA if available
if command -v git &> /dev/null; then
    GIT_SHA=$(git rev-parse --short HEAD)
    docker tag ${IMAGE_NAME}:${VERSION} ${ECR_URL}:git-${GIT_SHA}
    echo "Tagged with git SHA: git-${GIT_SHA}"
fi

# Push to ECR
echo "⬆️  Pushing to ECR..."
docker push ${ECR_URL}:${VERSION}
docker push ${ECR_URL}:latest

if [ -n "$GIT_SHA" ]; then
    docker push ${ECR_URL}:git-${GIT_SHA}
fi

# Show pushed images
echo ""
echo "✅ Push complete! Images in ECR:"
aws ecr describe-images \
    --repository-name ${REPO_NAME} \
    --region ${REGION} \
    --query 'imageDetails[*].[imageTags[0],imagePushedAt,imageSizeInBytes]' \
    --output table

echo ""
echo "📋 Pull command:"
echo "docker pull ${ECR_URL}:${VERSION}"
EOF

chmod +x push-to-ecr.sh

# Test the script
./push-to-ecr.sh v1.0.0
```

### Step 5: Test Pulling from ECR (30 minutes)

```bash
# Get ECR URL
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
cd ../../terraform/environments/dev
REPO_NAME=$(terraform output -json ecr | jq -r '.repository_name')
ECR_URL="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}"

# Remove local images
docker rmi ${ECR_URL}:latest || true
docker rmi ${ECR_URL}:v1.0.0 || true

# Pull from ECR
docker pull ${ECR_URL}:latest

# Test pulled image
docker run --rm \
    -e REDSHIFT_HOST=$REDSHIFT_HOST \
    -e REDSHIFT_USER=$REDSHIFT_USER \
    -e REDSHIFT_PASSWORD=$REDSHIFT_PASSWORD \
    ${ECR_URL}:latest dbt --version

# Test with Secrets Manager
docker run --rm \
    -e AWS_SECRET_NAME=data-platform/dev/redshift/master \
    -e AWS_DEFAULT_REGION=us-east-1 \
    ${ECR_URL}:latest dbt debug
```

### Step 6: Create Image Tagging Strategy Documentation (1 hour 30 minutes)

```bash
cd ../../../docs

cat > ECR_TAGGING_STRATEGY.md <<'EOF'
# ECR Image Tagging Strategy

## Tag Types

### 1. Version Tags (Semantic Versioning)
**Format**: `vMAJOR.MINOR.PATCH`
- `v1.0.0` - Major release
- `v1.1.0` - Minor release (new features)
- `v1.1.1` - Patch release (bug fixes)

**Usage**:
```bash
docker push ${ECR_URL}:v1.0.0
```

### 2. Git SHA Tags
**Format**: `git-<short-sha>`
- `git-a1b2c3d` - Tied to specific commit
- Immutable reference
- Useful for debugging

**Usage**:
```bash
GIT_SHA=$(git rev-parse --short HEAD)
docker push ${ECR_URL}:git-${GIT_SHA}
```

### 3. Environment Tags
**Format**: `<env>-<version>` or `<env>-latest`
- `dev-latest` - Latest dev build
- `prod-v1.0.0` - Production release
- `staging-latest` - Staging environment

**Usage**:
```bash
docker push ${ECR_URL}:dev-latest
docker push ${ECR_URL}:prod-v1.0.0
```

### 4. Latest Tag
**Format**: `latest`
- Points to most recent build
- **Mutable** (gets overwritten)
- Good for development, **not for production**

**Usage**:
```bash
docker push ${ECR_URL}:latest
```

## Recommended Tagging Workflow

### Development Builds
```bash
# Tag with git SHA and dev-latest
docker tag dbt-project:latest ${ECR_URL}:git-${GIT_SHA}
docker tag dbt-project:latest ${ECR_URL}:dev-latest
docker push ${ECR_URL}:git-${GIT_SHA}
docker push ${ECR_URL}:dev-latest
```

### Production Releases
```bash
# Tag with semantic version and prod prefix
docker tag dbt-project:latest ${ECR_URL}:v1.0.0
docker tag dbt-project:latest ${ECR_URL}:prod-v1.0.0
docker tag dbt-project:latest ${ECR_URL}:prod-latest
docker push ${ECR_URL}:v1.0.0
docker push ${ECR_URL}:prod-v1.0.0
docker push ${ECR_URL}:prod-latest
```

## ECR Lifecycle Policy

Our lifecycle policy automatically:
1. **Keeps last 10 tagged images** (v*, prod-*, dev-*)
2. **Deletes untagged images** after 7 days
3. **Saves storage costs**

## Image Pulling

### For ECS Tasks
```hcl
container_definitions = jsonencode([{
  image = "${ECR_URL}:v1.0.0"  # Use specific version
  # NOT ${ECR_URL}:latest
}])
```

### For Local Testing
```bash
# Pull specific version
docker pull ${ECR_URL}:v1.0.0

# Or latest for development
docker pull ${ECR_URL}:dev-latest
```

## Best Practices

✅ **Use semantic versioning** for releases
✅ **Tag with git SHA** for traceability
✅ **Never use latest in production** ECS tasks
✅ **Document tags** in release notes
✅ **Scan images** before production deployment

❌ **Don't delete production tags** manually
❌ **Don't reuse version tags** (v1.0.0 should always point to same image)
❌ **Don't skip tagging** - always tag images

## Verification

```bash
# List all images and tags
aws ecr describe-images \
    --repository-name ${REPO_NAME} \
    --query 'imageDetails[*].[imageTags,imagePushedAt]' \
    --output table

# Get image digest for specific tag
aws ecr describe-images \
    --repository-name ${REPO_NAME} \
    --image-ids imageTag=v1.0.0 \
    --query 'imageDetails[0].imageDigest'
```
EOF

# Create ECR operations guide
cat > ECR_OPERATIONS.md <<'EOF'
# ECR Operations Guide

## Common Operations

### List Images
```bash
aws ecr describe-images \
    --repository-name data-platform-dbt-dev \
    --query 'imageDetails[*].[imageTags[0],imagePushedAt,imageSizeInBytes]' \
    --output table
```

### Delete Specific Image
```bash
aws ecr batch-delete-image \
    --repository-name data-platform-dbt-dev \
    --image-ids imageTag=old-tag
```

### Get Image URI
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
REPO_NAME=data-platform-dbt-dev
TAG=v1.0.0

IMAGE_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:${TAG}"
echo $IMAGE_URI
```

### Scan Image for Vulnerabilities
```bash
# Start scan
aws ecr start-image-scan \
    --repository-name data-platform-dbt-dev \
    --image-id imageTag=v1.0.0

# Get scan results
aws ecr describe-image-scan-findings \
    --repository-name data-platform-dbt-dev \
    --image-id imageTag=v1.0.0
```

### Pull Image
```bash
# Authenticate
aws ecr get-login-password --region us-east-1 | \
    docker login --username AWS --password-stdin \
    ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com

# Pull
docker pull ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/data-platform-dbt-dev:v1.0.0
```

## Troubleshooting

### Issue: Authentication Failed
```bash
# Re-authenticate
aws ecr get-login-password --region us-east-1 | \
    docker login --username AWS --password-stdin \
    ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com
```

### Issue: Image Not Found
```bash
# Verify image exists
aws ecr describe-images \
    --repository-name data-platform-dbt-dev \
    --image-ids imageTag=v1.0.0
```

### Issue: Push Denied
```bash
# Check IAM permissions
aws iam get-user

# Verify ECR policy allows push
aws ecr get-repository-policy \
    --repository-name data-platform-dbt-dev
```

## Monitoring

### Check Repository Size
```bash
aws ecr describe-repositories \
    --repository-names data-platform-dbt-dev \
    --query 'repositories[0].[repositoryName,repositoryUri]'

# Calculate total size
aws ecr describe-images \
    --repository-name data-platform-dbt-dev \
    --query 'sum(imageDetails[].imageSizeInBytes)'
```

### Set Up CloudWatch Alarms
- Repository size > threshold
- Failed image scans
- Failed pushes
EOF
```

---

## End of Day 2 Checklist

- [x] ECR Terraform module created
- [x] ECR repository deployed with lifecycle policy
- [x] Image tagged with multiple strategies
- [x] Images pushed to ECR successfully
- [x] Push script automated
- [x] Pull testing successful
- [x] Tagging strategy documented
- [x] Operations guide created

---

## 📝 Daily Standup Notes

**Completed Today**:
- Created ECR repository with Terraform
- Pushed dbt Docker image to ECR
- Implemented tagging strategy (version, git SHA, latest)
- Automated push process with script
- Tested image pull and execution
- Documented ECR operations

**Blockers**:
- None

**Tomorrow's Plan**:
- Scan images with Trivy
- Fix vulnerabilities
- Create GitHub Actions workflow
- Sprint demo
- **Milestone Release 1**

---

## 🎯 Success Metric

```bash
# Images in ECR
aws ecr describe-images --repository-name data-platform-dbt-dev
# Should show multiple tags

# Can pull and run
docker pull ${ECR_URL}:latest
docker run --rm ${ECR_URL}:latest dbt --version
# Should work

# Image scanning enabled
aws ecr describe-repositories --repository-names data-platform-dbt-dev \
    --query 'repositories[0].imageScanningConfiguration'
# Should show scanOnPush: true
```

---

## ⏭️ Next: Day 3

Tomorrow: Security scanning, CI/CD automation, Milestone Release 1

**See [day-3.md](./day-3.md)** 🚀
