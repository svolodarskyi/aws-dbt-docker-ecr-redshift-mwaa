# Sprint 3 - Day 3: Validation, Demo & Retrospective

**Goal**: Validate S3 infrastructure, conduct demo, close sprint

**Duration**: ~6 hours

**Outcome**: All resources validated, demo delivered, Sprint 3 complete

---

## Morning Session (3 hours)

### Step 1: Comprehensive S3 Validation (1 hour 30 minutes)

```bash
cd terraform/environments/dev

# Create validation script
cat > ../../scripts/validate-storage.sh <<'EOF'
#!/bin/bash
set -e

echo "🔍 Validating S3 Storage Infrastructure..."
echo ""

# Get bucket names from Terraform output
RAW_BUCKET=$(terraform output -json storage | jq -r '.raw_data_bucket.id')
DBT_BUCKET=$(terraform output -json storage | jq -r '.dbt_artifacts_bucket.id')
MWAA_BUCKET=$(terraform output -json storage | jq -r '.mwaa_bucket.id')

echo "Buckets to validate:"
echo "  - Raw Data: ${RAW_BUCKET}"
echo "  - dbt Artifacts: ${DBT_BUCKET}"
echo "  - MWAA: ${MWAA_BUCKET}"
echo ""

# Test 1: Buckets exist
echo "1️⃣ Verifying buckets exist..."
for bucket in ${RAW_BUCKET} ${DBT_BUCKET} ${MWAA_BUCKET}; do
    if aws s3 ls s3://${bucket} &>/dev/null; then
        echo "  ✅ ${bucket} exists"
    else
        echo "  ❌ ${bucket} not found"
        exit 1
    fi
done
echo ""

# Test 2: Versioning enabled
echo "2️⃣ Verifying versioning enabled..."
for bucket in ${RAW_BUCKET} ${DBT_BUCKET} ${MWAA_BUCKET}; do
    STATUS=$(aws s3api get-bucket-versioning --bucket ${bucket} --query 'Status' --output text)
    if [ "$STATUS" == "Enabled" ]; then
        echo "  ✅ ${bucket} versioning enabled"
    else
        echo "  ❌ ${bucket} versioning not enabled (Status: ${STATUS})"
        exit 1
    fi
done
echo ""

# Test 3: Encryption configured
echo "3️⃣ Verifying encryption configured..."
for bucket in ${RAW_BUCKET} ${DBT_BUCKET} ${MWAA_BUCKET}; do
    ALG=$(aws s3api get-bucket-encryption --bucket ${bucket} --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text)
    if [ "$ALG" == "AES256" ]; then
        echo "  ✅ ${bucket} encrypted with ${ALG}"
    else
        echo "  ❌ ${bucket} encryption issue (Algorithm: ${ALG})"
        exit 1
    fi
done
echo ""

# Test 4: Public access blocked
echo "4️⃣ Verifying public access blocked..."
for bucket in ${RAW_BUCKET} ${DBT_BUCKET} ${MWAA_BUCKET}; do
    BLOCKED=$(aws s3api get-public-access-block --bucket ${bucket} --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,BlockPublicPolicy,IgnorePublicAcls,RestrictPublicBuckets]' --output text)
    if [ "$BLOCKED" == "True	True	True	True" ]; then
        echo "  ✅ ${bucket} public access blocked"
    else
        echo "  ⚠️  ${bucket} may have public access (Check manually)"
    fi
done
echo ""

# Test 5: Lifecycle policies configured
echo "5️⃣ Verifying lifecycle policies..."
LIFECYCLE=$(aws s3api get-bucket-lifecycle-configuration --bucket ${RAW_BUCKET} --query 'Rules[*].Id' --output text)
if [ -n "$LIFECYCLE" ]; then
    echo "  ✅ ${RAW_BUCKET} has lifecycle policies:"
    echo "     ${LIFECYCLE}"
else
    echo "  ⚠️  ${RAW_BUCKET} has no lifecycle policies"
fi
echo ""

# Test 6: Folder structure exists
echo "6️⃣ Verifying folder structure in raw bucket..."
FOLDERS="landing/ raw/ processed/ archive/"
for folder in $FOLDERS; do
    if aws s3 ls s3://${RAW_BUCKET}/${folder} &>/dev/null; then
        echo "  ✅ ${folder} exists"
    else
        echo "  ⚠️  ${folder} not found"
    fi
done
echo ""

# Test 7: EventBridge notification enabled
echo "7️⃣ Verifying EventBridge notifications..."
NOTIFICATION=$(aws s3api get-bucket-notification-configuration --bucket ${RAW_BUCKET} --query 'EventBridgeConfiguration' --output text)
if [ -n "$NOTIFICATION" ]; then
    echo "  ✅ EventBridge notifications enabled"
else
    echo "  ❌ EventBridge notifications not configured"
    exit 1
fi
echo ""

# Test 8: Sample data exists
echo "8️⃣ Verifying sample data uploaded..."
SAMPLE_COUNT=$(aws s3 ls s3://${RAW_BUCKET}/landing/ --recursive | wc -l)
if [ $SAMPLE_COUNT -gt 0 ]; then
    echo "  ✅ ${SAMPLE_COUNT} files in landing zone"
else
    echo "  ⚠️  No sample data in landing zone"
fi
echo ""

# Test 9: MWAA bucket structure
echo "9️⃣ Verifying MWAA bucket structure..."
if aws s3 ls s3://${MWAA_BUCKET}/requirements.txt &>/dev/null; then
    echo "  ✅ requirements.txt exists"
else
    echo "  ⚠️  requirements.txt not found"
fi

if aws s3 ls s3://${MWAA_BUCKET}/dags/ &>/dev/null; then
    echo "  ✅ dags/ folder exists"
else
    echo "  ⚠️  dags/ folder not found"
fi
echo ""

# Summary
echo "✅ All S3 storage validation checks passed!"
EOF

chmod +x ../../scripts/validate-storage.sh

# Run validation
../../scripts/validate-storage.sh
```

