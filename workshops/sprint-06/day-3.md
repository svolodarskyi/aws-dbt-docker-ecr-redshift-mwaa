# Sprint 6 - Day 3: Security Scanning, CI/CD & Milestone Release

**Goal**: Security scanning, GitHub Actions automation, Milestone Release 1

**Duration**: ~6 hours

**Outcome**: Secure, automated Docker builds - **MILESTONE RELEASE 1** 🎉

---

## Morning Session (3 hours)

### Step 1: Install and Run Trivy Security Scanner (1 hour)

```bash
# Install Trivy (macOS)
brew install aquasecurity/trivy/trivy

# Linux installation
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get install trivy

# Verify installation
trivy --version

# Scan local image
cd dbt
docker build -t dbt-project:scan-test .

trivy image dbt-project:scan-test

# Scan with severity filter (HIGH and CRITICAL only)
trivy image --severity HIGH,CRITICAL dbt-project:scan-test

# Generate JSON report
trivy image --format json --output trivy-report.json dbt-project:scan-test

# Generate table report
trivy image --format table --output trivy-report.txt dbt-project:scan-test

# View report
cat trivy-report.txt
```

### Step 2: Fix Critical Vulnerabilities (1 hour)

```bash
# Common fixes:

# 1. Update base image
cat > Dockerfile <<'EOF'
# Use latest patch version
FROM python:3.11.8-slim AS builder

WORKDIR /build
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc libpq-dev git \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir --user -r requirements.txt

FROM python:3.11.8-slim

WORKDIR /usr/app/dbt

# Install security updates
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends libpq5 && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /root/.local /root/.local
COPY --chown=nobody:nogroup profiles ./profiles
COPY --chown=nobody:nogroup models ./models
COPY --chown=nobody:nogroup macros ./macros
COPY --chown=nobody:nogroup dbt_project.yml packages.yml ./
COPY docker-entrypoint.sh /usr/local/bin/

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENV PATH=/root/.local/bin:$PATH \
    DBT_PROFILES_DIR=/usr/app/dbt/profiles \
    PYTHONUNBUFFERED=1

USER nobody

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["dbt", "run"]
EOF

# 2. Update Python dependencies
cat > requirements.txt <<'EOF'
dbt-core==1.7.6
dbt-redshift==1.7.3
dbt-external-tables==0.8.7
boto3==1.34.34
psycopg2-binary==2.9.9
EOF

# Rebuild and rescan
docker build -t dbt-project:secure .
trivy image --severity HIGH,CRITICAL dbt-project:secure

# Repeat until no CRITICAL vulnerabilities
```

### Step 3: Create Scanning Script (1 hour)

```bash
cd ../scripts/docker

cat > scan-image.sh <<'EOF'
#!/bin/bash
set -e

IMAGE=${1:-dbt-project:latest}
SEVERITY=${2:-HIGH,CRITICAL}

echo "🔍 Scanning image: ${IMAGE}"
echo "Severity levels: ${SEVERITY}"
echo ""

# Scan image
trivy image --severity ${SEVERITY} ${IMAGE}

# Generate reports
REPORT_DIR="../../security-reports"
mkdir -p ${REPORT_DIR}

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
JSON_REPORT="${REPORT_DIR}/trivy-${TIMESTAMP}.json"
HTML_REPORT="${REPORT_DIR}/trivy-${TIMESTAMP}.html"

echo ""
echo "📊 Generating reports..."

trivy image --format json --output ${JSON_REPORT} ${IMAGE}
trivy image --format template --template '@contrib/html.tpl' --output ${HTML_REPORT} ${IMAGE}

echo "✅ Reports generated:"
echo "  - JSON: ${JSON_REPORT}"
echo "  - HTML: ${HTML_REPORT}"

# Check for CRITICAL vulnerabilities
CRITICAL_COUNT=$(trivy image --format json ${IMAGE} | jq '[.Results[].Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length')

echo ""
if [ "$CRITICAL_COUNT" -gt 0 ]; then
    echo "❌ CRITICAL vulnerabilities found: ${CRITICAL_COUNT}"
    echo "Fix these before deploying to production!"
    exit 1
else
    echo "✅ No CRITICAL vulnerabilities found"
fi
EOF

chmod +x scan-image.sh

# Test scanning script
./scan-image.sh dbt-project:secure

# Add to .gitignore
echo "security-reports/" >> ../../.gitignore
```

---

## Afternoon Session (3 hours)

### Step 4: Create GitHub Actions Workflow (1 hour 30 minutes)

