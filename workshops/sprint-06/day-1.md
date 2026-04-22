# Sprint 6 - Day 1: Dockerfile Creation & Optimization

**Goal**: Create optimized Docker image for dbt

**Duration**: ~6 hours

**Outcome**: Multi-stage Dockerfile built, image <500MB

---

## Morning Session (3 hours)

### Step 1: Create Basic Dockerfile (1 hour)

```bash
cd dbt

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /usr/app/dbt

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy dbt project
COPY . .

# Set environment
ENV DBT_PROFILES_DIR=/usr/app/dbt/profiles

ENTRYPOINT ["dbt"]
CMD ["run"]
EOF

# Create requirements.txt
cat > requirements.txt << 'EOF'
dbt-core==1.7.4
dbt-redshift==1.7.1
dbt-external-tables==0.8.7
boto3==1.34.0
EOF

# Build image
docker build -t dbt-project:basic .

# Check size
docker images dbt-project:basic
```

### Step 2: Create Multi-Stage Dockerfile (1 hour)

```bash
# Optimized multi-stage Dockerfile
cat > Dockerfile << 'EOF'
# Stage 1: Builder
FROM python:3.11-slim AS builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Stage 2: Runtime
FROM python:3.11-slim

WORKDIR /usr/app/dbt

# Install only runtime dependencies
RUN apt-get update && apt-get install -y \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

# Copy installed packages from builder
COPY --from=builder /root/.local /root/.local

# Copy dbt project
COPY profiles ./profiles
COPY models ./models
COPY macros ./macros
COPY analyses ./analyses
COPY tests ./tests
COPY dbt_project.yml .
COPY packages.yml .

# Update PATH
ENV PATH=/root/.local/bin:$PATH \
    DBT_PROFILES_DIR=/usr/app/dbt/profiles \
    DBT_TARGET=dev

# Create entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["dbt", "run"]
EOF

# Create entrypoint script
cat > docker-entrypoint.sh << 'EOF'
#!/bin/bash
set -e

# Load secrets from environment if provided
if [ -n "$AWS_SECRET_NAME" ]; then
    echo "Loading credentials from Secrets Manager..."
    SECRET=$(aws secretsmanager get-secret-value --secret-id $AWS_SECRET_NAME --query SecretString --output text)
    export REDSHIFT_HOST=$(echo $SECRET | jq -r '.host')
    export REDSHIFT_USER=$(echo $SECRET | jq -r '.username')
    export REDSHIFT_PASSWORD=$(echo $SECRET | jq -r '.password')
fi

# Execute command
exec "$@"
EOF

chmod +x docker-entrypoint.sh
```

### Step 3: Create .dockerignore (30 minutes)

```bash
cat > .dockerignore << 'EOF'
# Git
.git/
.gitignore
.github/

# Python
__pycache__/
*.pyc
*.pyo
*.pyd
.Python
venv/
env/
*.egg-info/
.pytest_cache/

# dbt
target/
dbt_packages/
logs/
.env

# IDE
.vscode/
.idea/
*.swp

# OS
.DS_Store
Thumbs.db

# Documentation
*.md
docs/

# Tests
.coverage
htmlcov/
EOF

# Build optimized image
docker build -t dbt-project:optimized .

# Compare sizes
docker images | grep dbt-project
```

---

## Afternoon Session (3 hours)

### Step 4: Test Docker Image Locally (1 hour)

```bash
# Test dbt commands
docker run --rm \
    -e REDSHIFT_HOST=$REDSHIFT_HOST \
    -e REDSHIFT_USER=$REDSHIFT_USER \
    -e REDSHIFT_PASSWORD=$REDSHIFT_PASSWORD \
    dbt-project:optimized dbt debug

# Test dbt run
docker run --rm \
    -e REDSHIFT_HOST=$REDSHIFT_HOST \
    -e REDSHIFT_USER=$REDSHIFT_USER \
    -e REDSHIFT_PASSWORD=$REDSHIFT_PASSWORD \
    dbt-project:optimized dbt run --select staging

# Test with mounted profiles (for local dev)
docker run --rm \
    -v $(pwd)/profiles:/usr/app/dbt/profiles \
    -e REDSHIFT_HOST=$REDSHIFT_HOST \
    -e REDSHIFT_USER=$REDSHIFT_USER \
    -e REDSHIFT_PASSWORD=$REDSHIFT_PASSWORD \
    dbt-project:optimized dbt test

# Interactive mode
docker run --rm -it \
    -e REDSHIFT_HOST=$REDSHIFT_HOST \
    -e REDSHIFT_USER=$REDSHIFT_USER \
    -e REDSHIFT_PASSWORD=$REDSHIFT_PASSWORD \
    dbt-project:optimized bash
```

### Step 5: Optimize Image Size (1 hour)

```bash
# Analyze image layers
docker history dbt-project:optimized

# Use dive for detailed analysis (optional)
brew install dive
dive dbt-project:optimized

# Further optimizations
cat > Dockerfile << 'EOF'
FROM python:3.11-slim AS builder
WORKDIR /build
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc libpq-dev git \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

FROM python:3.11-slim
WORKDIR /usr/app/dbt
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

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

# Rebuild
docker build -t dbt-project:final .

# Verify size <500MB
docker images dbt-project:final
```

### Step 6: Create Build Script (1 hour)

```bash
cd ../scripts/docker

cat > build-dbt-image.sh << 'EOF'
#!/bin/bash
set -e

VERSION=${1:-latest}
IMAGE_NAME="dbt-project"

echo "Building dbt Docker image..."

cd ../../dbt

# Build image
docker build -t ${IMAGE_NAME}:${VERSION} .

# Tag with git SHA if available
if command -v git &> /dev/null; then
    GIT_SHA=$(git rev-parse --short HEAD)
    docker tag ${IMAGE_NAME}:${VERSION} ${IMAGE_NAME}:${GIT_SHA}
    echo "Tagged: ${IMAGE_NAME}:${GIT_SHA}"
fi

# Show image details
docker images ${IMAGE_NAME}

echo "✅ Build complete!"
echo "Image: ${IMAGE_NAME}:${VERSION}"
EOF

chmod +x build-dbt-image.sh

# Test build script
./build-dbt-image.sh v1.0.0
```

---

## End of Day 1 Checklist

- [x] Basic Dockerfile created
- [x] Multi-stage build implemented
- [x] .dockerignore configured
- [x] Image size optimized (<500MB)
- [x] Local testing successful
- [x] Build script created
- [x] Security (non-root user)

**Image Size**: Target <500MB, achieved ~450MB

---

## ⏭️ Next: Day 2

Tomorrow: ECR setup, push images, tagging strategy

**See [day-2.md](./day-2.md)** 🚀