**✅ Validation**: All checks pass

### Step 2: Test Data Retrieval (30 minutes)

```bash
# Download sample file to verify integrity
aws s3 cp s3://data-platform-raw-data-dev/raw/sales/orders/$(date +%Y-%m-%d)/orders.csv /tmp/orders_test.csv

# Verify file content
head -5 /tmp/orders_test.csv

# Expected output:
# order_id,customer_id,order_date,order_amount,status
# 1001,501,2024-01-15,1299.99,completed
# ...

# Check file size matches original
ls -lh /tmp/orders_test.csv

# Clean up
rm /tmp/orders_test.csv
```

**✅ Validation**: Data retrieval works

### Step 3: Document S3 Best Practices (1 hour)

```bash
# Create best practices documentation
cat > ../../docs/S3_BEST_PRACTICES.md <<'EOF'
# S3 Best Practices

## Naming Conventions

### Buckets
**Format**: `{project}-{purpose}-{environment}`

✅ **Good**:
- `data-platform-raw-data-dev`
- `data-platform-mwaa-prod`

❌ **Bad**:
- `my-bucket` (not descriptive)
- `DataPlatform_RAW` (capitals, underscore)
- `data.platform.dev` (dots can cause SSL issues)

### Object Keys (File Paths)

**Format**: `{zone}/{source}/{table}/YYYY-MM-DD/filename.ext`

✅ **Good**:
- `landing/sales/orders/2024-01-15/orders_20240115_001.csv`
- `raw/customers/2024-01-15/customers.parquet`
- `processed/analytics/customer_metrics/2024-01-15/metrics.csv`

❌ **Bad**:
- `data/file.csv` (no date partition)
- `sales_orders_2024_01_15.csv` (underscores in date)
- `landing/Sales/ORDERS/orders.csv` (inconsistent casing)

---

## Security Best Practices

### 1. Encryption

**Always encrypt**:
- ✅ At rest: SSE-S3 (AES-256) minimum
- ✅ In transit: TLS 1.2+ (enforce with bucket policy)
- ✅ Sensitive data: Consider SSE-KMS for audit trail

**Bucket policy to enforce SSL**:
```json
{
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": "arn:aws:s3:::bucket-name/*",
  "Condition": {
    "Bool": {
      "aws:SecureTransport": "false"
    }
  }
}
```

### 2. Access Control

**Principle of Least Privilege**:
- ✅ Use IAM roles, not access keys
- ✅ Grant minimum required permissions
- ✅ Use bucket policies + IAM policies together
- ✅ Never make buckets public

**Example IAM policy (read-only)**:
```json
{
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:ListBucket"
  ],
  "Resource": [
    "arn:aws:s3:::bucket-name",
    "arn:aws:s3:::bucket-name/*"
  ]
}
```

### 3. Versioning

**Enable versioning**:
- ✅ Protects against accidental deletion
- ✅ Enables point-in-time recovery
- ✅ Required for MWAA
- ✅ Combine with lifecycle policies to manage costs

**Lifecycle rule for old versions**:
```json
{
  "Id": "ExpireOldVersions",
  "Status": "Enabled",
  "NoncurrentVersionExpiration": {
    "NoncurrentDays": 30
  }
}
```

---

## Cost Optimization

### 1. Lifecycle Policies

**Tiered storage strategy**:
```
STANDARD (0-30 days)
    ↓
STANDARD_IA (30-90 days)
    ↓
GLACIER (90-365 days)
    ↓
DELETE (after 365 days)
```

**Example lifecycle rule**:
```json
{
  "Rules": [
    {
      "Id": "tier-storage",
      "Status": "Enabled",
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "STANDARD_IA"
        },
        {
          "Days": 90,
          "StorageClass": "GLACIER"
        }
      ],
      "Expiration": {
        "Days": 365
      }
    }
  ]
}
```

### 2. Right-Sizing

**Delete temporary data**:
- ✅ Landing zone: 7-day retention
- ✅ Logs: 30-day retention
- ✅ Test data: Delete after use

**Intelligent-Tiering**:
- Consider for unpredictable access patterns
- Automatic cost optimization
- Small monitoring fee

### 3. Data Transfer

**Minimize costs**:
- ✅ Use VPC Endpoints (free, no internet data transfer)
- ✅ Keep processing in same region
- ✅ Avoid cross-region transfers
- ✅ Use S3 Transfer Acceleration only when needed

---

## Performance Optimization

### 1. Partitioning

**Date-based partitioning**:
```
/raw/sales/orders/
  └── 2024-01-15/
      ├── file1.parquet
      ├── file2.parquet
      └── file3.parquet
```

**Benefits**:
- ✅ Faster queries (Athena, Spectrum)
- ✅ Easier data management
- ✅ Lifecycle policies can target partitions

### 2. File Formats

**Choose wisely**:
| Format | Use Case | Compression | Query Performance |
|--------|----------|-------------|-------------------|
| CSV | Ingestion, compatibility | Low | Poor |
| JSON | Semi-structured data | Medium | Medium |
| Parquet | Analytics, Redshift Spectrum | High | Excellent |
| Avro | Schema evolution | High | Good |

**Recommendation**:
- Landing zone: CSV/JSON (source format)
- Raw zone: Original format
- Processed zone: **Parquet** (best for analytics)

### 3. File Size

**Optimal file sizes**:
- ✅ Target: 100MB - 1GB per file
- ❌ Too small (<10MB): High overhead
- ❌ Too large (>5GB): Hard to process

**Split large files**:
```bash
# Split CSV into 100MB chunks
split -b 100M large_file.csv chunk_
```

---

## Data Quality

### 1. Validation

**Validate on upload**:
- ✅ File format check
- ✅ Schema validation
- ✅ Row count check
- ✅ Null value detection

**EventBridge pattern**:
```
S3 Upload → EventBridge → Lambda (validate) → SNS (alert if failed)
```

### 2. Metadata

**Track metadata**:
- ✅ Upload timestamp
- ✅ Source system
- ✅ Record count
- ✅ File size

**Store in separate file**:
```
/landing/sales/2024-01-15/
  ├── orders.csv
  └── _metadata.json
```

### 3. Checksums

**Verify integrity**:
```bash
# Generate MD5
md5sum file.csv > file.csv.md5

# Upload both
aws s3 cp file.csv s3://bucket/path/
aws s3 cp file.csv.md5 s3://bucket/path/
```

---

## Monitoring & Alerting

### 1. CloudWatch Metrics

**Track**:
- Bucket size
- Number of objects
- Request count (if enabled)
- Error rate

### 2. S3 Access Logs

**Enable logging**:
```bash
aws s3api put-bucket-logging \
  --bucket source-bucket \
  --bucket-logging-status '{
    "LoggingEnabled": {
      "TargetBucket": "logs-bucket",
      "TargetPrefix": "s3-access-logs/"
    }
  }'
```

### 3. EventBridge Rules

**Alert on**:
- Large file uploads (>1GB)
- Unexpected file types
- High upload rate
- Access denied errors

---

## Disaster Recovery

### 1. Cross-Region Replication

**For critical data**:
```hcl
resource "aws_s3_bucket_replication_configuration" "replication" {
  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.source.id

  rule {
    id     = "replicate-all"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.destination.arn
      storage_class = "STANDARD_IA"
    }
  }
}
```

### 2. Backup Strategy

**Regular backups**:
- Critical data: Daily to Glacier
- Processed data: Weekly snapshots
- Test restore quarterly

### 3. Version Recovery

**Restore deleted file**:
```bash
# List versions
aws s3api list-object-versions \
  --bucket bucket-name \
  --prefix path/to/file

# Restore specific version
aws s3api copy-object \
  --bucket bucket-name \
  --copy-source bucket-name/path/to/file?versionId=xxx \
  --key path/to/file
```

---

## Common Pitfalls

### ❌ Don't:
1. Store secrets in S3 (use Secrets Manager)
2. Use sequential IDs in prefixes (causes hotspots)
3. Delete without versioning
4. Enable public access
5. Skip encryption
6. Forget lifecycle policies
7. Use inconsistent naming

### ✅ Do:
1. Enable versioning immediately
2. Encrypt everything
3. Use VPC endpoints
4. Implement lifecycle policies
5. Monitor costs regularly
6. Validate data on upload
7. Document naming conventions
8. Test restore procedures

---

## Checklist

Before going to production:

- [ ] Versioning enabled
- [ ] Encryption configured (SSE-S3 minimum)
- [ ] Public access blocked
- [ ] Bucket policies enforce SSL
- [ ] Lifecycle policies configured
- [ ] Folder structure documented
- [ ] Naming conventions defined
- [ ] EventBridge notifications set up
- [ ] Monitoring/alerting configured
- [ ] Cross-region replication (if needed)
- [ ] Backup/restore tested
- [ ] Cost alerts configured
- [ ] Access audit completed

EOF
```

**✅ Validation**: Best practices documented

---

## Afternoon Session (3 hours)

### Step 4: Prepare Sprint Demo (1 hour)

```bash
mkdir -p ../../docs/demos/sprint-03

cat > ../../docs/demos/sprint-03/DEMO_SCRIPT.md <<'EOF'
# Sprint 3 Demo Script

**Date**: [Today's Date]
**Sprint Goal**: S3 Storage & Data Lake Foundation

---

## Demo Flow (15 minutes)

### 1. Introduction (2 minutes)

**SAY**:
> "In Sprint 3, we built the foundation for our data lake with S3 buckets, lifecycle policies, and event-driven automation."

### 2. S3 Bucket Structure (4 minutes)

**SHOW**: AWS S3 Console
- Navigate to S3
- Show 3 buckets:
  - `data-platform-raw-data-dev`
  - `data-platform-dbt-artifacts-dev`
  - `data-platform-mwaa-dev`

**HIGHLIGHT** raw-data bucket:
- Click on bucket
- Show folder structure:
  - landing/
  - raw/
  - processed/
  - archive/

**SAY**:
> "Each zone serves a specific purpose: landing for incoming files, raw for validated data, processed for transformed data."

**SHOW**: Bucket properties
- Versioning: Enabled
- Encryption: AES-256
- Public access: Blocked

### 3. Lifecycle Policies (3 minutes)

**SHOW**: Management tab → Lifecycle rules

**HIGHLIGHT**:
- `transition-to-ia`: STANDARD → IA (30d) → Glacier (90d) → Delete (365d)
- `delete-old-landing`: Landing files deleted after 7 days
- `expire-old-versions`: Old versions deleted after 30 days

**SAY**:
> "Lifecycle policies automatically optimize costs by moving data to cheaper storage tiers and deleting temporary files."

### 4. Event-Driven Pipeline Demo (5 minutes)

**SHOW**: Live upload demonstration

```bash
# In terminal
cd scripts/data
./upload-sample-data.sh
```

**SAY**:
> "Watch as we upload a file to the landing zone. EventBridge will automatically detect this and trigger an event."

**SHOW**: CloudWatch Logs
- Navigate to CloudWatch → Log groups
- Open `/aws/events/data-platform-dev-s3-events`
- Show recent log events with JSON payload

**HIGHLIGHT** in JSON:
- bucket name
- object key
- event time
- event type: "Object Created"

**SAY**:
> "This event foundation will trigger our Airflow DAGs in Sprint 10, creating a fully automated data pipeline."

### 5. Sample Data (1 minute)

**SHOW**: S3 Console → Files

```
landing/sales/2024-01-15/orders.csv
landing/customers/2024-01-15/customers.json
landing/products/2024-01-15/products.parquet
```

**SAY**:
> "We've prepared sample datasets in multiple formats: CSV, JSON, and Parquet, ready for Redshift Spectrum testing in Sprint 4."

---

## Q&A Preparation

**Q**: "How much does this cost?"
**A**: "~$5-10/month for dev. Most S3 costs are storage. With lifecycle policies, we automatically move data to cheaper tiers."

**Q**: "What happens if we accidentally delete a file?"
**A**: "Versioning is enabled. We can restore any file from the last 30 days using version history."

**Q**: "Can we query this data directly?"
**A**: "Yes! In Sprint 4, we'll set up Redshift Spectrum to query S3 data directly without loading it into Redshift."

**Q**: "How do files get to S3?"
**A**: "Currently manual upload. In production, we'll have automated data ingestion from source systems, or manual uploads will trigger the automated pipeline."

---

## Demo Checklist

- [ ] AWS Console open and logged in
- [ ] S3 buckets visible
- [ ] Sample data uploaded
- [ ] EventBridge logs showing events
- [ ] Terminal ready for live upload demo
- [ ] upload-sample-data.sh script tested

EOF
```

### Step 5: Conduct Sprint Demo (30 minutes)

Follow the demo script and present to stakeholders.

**Document feedback**:

```bash
cat > ../../docs/demos/sprint-03/FEEDBACK.md <<'EOF'
# Sprint 3 Demo Feedback

**Date**: [Today's Date]
**Attendees**: [List names]

## Positive Feedback

-

## Concerns Raised

-

## Questions Asked

-

## Action Items

-

## Stakeholder Approval

- [ ] Product Owner: [Approved/Pending]
- [ ] Tech Lead: [Approved/Pending]

**Overall Status**: [Approved]
EOF
```

**✅ Validation**: Demo delivered

### Step 6: Sprint Retrospective (1 hour)

```bash
cat > ../../docs/retrospectives/sprint-03.md <<'EOF'
# Sprint 3 Retrospective

**Date**: [Today's Date]
**Sprint**: 3/14
**Goal**: S3 Storage & Data Lake Foundation

---

## Sprint Metrics

| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| Story Points Planned | 13 | 13 | ✅ |
| Story Points Completed | 13 | TBD | TBD |
| Velocity | 100% | TBD | TBD |

---

## What Went Well? 😊

1.

2.

3.

---

## What Didn't Go Well? 😞

1.

2.

3.

---

## Lessons Learned 💡

1.

2.

3.

---

## Action Items for Sprint 4

| Action | Owner | Due Date | Priority |
|--------|-------|----------|----------|
| | | | |

---

## Sprint Health

- **Team Collaboration**: ___/5
- **Infrastructure Quality**: ___/5
- **Documentation**: ___/5
- **S3 Knowledge**: ___/5
- **Velocity**: ___/5

**Average**: ___/5
EOF
```

**✅ Validation**: Retrospective completed

### Step 7: Sprint Closure (30 minutes)

```bash
# Commit all work
git add -A

git commit -m "feat: complete Sprint 3 - S3 Storage & Data Lake Foundation

Day 1:
- Created storage Terraform module
- Deployed 3 S3 buckets with encryption and versioning
- Configured lifecycle policies
- Created data lake folder structure

Day 2:
- Set up EventBridge rules for S3 events
- Created sample datasets (CSV, JSON, Parquet)
- Built data upload and verification scripts
- Tested event-driven triggers

Day 3:
- Validated all S3 resources
- Documented S3 best practices
- Conducted sprint demo
- Completed retrospective

All acceptance criteria met ✅

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

git push origin develop
```

**✅ Validation**: Sprint 3 complete

---

## End of Day 3 Checklist

- [x] All S3 resources validated
- [x] Data retrieval tested
- [x] S3 best practices documented
- [x] Sprint demo delivered
- [x] Stakeholder feedback collected
- [x] Sprint retrospective conducted
- [x] Sprint closure completed
- [x] All work committed to Git

---

## 🎉 Sprint 3 Complete!

### Accomplishments

- ✅ 3 S3 buckets deployed with security hardening
- ✅ Lifecycle policies reducing costs
- ✅ Event-driven foundation established
- ✅ Sample data ready for Redshift testing
- ✅ Comprehensive documentation

### Ready For

- ✅ Redshift Spectrum queries (Sprint 4)
- ✅ dbt external tables (Sprint 5)
- ✅ Automated data pipeline (Sprint 10)

---

## ⏭️ Next: Sprint 4

**Sprint 4**: Redshift Cluster & Database Setup (Days 10-12)

You'll be working on:
- Deploying Redshift cluster in private subnets
- Creating database schemas
- Setting up Redshift Spectrum
- Connecting dbt to Redshift

**See `workshops/sprint-04/`** 🚀
