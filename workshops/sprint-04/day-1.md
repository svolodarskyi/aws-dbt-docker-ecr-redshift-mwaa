# Sprint 4 - Day 1: Redshift Cluster Provisioning

**Goal**: Deploy Redshift cluster with proper security configuration

**Duration**: ~6 hours

**Outcome**: Redshift cluster operational in private subnets

---

## Morning Session (3 hours)

### Step 1: Create Redshift Secrets in Secrets Manager (30 minutes)

```bash
# Generate a strong password
REDSHIFT_PASSWORD=$(openssl rand -base64 32)

# Store in Secrets Manager
aws secretsmanager create-secret \
    --name data-platform/dev/redshift/master \
    --description "Redshift master user credentials" \
    --secret-string "{\"username\":\"admin\",\"password\":\"${REDSHIFT_PASSWORD}\"}" \
    --tags Key=Project,Value=data-platform Key=Environment,Value=dev

# Verify secret created
aws secretsmanager describe-secret \
    --secret-id data-platform/dev/redshift/master

# Get secret ARN (save for Terraform)
SECRET_ARN=$(aws secretsmanager describe-secret \
    --secret-id data-platform/dev/redshift/master \
    --query ARN --output text)

echo "Secret ARN: ${SECRET_ARN}"
```

**✅ Validation**: Secret stored in Secrets Manager

### Step 2: Create Data Terraform Module (1 hour 30 minutes)

```bash
cd terraform/modules

mkdir -p data

cd data

cat > main.tf <<'EOF'
# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_secretsmanager_secret_version" "redshift_master" {
  secret_id = var.redshift_master_secret_arn
}

locals {
  redshift_credentials = jsondecode(data.aws_secretsmanager_secret_version.redshift_master.secret_string)
}

# ---------------------------------------------------------
# Redshift Subnet Group
# ---------------------------------------------------------

resource "aws_redshift_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-redshift-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-${var.environment}-redshift-subnet-group"
  }
}

# ---------------------------------------------------------
# Redshift Parameter Group
# ---------------------------------------------------------

resource "aws_redshift_parameter_group" "main" {
  name   = "${var.project_name}-${var.environment}-redshift-params"
  family = "redshift-1.0"

  parameter {
    name  = "enable_user_activity_logging"
    value = "true"
  }

  parameter {
    name  = "require_ssl"
    value = "true"
  }

  parameter {
    name  = "max_cursor_result_set_size"
    value = "10240"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-redshift-params"
  }
}

# ---------------------------------------------------------
# Redshift Cluster
# ---------------------------------------------------------

resource "aws_redshift_cluster" "main" {
  cluster_identifier = "${var.project_name}-${var.environment}-redshift"
  database_name      = var.database_name
  master_username    = local.redshift_credentials.username
  master_password    = local.redshift_credentials.password

  node_type           = var.node_type
  cluster_type        = var.number_of_nodes > 1 ? "multi-node" : "single-node"
  number_of_nodes     = var.number_of_nodes

  # Network configuration
  cluster_subnet_group_name    = aws_redshift_subnet_group.main.name
  vpc_security_group_ids       = [var.redshift_security_group_id]
  publicly_accessible          = false
  enhanced_vpc_routing         = true

  # Configuration
  cluster_parameter_group_name = aws_redshift_parameter_group.main.name
  encrypted                    = true
  kms_key_id                   = var.kms_key_id

  # IAM role for Spectrum
  iam_roles = [var.redshift_spectrum_role_arn]

  # Maintenance and backup
  automated_snapshot_retention_period = 7
  preferred_maintenance_window        = "sun:05:00-sun:06:00"
  skip_final_snapshot                 = var.environment == "dev" ? true : false
  final_snapshot_identifier           = var.environment == "dev" ? null : "${var.project_name}-${var.environment}-final-snapshot"

  # Monitoring
  logging {
    enable        = true
    bucket_name   = var.logging_bucket_name
    s3_key_prefix = "redshift-logs/"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-redshift"
  }

  lifecycle {
    ignore_changes = [master_password]
  }
}

# ---------------------------------------------------------
# CloudWatch Log Group for Redshift
# ---------------------------------------------------------

resource "aws_cloudwatch_log_group" "redshift" {
  name              = "/aws/redshift/${var.project_name}-${var.environment}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-redshift-logs"
  }
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

variable "database_name" {
  description = "Name of the initial database"
  type        = string
  default     = "dev"
}

variable "node_type" {
  description = "Redshift node type"
  type        = string
  default     = "dc2.large"
}

variable "number_of_nodes" {
  description = "Number of nodes in cluster"
  type        = number
  default     = 2
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "redshift_security_group_id" {
  description = "Security group ID for Redshift"
  type        = string
}

variable "redshift_spectrum_role_arn" {
  description = "IAM role ARN for Redshift Spectrum"
  type        = string
}

variable "redshift_master_secret_arn" {
  description = "ARN of the secret containing master credentials"
  type        = string
}

variable "logging_bucket_name" {
  description = "S3 bucket for Redshift logs"
  type        = string
}

variable "kms_key_id" {
  description = "KMS key ID for encryption (optional)"
  type        = string
  default     = null
}
EOF

cat > outputs.tf <<'EOF'
output "cluster_id" {
  description = "Redshift cluster identifier"
  value       = aws_redshift_cluster.main.cluster_identifier
}

output "cluster_endpoint" {
  description = "Redshift cluster endpoint"
  value       = aws_redshift_cluster.main.endpoint
}

output "cluster_hostname" {
  description = "Redshift cluster hostname"
  value       = split(":", aws_redshift_cluster.main.endpoint)[0]
}

output "cluster_port" {
  description = "Redshift cluster port"
  value       = aws_redshift_cluster.main.port
}

output "database_name" {
  description = "Redshift database name"
  value       = aws_redshift_cluster.main.database_name
}

output "cluster_arn" {
  description = "Redshift cluster ARN"
  value       = aws_redshift_cluster.main.arn
}
EOF
```