```bash
cd ../../

mkdir -p .github/workflows

cat > .github/workflows/docker-build.yml <<'EOF'
name: Build and Push dbt Docker Image

on:
  push:
    branches: [main, develop]
    paths:
      - 'dbt/**'
      - '.github/workflows/docker-build.yml'
  pull_request:
    branches: [main, develop]
    paths:
      - 'dbt/**'

env:
  AWS_REGION: us-east-1
  ECR_REPOSITORY: data-platform-dbt-dev

permissions:
  id-token: write
  contents: read
  security-events: write

jobs:
  build-and-scan:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build Docker image
        working-directory: ./dbt
        run: |
          docker build -t dbt-project:${{ github.sha }} .
          docker tag dbt-project:${{ github.sha }} dbt-project:latest

      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: 'dbt-project:${{ github.sha }}'
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
          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            aquasec/trivy:latest image \
            --severity CRITICAL \
            --exit-code 1 \
            dbt-project:${{ github.sha }}

  push-to-ecr:
    needs: build-and-scan
    if: github.event_name == 'push'
    runs-on: ubuntu-latest

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

      - name: Build, tag, and push image
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}
        working-directory: ./dbt
        run: |
          # Build
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .

          # Tag
          docker tag $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG $ECR_REGISTRY/$ECR_REPOSITORY:latest

          # Tag with version if on main branch
          if [ "${{ github.ref }}" == "refs/heads/main" ]; then
            VERSION=$(cat VERSION || echo "v1.0.0")
            docker tag $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG $ECR_REGISTRY/$ECR_REPOSITORY:$VERSION
            docker push $ECR_REGISTRY/$ECR_REPOSITORY:$VERSION
          fi

          # Push
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest

      - name: Image digest
        run: echo "Image pushed with digest ${{ steps.docker_build.outputs.digest }}"

      - name: Scan image in ECR
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          aws ecr start-image-scan \
            --repository-name $ECR_REPOSITORY \
            --image-id imageTag=$IMAGE_TAG \
            --region $AWS_REGION
EOF

# Create VERSION file
echo "v1.0.0" > dbt/VERSION

# Create GitHub OIDC role (Terraform)
cat > terraform/modules/github-actions/main.tf <<'EOF'
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]
}

resource "aws_iam_role" "github_actions" {
  name = "github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

variable "github_repo" {
  description = "GitHub repository (org/repo)"
  type        = string
}

output "role_arn" {
  value = aws_iam_role.github_actions.arn
}
EOF
```

### Step 5: Test CI/CD Workflow (30 minutes)

```bash
# Commit and push to trigger workflow
git add .
git commit -m "feat: add Docker build CI/CD workflow

- Trivy security scanning
- Automated ECR push
- GitHub Security integration
- Multi-stage build optimization

Sprint 6 Day 3 - Milestone Release 1"

git push origin develop

# Monitor workflow
# Go to GitHub → Actions → Watch workflow run

# Verify image in ECR after workflow completes
aws ecr describe-images \
    --repository-name data-platform-dbt-dev \
    --query 'imageDetails[*].[imageTags[0],imagePushedAt]' \
    --output table
```

### Step 6: Sprint Demo & Milestone Release (1 hour)

```bash
cd docs/demos

mkdir -p sprint-06

cat > sprint-06/DEMO_SCRIPT.md <<'EOF'
# Sprint 6 Demo: Docker & ECR - Milestone Release 1 🎉

## Demo Flow (15 min)

### 1. Dockerized dbt (3 min)

**SHOW**: Dockerfile
- Multi-stage build
- Optimized size (<500MB)
- Non-root user
- Security best practices

**RUN**: Local container
```bash
docker run --rm dbt-project:latest dbt --version
```

### 2. ECR Repository (3 min)

**SHOW**: AWS Console → ECR
- Repository: data-platform-dbt-dev
- Lifecycle policy
- Image scanning enabled

**SHOW**: Images with tags
- latest
- v1.0.0
- git-abc123

### 3. Security Scanning (3 min)

**SHOW**: Trivy scan results
```bash
trivy image dbt-project:latest
```

**HIGHLIGHT**:
- No CRITICAL vulnerabilities
- Automated scanning in CI/CD
- GitHub Security integration

### 4. GitHub Actions CI/CD (4 min)

**SHOW**: .github/workflows/docker-build.yml

**Workflow**:
1. Build image on PR/push
2. Scan with Trivy
3. Block if CRITICAL vulns
4. Push to ECR (main/develop only)
5. Auto-tag with git SHA

**SHOW**: GitHub Actions run
- All checks passed ✅
- Image in ECR

### 5. End-to-End Test (2 min)

**RUN**: Pull from ECR and execute
```bash
docker pull ${ECR_URL}:latest
docker run --rm \
    -e AWS_SECRET_NAME=data-platform/dev/redshift/master \
    ${ECR_URL}:latest dbt run --select staging
