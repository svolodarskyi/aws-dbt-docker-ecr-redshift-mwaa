# Sprint 3 - Day 1: S3 Bucket Creation & Lifecycle Policies

**Goal**: Create S3 data lake structure with bucket policies and lifecycle management

**Duration**: ~6 hours

**Outcome**: S3 buckets deployed, folder structure created, lifecycle policies active

---

## Morning Session (3 hours)

### Step 1: Create Storage Terraform Module (1 hour 30 minutes)

```bash
cd terraform/modules

# Create storage module
mkdir -p storage

cd storage

cat > main.tf <<'EOF'
# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------
# S3 Bucket: Raw Data
# ---------------------------------------------------------

resource "aws_s3_bucket" "raw_data" {
  bucket = "${var.project_name}-raw-data-${var.environment}"

  tags = {
    Name        = "${var.project_name}-raw-data-${var.environment}"
    DataZone    = "raw"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    filter {
      prefix = "processed/"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }

  rule {
    id     = "delete-old-landing"
    status = "Enabled"

    filter {
      prefix = "landing/"
    }

    expiration {
      days = 7
    }
  }

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# ---------------------------------------------------------
# S3 Bucket: dbt Artifacts
# ---------------------------------------------------------

resource "aws_s3_bucket" "dbt_artifacts" {
  bucket = "${var.project_name}-dbt-artifacts-${var.environment}"

  tags = {
    Name        = "${var.project_name}-dbt-artifacts-${var.environment}"
    Purpose     = "dbt logs, manifests, compiled SQL"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "dbt_artifacts" {
  bucket = aws_s3_bucket.dbt_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dbt_artifacts" {
  bucket = aws_s3_bucket.dbt_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "dbt_artifacts" {
  bucket = aws_s3_bucket.dbt_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "dbt_artifacts" {
  bucket = aws_s3_bucket.dbt_artifacts.id

  rule {
    id     = "delete-old-logs"
    status = "Enabled"

    filter {
      prefix = "logs/"
    }

    expiration {
      days = 30
    }
  }
}

# ---------------------------------------------------------
# S3 Bucket: MWAA (Airflow)
# ---------------------------------------------------------

resource "aws_s3_bucket" "mwaa" {
  bucket = "${var.project_name}-mwaa-${var.environment}"

  tags = {
    Name        = "${var.project_name}-mwaa-${var.environment}"
    Purpose     = "MWAA DAGs, plugins, requirements"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "mwaa" {
  bucket = aws_s3_bucket.mwaa.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mwaa" {
  bucket = aws_s3_bucket.mwaa.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "mwaa" {
  bucket = aws_s3_bucket.mwaa.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------
# S3 Bucket Policies
# ---------------------------------------------------------

resource "aws_s3_bucket_policy" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnforceSSLOnly"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          "${aws_s3_bucket.raw_data.arn}",
          "${aws_s3_bucket.raw_data.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "mwaa" {
  bucket = aws_s3_bucket.mwaa.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnforceSSLOnly"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          "${aws_s3_bucket.mwaa.arn}",
          "${aws_s3_bucket.mwaa.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
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
output "raw_data_bucket" {
  description = "Raw data S3 bucket details"
  value = {
    id  = aws_s3_bucket.raw_data.id
    arn = aws_s3_bucket.raw_data.arn
  }
}

output "dbt_artifacts_bucket" {
  description = "dbt artifacts S3 bucket details"
  value = {
    id  = aws_s3_bucket.dbt_artifacts.id
    arn = aws_s3_bucket.dbt_artifacts.arn
  }
}

output "mwaa_bucket" {
  description = "MWAA S3 bucket details"
  value = {
    id  = aws_s3_bucket.mwaa.id
    arn = aws_s3_bucket.mwaa.arn
  }
}
EOF
```

**✅ Validation**: Storage module created

### Step 2: Reference Storage Module in Environment (30 minutes)