**✅ Validation**: Data module created

### Step 3: Reference Data Module in Environment (1 hour)

```bash
cd ../../environments/dev

# Add Redshift configuration
cat > redshift.tf <<'EOF'
module "data" {
  source = "../../modules/data"

  project_name       = var.project_name
  environment        = var.environment
  database_name      = "dev"
  node_type          = "dc2.large"
  number_of_nodes    = 2

  private_subnet_ids           = module.networking.private_subnet_ids
  redshift_security_group_id   = module.networking.security_group_ids.redshift
  redshift_spectrum_role_arn   = module.iam.redshift_spectrum_role_arn
  redshift_master_secret_arn   = var.redshift_master_secret_arn
  logging_bucket_name          = module.storage.raw_data_bucket.id
}

output "redshift" {
  value = {
    cluster_id       = module.data.cluster_id
    cluster_endpoint = module.data.cluster_endpoint
    cluster_hostname = module.data.cluster_hostname
    cluster_port     = module.data.cluster_port
    database_name    = module.data.database_name
  }
  sensitive = true
}
EOF

# Add variable for secret ARN
cat >> variables.tf <<'EOF'

variable "redshift_master_secret_arn" {
  description = "ARN of Secrets Manager secret for Redshift master credentials"
  type        = string
}
EOF

# Add to terraform.tfvars
cat >> terraform.tfvars <<EOF

redshift_master_secret_arn = "${SECRET_ARN}"
EOF

# Format and validate
terraform fmt -recursive ../../
terraform validate

# Create plan
terraform plan

# Expected: Redshift cluster, subnet group, parameter group, logs
```

**✅ Validation**: Plan shows Redshift resources

---

## Afternoon Session (3 hours)

### Step 4: Deploy Redshift Cluster (1 hour 30 minutes)

