# Sprint 6 Workshop: Docker Containerization for dbt

**Duration**: Days 16-18 (3 days)

**Goal**: Containerize dbt project for production deployment

---

## Overview

In Sprint 6, you'll:
- Create optimized Dockerfile for dbt
- Implement multi-stage builds to reduce image size
- Configure ECR repository in Terraform
- Build and test container locally
- Push images to Amazon ECR
- Scan images for vulnerabilities
- Create CI/CD workflow for automated builds
- **Achieve Milestone Release 1**: Container ready for orchestration

---

## Prerequisites

Before starting Sprint 6, ensure:
- ✅ Sprint 5 completed successfully
- ✅ dbt models working and tested
- ✅ Docker installed locally
- ✅ AWS CLI configured
- ✅ ECR permissions configured
- ✅ Terraform modules ready

---

## Daily Breakdown

### Day 1: Dockerfile Creation & Optimization
**Duration**: 6 hours

**Morning Session**:
- Create `dbt/Dockerfile` with Python 3.11 base
- Copy requirements.txt and install dependencies
- Copy dbt project files
- Set up entrypoint and default command
- Build image locally: `docker build -t dbt-project:latest`

**Afternoon Session**:
- Implement multi-stage build for optimization
- Add .dockerignore to exclude unnecessary files
- Reduce image size (target: <500MB)
- Add healthcheck
- Document build process

**Deliverables**:
- Optimized Dockerfile (<500MB)
- .dockerignore configured
- Local build successful
- Build documentation

---

### Day 2: ECR Setup & Image Publishing
**Duration**: 6 hours

**Morning Session**:
- Create ECR Terraform module
- Configure repository with lifecycle policies
- Apply Terraform to create ECR repo
- Authenticate Docker with ECR
- Tag and push first image

**Afternoon Session**:
- Test pulling image from ECR
- Run container with environment variables
- Test dbt commands in container
- Create entrypoint script for flexibility
- Implement image tagging strategy (git SHA, latest)

**Deliverables**:
- ECR repository created
- Image pushed to ECR successfully
- Container runs dbt commands
- Tagging strategy documented

---

### Day 3: Security Scanning, CI/CD & Demo
**Duration**: 6 hours

**Morning Session**:
- Scan image with Trivy for vulnerabilities
- Fix critical and high severity issues
- Enable ECR image scanning
- Create GitHub Actions workflow for Docker build
- Test automated build on push

**Afternoon Session**:
- Optimize CI/CD workflow (caching, parallelization)
- Add build status badges
- Document deployment process
- Prepare sprint demo
- Conduct retrospective
- **Milestone Release 1 Complete**

**Deliverables**:
- No critical vulnerabilities
- GitHub Actions workflow operational
- Demo delivered
- Milestone achieved

---

## Acceptance Criteria

By end of Sprint 6:
- ✅ Docker image builds successfully
- ✅ Container runs dbt commands
- ✅ Image pushed to ECR
- ✅ No critical vulnerabilities
- ✅ CI workflow automates build/push
- ✅ **Milestone Release 1**: Production-ready container

---

## Dockerfile Strategy

### Basic Dockerfile
```dockerfile
FROM python:3.11-slim

WORKDIR /usr/app/dbt

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy dbt project
COPY . .

# Set environment
ENV DBT_PROFILES_DIR=/usr/app/dbt/profiles

ENTRYPOINT ["dbt"]
CMD ["run"]
```

### Multi-Stage Optimized Dockerfile
```dockerfile
# Stage 1: Builder
FROM python:3.11-slim AS builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Stage 2: Runtime
FROM python:3.11-slim

WORKDIR /usr/app/dbt

# Install runtime dependencies only
RUN apt-get update && apt-get install -y \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

# Copy installed packages from builder
COPY --from=builder /root/.local /root/.local

# Copy dbt project
COPY . .

# Update PATH
ENV PATH=/root/.local/bin:$PATH \
    DBT_PROFILES_DIR=/usr/app/dbt/profiles

# Add entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["dbt", "run"]
```

---

## .dockerignore Configuration

```
# Git
.git/
.gitignore

# Python
__pycache__/
*.pyc
*.pyo
*.pyd
.Python
venv/
env/
*.egg-info/

# dbt
target/
dbt_packages/
logs/
dbt_modules/

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Documentation
*.md
docs/

# Tests
tests/
.pytest_cache/

# CI/CD
.github/
.gitlab-ci.yml
```

---

## Entrypoint Script

```bash
#!/bin/bash
set -e

# docker-entrypoint.sh
# Flexible entrypoint for dbt container

# Function to wait for Redshift
wait_for_redshift() {
    echo "Waiting for Redshift..."
    # Add connection check logic here
}

# Function to handle secrets
load_secrets() {
    if [ -n "$AWS_SECRET_NAME" ]; then
        echo "Loading secrets from AWS Secrets Manager..."
        # Fetch and export credentials
    fi
}

# Main execution
case "$1" in
    dbt)
        shift
        load_secrets
        wait_for_redshift
        exec dbt "$@"
        ;;
    bash|sh)
        exec "$@"
        ;;
    *)
        exec "$@"
        ;;
esac
```

---

## ECR Terraform Module

```hcl
# terraform/modules/ecr/main.tf
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
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
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

output "repository_url" {
  value = aws_ecr_repository.dbt_project.repository_url
}
```

---