```bash
cd ../../environments/dev

cat > storage.tf <<'EOF'
module "storage" {
  source = "../../modules/storage"

  project_name = var.project_name
  environment  = var.environment
}

output "storage" {
  value = {
    raw_data_bucket      = module.storage.raw_data_bucket
    dbt_artifacts_bucket = module.storage.dbt_artifacts_bucket
    mwaa_bucket          = module.storage.mwaa_bucket
  }
}
EOF

# Format and validate
terraform fmt -recursive ../../
terraform validate

# Create plan
terraform plan

# Expected: 3 S3 buckets + configurations (~20 resources)
```

**✅ Validation**: Plan shows bucket resources

### Step 3: Deploy S3 Buckets (1 hour)

```bash
# Apply Terraform
terraform apply

# Type 'yes' when prompted

# Expected: Apply complete! Resources: ~20 added

# Verify buckets created
aws s3 ls | grep data-platform

# Expected output:
# 2024-xx-xx xx:xx:xx data-platform-raw-data-dev
# 2024-xx-xx xx:xx:xx data-platform-dbt-artifacts-dev
# 2024-xx-xx xx:xx:xx data-platform-mwaa-dev

# Check versioning enabled
aws s3api get-bucket-versioning \
  --bucket data-platform-raw-data-dev

# Expected: "Status": "Enabled"

# Check encryption
aws s3api get-bucket-encryption \
  --bucket data-platform-raw-data-dev

# Expected: "SSEAlgorithm": "AES256"
```

**✅ Validation**: All buckets created and configured

---

## Afternoon Session (3 hours)

### Step 4: Create Folder Structure in Raw Data Bucket (1 hour)

```bash
# Create folder structure script
cat > ../../scripts/storage/create-folder-structure.sh <<'EOF'
#!/bin/bash
set -e

BUCKET_NAME=${1:-data-platform-raw-data-dev}

echo "Creating folder structure in ${BUCKET_NAME}..."

# Landing zone folders
aws s3api put-object --bucket ${BUCKET_NAME} --key landing/
aws s3api put-object --bucket ${BUCKET_NAME} --key landing/sales/
aws s3api put-object --bucket ${BUCKET_NAME} --key landing/customers/
aws s3api put-object --bucket ${BUCKET_NAME} --key landing/products/

# Raw zone folders
aws s3api put-object --bucket ${BUCKET_NAME} --key raw/
aws s3api put-object --bucket ${BUCKET_NAME} --key raw/sales/
aws s3api put-object --bucket ${BUCKET_NAME} --key raw/customers/
aws s3api put-object --bucket ${BUCKET_NAME} --key raw/products/

# Processed zone folders
aws s3api put-object --bucket ${BUCKET_NAME} --key processed/
aws s3api put-object --bucket ${BUCKET_NAME} --key processed/analytics/
aws s3api put-object --bucket ${BUCKET_NAME} --key processed/reporting/

# Archive folder
aws s3api put-object --bucket ${BUCKET_NAME} --key archive/

echo "✅ Folder structure created"

# Verify
echo ""
echo "Folder structure:"
aws s3 ls s3://${BUCKET_NAME}/ --recursive | grep '/$'
EOF

chmod +x ../../scripts/storage/create-folder-structure.sh

# Run the script
../../scripts/storage/create-folder-structure.sh

# Verify folder structure
aws s3 ls s3://data-platform-raw-data-dev/ --recursive

# Expected output:
# landing/
# landing/sales/
# landing/customers/
# ...
```

**✅ Validation**: Folder structure created

### Step 5: Create MWAA Folder Structure (30 minutes)

```bash
# Create MWAA folder structure script
cat > ../../scripts/storage/setup-mwaa-bucket.sh <<'EOF'
#!/bin/bash
set -e

BUCKET_NAME=${1:-data-platform-mwaa-dev}

echo "Setting up MWAA bucket: ${BUCKET_NAME}..."

# Create folder structure
aws s3api put-object --bucket ${BUCKET_NAME} --key dags/
aws s3api put-object --bucket ${BUCKET_NAME} --key plugins/
aws s3api put-object --bucket ${BUCKET_NAME} --key requirements.txt --body /dev/null

# Create sample requirements.txt
cat > /tmp/requirements.txt <<'REQS'
# Airflow providers
apache-airflow-providers-amazon==8.13.0
apache-airflow-providers-postgres==5.7.1

# dbt orchestration
astronomer-cosmos==1.4.0

# Utilities
pandas==2.1.4
boto3==1.34.0
REQS

# Upload requirements.txt
aws s3 cp /tmp/requirements.txt s3://${BUCKET_NAME}/requirements.txt

echo "✅ MWAA bucket configured"

# Verify
aws s3 ls s3://${BUCKET_NAME}/ --recursive
EOF

chmod +x ../../scripts/storage/setup-mwaa-bucket.sh

# Run the script
../../scripts/storage/setup-mwaa-bucket.sh

# Verify
aws s3 ls s3://data-platform-mwaa-dev/
```