```bash
# Apply Terraform (this takes ~5-10 minutes)
terraform apply

# Type 'yes' when prompted

# Monitor cluster creation
watch -n 30 'aws redshift describe-clusters \
    --cluster-identifier data-platform-dev-redshift \
    --query "Clusters[0].[ClusterIdentifier,ClusterStatus,NodeType,NumberOfNodes]" \
    --output table'

# Wait until status shows "available"
# This takes approximately 5-10 minutes

# Once available, get cluster details
aws redshift describe-clusters \
    --cluster-identifier data-platform-dev-redshift
```

**✅ Validation**: Cluster status = "available"

### Step 5: Configure dbt Connection (1 hour)

```bash
cd ../../../dbt

# Update profiles.yml with Redshift connection
cat > profiles/profiles.yml <<'EOF'
data_platform:
  outputs:
    dev:
      type: redshift
      host: "{{ env_var('REDSHIFT_HOST') }}"
      port: 5439
      user: "{{ env_var('REDSHIFT_USER') }}"
      password: "{{ env_var('REDSHIFT_PASSWORD') }}"
      dbname: "{{ env_var('REDSHIFT_DATABASE', 'dev') }}"
      schema: staging_schema
      threads: 4
      keepalives_idle: 240
      connect_timeout: 10
      search_path: staging_schema,public
      sslmode: require
      ra3_node: false

    prod:
      type: redshift
      host: "{{ env_var('REDSHIFT_HOST') }}"
      port: 5439
      user: "{{ env_var('REDSHIFT_USER') }}"
      password: "{{ env_var('REDSHIFT_PASSWORD') }}"
      dbname: "{{ env_var('REDSHIFT_DATABASE', 'prod') }}"
      schema: staging_schema
      threads: 8
      keepalives_idle: 240
      connect_timeout: 10
      search_path: staging_schema,public
      sslmode: require
      ra3_node: false

  target: dev
EOF

# Get Redshift connection details
cd ../terraform/environments/dev

REDSHIFT_HOST=$(terraform output -json redshift | jq -r '.cluster_hostname')
REDSHIFT_PORT=$(terraform output -json redshift | jq -r '.cluster_port')
REDSHIFT_DB=$(terraform output -json redshift | jq -r '.database_name')

# Get credentials from Secrets Manager
REDSHIFT_CREDS=$(aws secretsmanager get-secret-value \
    --secret-id data-platform/dev/redshift/master \
    --query SecretString --output text)

REDSHIFT_USER=$(echo $REDSHIFT_CREDS | jq -r '.username')
REDSHIFT_PASSWORD=$(echo $REDSHIFT_CREDS | jq -r '.password')

# Create .env file for dbt (DO NOT COMMIT!)
cd ../../../dbt

cat > .env <<EOF
REDSHIFT_HOST=${REDSHIFT_HOST}
REDSHIFT_PORT=${REDSHIFT_PORT}
REDSHIFT_USER=${REDSHIFT_USER}
REDSHIFT_PASSWORD=${REDSHIFT_PASSWORD}
REDSHIFT_DATABASE=${REDSHIFT_DB}
EOF

# Ensure .env is in .gitignore
echo ".env" >> .gitignore

# Test dbt connection
source ../.venv/bin/activate
export $(cat .env | xargs)

dbt debug --profiles-dir ./profiles --target dev

# Expected output:
# Connection test: [OK connection ok]
```

**✅ Validation**: dbt debug passes

### Step 6: Create Helper Scripts (30 minutes)