```

**Result**: dbt runs successfully from containerized image

## 🎉 Milestone Release 1

**Achieved**:
✅ dbt containerized (<500MB)
✅ Images in ECR with lifecycle policy
✅ Security scanning (no critical vulns)
✅ CI/CD automation
✅ Production-ready container

**Next**: Sprint 7 - MWAA will use this container!

## Q&A

**Q**: "Why containerize dbt?"
**A**: "Consistency across environments, easy deployment to ECS/MWAA, version control of entire runtime."

**Q**: "Image size?"
**A**: "~450MB with multi-stage build. Started at 1.2GB."

**Q**: "Security?"
**A**: "Trivy scans on every build, non-root user, minimal base image, automated patching."
EOF

# Retrospective
cat > ../retrospectives/sprint-06.md <<'EOF'
# Sprint 6 Retrospective

**Sprint**: 6/14
**Goal**: Docker Containerization for dbt

## 🎉 MILESTONE RELEASE 1 ACHIEVED

## Metrics

| Metric | Target | Actual |
|--------|--------|--------|
| Image Size | <500MB | ~450MB ✅ |
| Build Time | <5 min | ~3 min ✅ |
| Vulnerabilities | 0 Critical | 0 Critical ✅ |
| CI/CD Automated | Yes | Yes ✅ |

## Accomplishments

✅ Multi-stage Dockerfile (70% size reduction)
✅ ECR repository with lifecycle policy
✅ Security scanning with Trivy
✅ GitHub Actions CI/CD workflow
✅ Automated tagging strategy
✅ **Milestone Release 1**

## What Went Well

1. Multi-stage build dramatically reduced size
2. Trivy found and we fixed vulnerabilities
3. GitHub Actions workflow smooth
4. Good documentation created

## What Didn't Go Well

1. Initial image size was huge (1.2GB)
2. Some trial and error with .dockerignore
3. ECR authentication needed refreshing

## Lessons Learned

1. Always use multi-stage builds
2. Scan early and often
3. Document tagging strategy upfront
4. Test pulled images, not just built

## Sprint 7 Preview

**Goal**: AWS MWAA Environment Setup
- Deploy managed Airflow
- Use this Docker image!
- Create DAGs
- Access Airflow UI
EOF

# Final commit
cd ../../..

git add -A
git commit -m "feat: complete Sprint 6 - Docker Containerization

Day 1:
- Created optimized Dockerfile with multi-stage build
- Reduced image size from 1.2GB to 450MB
- Implemented security best practices

Day 2:
- Created ECR repository with Terraform
- Pushed images with multiple tagging strategies
- Automated push process

Day 3:
- Implemented Trivy security scanning
- Fixed all CRITICAL vulnerabilities
- Created GitHub Actions CI/CD workflow
- Automated build, scan, and push

🎉 MILESTONE RELEASE 1 ACHIEVED

Production-ready dbt container:
- Size: 450MB ✅
- Security: 0 Critical vulnerabilities ✅
- CI/CD: Fully automated ✅
- ECR: Images tagged and lifecycle managed ✅

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

git push origin develop
```

---

## End of Day 3 Checklist

- [x] Trivy security scanner installed
- [x] Images scanned for vulnerabilities
- [x] All CRITICAL vulnerabilities fixed
- [x] Security scanning script created
- [x] GitHub Actions workflow created
- [x] CI/CD tested and working
- [x] Sprint demo delivered
- [x] **MILESTONE RELEASE 1** achieved
- [x] Sprint retrospective completed

---

## 🎉 Sprint 6 Complete - MILESTONE RELEASE 1!

### Deliverables

✅ Optimized Docker image (450MB, was 1.2GB)
✅ Multi-stage build
✅ ECR repository with lifecycle policy
✅ Security scanning (0 CRITICAL vulnerabilities)
✅ GitHub Actions CI/CD
✅ Automated tagging strategy
✅ Complete documentation

### Milestone Release 1 Achievements

**Container Ready for Production**:
- ✅ Size optimized
- ✅ Security hardened
- ✅ CI/CD automated
- ✅ Versioned and tagged
- ✅ Ready for MWAA/ECS

### Impact

This containerized dbt image will be used in:
- **Sprint 7**: MWAA environment
- **Sprint 8**: ECS Fargate tasks
- **Sprint 9**: Automated CI/CD deployments
- **Production**: Scheduled data transformations

---

## 📊 Sprint 6 Statistics

- **Image size reduction**: 70% (1.2GB → 450MB)
- **Vulnerabilities fixed**: All CRITICAL
- **Build time**: ~3 minutes
- **Tags pushed**: 3 per build (version, git SHA, latest)
- **Automation**: 100% (GitHub Actions)

---

## ⏭️ Next: Sprint 7

**Sprint 7**: AWS MWAA Environment Setup

**You'll deploy**:
- MWAA (managed Apache Airflow)
- Configure to use this Docker image
- Create and deploy DAGs
- Access Airflow UI
- Run first orchestrated pipeline

**See `workshops/sprint-07/`** 🚀

---

**Congratulations on Milestone Release 1!** 🎊

You now have a production-ready, containerized dbt project that's:
- Secure
- Optimized
- Automated
- Version controlled
- Ready for orchestration

**Excellent progress!** 💪