**✅ Validation**: MWAA bucket configured

### Step 6: Document Bucket Structure and Policies (1 hour 30 minutes)

```bash
# Create documentation
cat > ../../docs/S3_BUCKET_STRUCTURE.md <<'EOF'
# S3 Bucket Structure

## Overview

The data platform uses three main S3 buckets for data storage, artifacts, and orchestration.

---

## Bucket 1: Raw Data (`data-platform-raw-data-dev`)

**Purpose**: Store all raw data from various sources

### Folder Structure

```
data-platform-raw-data-dev/
├── landing/              # Incoming data drops (7-day retention)
│   ├── sales/
│   │   └── YYYY-MM-DD/
│   ├── customers/
│   │   └── YYYY-MM-DD/
│   └── products/
│       └── YYYY-MM-DD/
│
├── raw/                  # Validated and organized data
│   ├── sales/
│   │   ├── orders/
│   │   │   └── YYYY-MM-DD/
│   │   └── order_items/
│   │       └── YYYY-MM-DD/
│   ├── customers/
│   │   └── YYYY-MM-DD/
│   └── products/
│       └── YYYY-MM-DD/
│
├── processed/            # Transformed data (30-day STANDARD, then IA)
│   ├── analytics/
│   │   └── YYYY-MM-DD/
│   └── reporting/
│       └── YYYY-MM-DD/
│
└── archive/              # Historical data (90-day IA, then Glacier)
    └── YYYY-MM-DD/