## Build and Push Commands

```bash
# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
REPO_NAME=data-platform-dbt-dev

# Build image
docker build -t dbt-project:latest ./dbt

# Tag for ECR
docker tag dbt-project:latest \
    ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:latest

docker tag dbt-project:latest \
    ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:$(git rev-parse --short HEAD)

# Authenticate with ECR
aws ecr get-login-password --region ${REGION} | \
    docker login --username AWS --password-stdin \
    ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# Push to ECR
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:latest
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:$(git rev-parse --short HEAD)
```

---

## Local Testing

```bash
# Test dbt run
docker run --rm \
    -e REDSHIFT_HOST=xxx.redshift.amazonaws.com \
    -e REDSHIFT_PORT=5439 \
    -e REDSHIFT_USER=admin \
    -e REDSHIFT_PASSWORD=xxx \
    -e REDSHIFT_DATABASE=dev \
    -e DBT_TARGET=dev \
    dbt-project:latest dbt run

# Test dbt test
docker run --rm \
    -e REDSHIFT_HOST=xxx \
    -e REDSHIFT_USER=admin \
    -e REDSHIFT_PASSWORD=xxx \
    dbt-project:latest dbt test

# Interactive mode
docker run --rm -it \
    -e REDSHIFT_HOST=xxx \
    dbt-project:latest bash
```

---

## Security Scanning with Trivy

```bash
# Install Trivy
brew install aquasecurity/trivy/trivy  # macOS
# OR
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get install trivy

# Scan image
trivy image dbt-project:latest

# Scan for HIGH and CRITICAL only
trivy image --severity HIGH,CRITICAL dbt-project:latest

# Generate report
trivy image --format json --output trivy-report.json dbt-project:latest
```

---

## GitHub Actions Workflow

```yaml
# .github/workflows/docker-build.yml
name: Build and Push dbt Docker Image

on:
  push:
    branches: [main, develop]
    paths:
      - 'dbt/**'
      - '.github/workflows/docker-build.yml'
  pull_request:
    paths:
      - 'dbt/**'

env:
  AWS_REGION: us-east-1
  ECR_REPOSITORY: data-platform-dbt-dev

jobs:
  build-and-push:
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
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/github-actions-role
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build Docker image
        working-directory: ./dbt
        run: |
          docker build -t ${{ env.ECR_REPOSITORY }}:${{ github.sha }} .
          docker tag ${{ env.ECR_REPOSITORY }}:${{ github.sha }} ${{ env.ECR_REPOSITORY }}:latest

      - name: Scan image with Trivy
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.ECR_REPOSITORY }}:${{ github.sha }}
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'CRITICAL,HIGH'

      - name: Push to ECR
        if: github.event_name == 'push'
        run: |
          docker push ${{ steps.login-ecr.outputs.registry }}/${{ env.ECR_REPOSITORY }}:${{ github.sha }}
          docker push ${{ steps.login-ecr.outputs.registry }}/${{ env.ECR_REPOSITORY }}:latest

      - name: Image digest
        run: echo ${{ steps.docker_build.outputs.digest }}
```

---

## Image Size Optimization

### Before Optimization
- Base image: ~1.2GB
- With dependencies: ~1.5GB
- Final size: ~1.5GB

### After Multi-Stage Build
- Builder stage: ~1.2GB (discarded)
- Runtime stage: ~450MB
- **Reduction**: 70%

### Optimization Techniques
1. Use `slim` base images
2. Multi-stage builds
3. Remove build dependencies
4. Clean apt cache
5. Use `.dockerignore`
6. Minimize layers

---

## Tagging Strategy

```bash
# Git SHA (unique, immutable)
${ECR_URL}:a1b2c3d

# Semantic version
${ECR_URL}:v1.0.0

# Latest (mutable, points to most recent)
${ECR_URL}:latest

# Environment-specific
${ECR_URL}:dev-latest
${ECR_URL}:prod-v1.0.0

# Date-based
${ECR_URL}:2024-01-15
```

---

## Estimated Story Points

**Total**: 13 points

- Dockerfile creation: 3 points
- Multi-stage optimization: 3 points
- ECR setup: 2 points
- Security scanning: 2 points
- CI/CD workflow: 3 points

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Image size too large | Multi-stage build, slim base |
| Credentials in image | Use environment variables, AWS Secrets Manager |
| Vulnerabilities | Scan with Trivy, update base images regularly |
| Build time too long | Layer caching, parallel builds |

---

## Milestone Release 1 Checklist

- [ ] Dockerfile optimized (<500MB)
- [ ] Image pushed to ECR
- [ ] No critical vulnerabilities
- [ ] CI/CD workflow operational
- [ ] Container runs dbt successfully
- [ ] Documentation complete
- [ ] Demo delivered
- [ ] Team trained on container usage

---

## Next Sprint Preview

**Sprint 7**: AWS MWAA Environment Setup
- Deploy managed Airflow
- Configure MWAA execution roles
- Upload DAGs to S3
- Access Airflow UI
- Run sample DAGs

---

## Resources

- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Multi-Stage Builds](https://docs.docker.com/build/building/multi-stage/)
- [Amazon ECR](https://docs.aws.amazon.com/ecr/)
- [Trivy](https://github.com/aquasecurity/trivy)

---

👉 **Workshop materials**: Detailed day-by-day guides following Sprint 1-2 format. Create them based on deliverables above.