```bash
cd ../scripts/redshift

# Create connection script
cat > connect-redshift.sh <<'EOF'
#!/bin/bash
set -e

echo "🔌 Connecting to Redshift..."

# Get credentials from Secrets Manager
CREDS=$(aws secretsmanager get-secret-value \
    --secret-id data-platform/dev/redshift/master \
    --query SecretString --output text)

USERNAME=$(echo $CREDS | jq -r '.username')
PASSWORD=$(echo $CREDS | jq -r '.password')

# Get cluster endpoint from Terraform
cd ../../terraform/environments/dev
ENDPOINT=$(terraform output -json redshift | jq -r '.cluster_endpoint')
HOST=$(echo $ENDPOINT | cut -d':' -f1)
PORT=$(echo $ENDPOINT | cut -d':' -f2)
DATABASE=$(terraform output -json redshift | jq -r '.database_name')

echo "Host: ${HOST}"
echo "Port: ${PORT}"
echo "Database: ${DATABASE}"
echo "Username: ${USERNAME}"
echo ""

# Connect using psql
PGPASSWORD=${PASSWORD} psql \
    -h ${HOST} \
    -p ${PORT} \
    -U ${USERNAME} \
    -d ${DATABASE}
EOF

chmod +x connect-redshift.sh

# Create pause/resume scripts for cost savings
cat > pause-cluster.sh <<'EOF'
#!/bin/bash
set -e

CLUSTER_ID="data-platform-dev-redshift"

echo "⏸️  Pausing Redshift cluster: ${CLUSTER_ID}..."

aws redshift pause-cluster --cluster-identifier ${CLUSTER_ID}

echo "✅ Cluster pause initiated"
echo "Cluster will be paused in ~1 minute"
EOF

chmod +x pause-cluster.sh

cat > resume-cluster.sh <<'EOF'
#!/bin/bash
set -e

CLUSTER_ID="data-platform-dev-redshift"

echo "▶️  Resuming Redshift cluster: ${CLUSTER_ID}..."

aws redshift resume-cluster --cluster-identifier ${CLUSTER_ID}

echo "✅ Cluster resume initiated"
echo "Cluster will be available in ~2-3 minutes"
EOF

chmod +x resume-cluster.sh
```

**✅ Validation**: Helper scripts created

---

## End of Day 1 Checklist

- [x] Redshift master credentials stored in Secrets Manager
- [x] Data Terraform module created
- [x] Redshift subnet group configured
- [x] Redshift parameter group with SSL required
- [x] Redshift cluster deployed (2 nodes, dc2.large)
- [x] Cluster encrypted and in private subnets
- [x] dbt profiles.yml configured with Redshift
- [x] dbt debug connection test passes
- [x] Helper scripts created (connect, pause, resume)

---

## 📝 Daily Standup Notes

**Completed Today**:
- Stored Redshift credentials securely in Secrets Manager
- Created data Terraform module
- Deployed 2-node Redshift cluster in private subnets
- Configured dbt connection to Redshift
- Created helper scripts for cluster management

**Blockers**:
- None (cluster takes 5-10 min to provision - expected)

**Tomorrow's Plan**:
- Connect to Redshift and create database schemas
- Set up Glue Data Catalog
- Configure Redshift Spectrum external schema
- Test querying S3 data via Spectrum

---

## 🎯 Success Metric

**You're successful if**:

```bash
# Cluster is available
aws redshift describe-clusters \
    --cluster-identifier data-platform-dev-redshift \
    --query 'Clusters[0].ClusterStatus' --output text
# Should return: available

# dbt can connect
cd dbt
export $(cat .env | xargs)
dbt debug --profiles-dir ./profiles --target dev
# Should show: Connection test: [OK connection ok]

# Can connect via psql
cd ../scripts/redshift
./connect-redshift.sh
# Should connect successfully
```

---

## 💰 Cost Note

**Redshift dc2.large (2 nodes)**:
- Cost: ~$0.25/hour = ~$360/month (continuous)
- **Optimization**: Pause during off-hours
  - Weeknights (8 PM - 8 AM): 12 hours/day = 50% savings
  - Weekends: Full pause = additional savings
  - **Potential savings**: ~$180/month (50%)

**To pause now**:
```bash
cd scripts/redshift
./pause-cluster.sh
```

**To resume tomorrow**:
```bash
./resume-cluster.sh
```

---

## ⏭️ Next: Day 2

Tomorrow you'll:
- Create database schemas (raw, staging, analytics, audit)
- Set up Glue Data Catalog
- Configure Redshift Spectrum external schema
- Test querying S3 data

**See [day-2.md](./day-2.md)** 🚀