```

### Lifecycle Policies

| Path | Lifecycle | Retention |
|------|-----------|-----------|
| `landing/*` | Delete after 7 days | 7 days |
| `raw/*` | Keep in STANDARD | Indefinite |
| `processed/*` | STANDARD → IA (30d) → Glacier (90d) → Delete (365d) | 1 year |
| `archive/*` | IA (immediate) → Glacier (90d) | Indefinite |

### Versioning

- **Enabled**: Yes
- **Noncurrent versions**: Expire after 30 days

### Encryption

- **Type**: SSE-S3 (AES-256)
- **Enforced**: Yes (SSL/TLS required)

---

## Bucket 2: dbt Artifacts (`data-platform-dbt-artifacts-dev`)

**Purpose**: Store dbt outputs, logs, and manifests

### Folder Structure

```
data-platform-dbt-artifacts-dev/
├── logs/                # dbt run logs (30-day retention)
│   └── YYYY-MM-DD/
│       └── run_id.log
│
├── target/              # dbt compile output
│   ├── manifest.json
│   ├── catalog.json
│   └── run_results.json
│
└── compiled/            # Compiled SQL
    └── YYYY-MM-DD/
```

### Lifecycle Policies

| Path | Lifecycle | Retention |
|------|-----------|-----------|
| `logs/*` | Delete after 30 days | 30 days |
| `target/*` | Keep latest 10 versions | Indefinite |
| `compiled/*` | Delete after 90 days | 90 days |

---

## Bucket 3: MWAA (`data-platform-mwaa-dev`)

**Purpose**: Airflow DAGs, plugins, and requirements

### Folder Structure

```
data-platform-mwaa-dev/
├── dags/                # Airflow DAG files
│   ├── data_ingestion.py
│   ├── dbt_transform.py
│   └── utilities/
│       └── helper.py
│
├── plugins/             # Custom Airflow plugins
│   └── custom_operators/
│
└── requirements.txt     # Python dependencies for MWAA
```

### Versioning

- **Enabled**: Yes (required by MWAA)
- **DAG sync frequency**: Every 5 minutes

---

## Naming Conventions

### Buckets
Format: `{project}-{purpose}-{environment}`
- Example: `data-platform-raw-data-dev`

### File Paths
Format: `{zone}/{source}/{table}/YYYY-MM-DD/filename.ext`
- Example: `landing/sales/orders/2024-01-15/orders_20240115.csv`

### Date Partitions
- Format: `YYYY-MM-DD` (ISO 8601)
- Timezone: UTC
- Example: `2024-01-15`

---

## Access Patterns

### Landing Zone
- **Write**: Data ingestion processes
- **Read**: Validation scripts
- **TTL**: 7 days (auto-delete)

### Raw Zone
- **Write**: Validated data movers
- **Read**: dbt external tables, Redshift Spectrum
- **TTL**: Indefinite

### Processed Zone
- **Write**: dbt, Spark jobs
- **Read**: BI tools, analysts
- **TTL**: 1 year (with archival tiers)

---

## Security

### Encryption
- At rest: SSE-S3 (AES-256)
- In transit: TLS 1.2+ (enforced by bucket policy)

### Access Control
- Public access: **Blocked**
- IAM roles: Principle of least privilege
- Bucket policies: Deny non-SSL requests

### Compliance
- Versioning: Enabled (audit trail)
- Logging: S3 access logs (optional, can enable later)
- MFA Delete: Disabled (can enable for prod)

---

## Cost Optimization

### Storage Classes

| Class | Use Case | Cost (per GB/month) |
|-------|----------|---------------------|
| STANDARD | Active data (landing, raw) | $0.023 |
| STANDARD_IA | Infrequent access (processed 30d+) | $0.0125 |
| GLACIER | Archive (processed 90d+) | $0.004 |

### Estimates (1TB monthly ingestion)

- Landing: 1TB × 7 days ≈ 0.23TB × $0.023 = **$5/month**
- Raw: 12TB/year × $0.023 = **$276/year**
- Processed: Tiered storage = **~$100/year**
- **Total S3**: ~$30-40/month

---

## Monitoring

### CloudWatch Metrics
- Bucket size
- Number of objects
- Request metrics (optional, additional cost)

### Alerts
- Rapid growth (>20% increase per day)
- Failed lifecycle transitions
- High error rates

---

## Future Enhancements

- [ ] Enable S3 access logging
- [ ] S3 Intelligent-Tiering for processed zone
- [ ] Cross-region replication (DR)
- [ ] S3 Object Lock for compliance
- [ ] Athena for ad-hoc querying
EOF
```

**✅ Validation**: Documentation complete

---

## End of Day 1 Checklist

- [x] Storage Terraform module created
- [x] 3 S3 buckets deployed
- [x] Versioning enabled on all buckets
- [x] Encryption configured (SSE-S3)
- [x] Public access blocked
- [x] Lifecycle policies configured
- [x] Folder structure created in raw-data bucket
- [x] MWAA bucket configured
- [x] Bucket structure documented

---

## 📝 Daily Standup Notes

**Completed Today**:
- Created storage Terraform module
- Deployed 3 S3 buckets with encryption and versioning
- Configured lifecycle policies for cost optimization
- Created folder structure for data lake
- Documented bucket architecture

**Blockers**:
- None

**Tomorrow's Plan**:
- Set up EventBridge rules for S3 events
- Prepare sample datasets
- Test S3 event notifications
- Create data upload scripts

---

## 🎯 Success Metric

**You're successful if**:

```bash
# All buckets exist
aws s3 ls | grep data-platform | wc -l
# Should return: 3

# Versioning enabled
aws s3api get-bucket-versioning --bucket data-platform-raw-data-dev
# Should show: "Status": "Enabled"

# Lifecycle policy configured
aws s3api get-bucket-lifecycle-configuration --bucket data-platform-raw-data-dev
# Should show rules

# Folder structure exists
aws s3 ls s3://data-platform-raw-data-dev/ | grep landing
# Should show landing/ folder
```

---

## ⏭️ Next: Day 2

Tomorrow you'll:
- Create EventBridge rules for S3 events
- Prepare sample datasets (CSV, JSON, Parquet)
- Test event-driven triggers
- Create data upload scripts

**See [day-2.md](./day-2.md)** 🚀
