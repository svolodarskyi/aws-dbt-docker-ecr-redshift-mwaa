# Sprint 10 - Day 1: EventBridge Integration Setup

**Goal**: Configure S3 events to trigger Airflow DAGs via EventBridge

**Duration**: ~6 hours

**Outcome**: EventBridge rules configured, IAM permissions set, integration tested

---

## Morning Session (3 hours)

### Step 1: Create EventBridge Terraform Module (1 hour 30 minutes)

```bash
cd terraform/modules
mkdir -p events
cd events

cat > main.tf <<'EOF'
# EventBridge Rule for S3 Uploads
resource "aws_cloudwatch_event_rule" "s3_landing_upload" {
  name        = "${var.project_name}-s3-landing-upload-${var.environment}"
  description = "Trigger when files uploaded to S3 landing zone"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [var.raw_data_bucket_name]
      }
      object = {
        key = [{
          prefix = "landing/"
        }]
      }
    }
  })

  tags = {
    Name = "${var.project_name}-s3-landing-upload-${var.environment}"
  }
}

# IAM Role for EventBridge to invoke MWAA
resource "aws_iam_role" "eventbridge_mwaa" {
  name = "${var.project_name}-eventbridge-mwaa-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_mwaa" {
  name = "invoke-mwaa"
  role = aws_iam_role.eventbridge_mwaa.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "airflow:CreateCliToken"
      ]
      Resource = var.mwaa_environment_arn
    }]
  })
}

# EventBridge Target - MWAA
resource "aws_cloudwatch_event_target" "mwaa" {
  rule      = aws_cloudwatch_event_rule.s3_landing_upload.name
  arn       = var.mwaa_environment_arn
  role_arn  = aws_iam_role.eventbridge_mwaa.arn

  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name"
      key    = "$.detail.object.key"
      size   = "$.detail.object.size"
    }
    input_template = jsonencode({
      dag_name = "data_ingestion_pipeline"
      conf = {
        s3_bucket = "<bucket>"
        s3_key    = "<key>"
        file_size = "<size>"
      }
    })
  }
}

# CloudWatch Log Group for EventBridge
resource "aws_cloudwatch_log_group" "eventbridge" {
  name              = "/aws/events/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days
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

variable "raw_data_bucket_name" {
  description = "Name of raw data S3 bucket"
  type        = string
}

variable "mwaa_environment_arn" {
  description = "ARN of MWAA environment"
  type        = string
}

variable "log_retention_days" {
  description = "Log retention in days"
  type        = number
  default     = 7
}
EOF

cat > outputs.tf <<'EOF'
output "event_rule_arn" {
  description = "ARN of EventBridge rule"
  value       = aws_cloudwatch_event_rule.s3_landing_upload.arn
}

output "eventbridge_role_arn" {
  description = "ARN of EventBridge IAM role"
  value       = aws_iam_role.eventbridge_mwaa.arn
}
EOF

terraform fmt -recursive ../../
```

### Step 2: Enable S3 Event Notifications (1 hour)

```bash
cd ../../modules/storage

# Add EventBridge notification to S3 bucket
cat >> main.tf <<'EOF'

# Enable EventBridge notifications on raw data bucket
resource "aws_s3_bucket_notification" "raw_data_events" {
  bucket      = aws_s3_bucket.raw_data.id
  eventbridge = true
}
EOF

terraform fmt main.tf
```

### Step 3: Apply EventBridge Configuration (30 minutes)

```bash
cd ../../environments/dev

cat > events.tf <<'EOF'
module "events" {
  source = "../../modules/events"

  project_name         = var.project_name
  environment          = var.environment
  raw_data_bucket_name = module.storage.raw_data_bucket_id
  mwaa_environment_arn = module.orchestration.mwaa_environment_arn
  log_retention_days   = 7
}

output "events" {
  value = {
    event_rule_arn       = module.events.event_rule_arn
    eventbridge_role_arn = module.events.eventbridge_role_arn
  }
}
EOF

terraform init
terraform apply -target=module.storage  # Update S3 notification
terraform apply -target=module.events   # Create EventBridge rule
```

---

## Afternoon Session (3 hours)

### Step 4: Test EventBridge Rule (1 hour)

```bash
# Upload test file to trigger event
aws s3 cp /tmp/test-file.csv s3://data-platform-raw-data-dev/landing/test-file.csv

# Check EventBridge metrics
aws events describe-rule --name data-platform-s3-landing-upload-dev

# View CloudWatch Events
aws logs tail /aws/events/data-platform-dev --follow

# Check if event was captured
aws events test-event-pattern \
  --event-pattern file://event-pattern.json \
  --event file://sample-event.json
```

### Step 5: Create Event Testing Script (1 hour)

```bash
cd ../../../../scripts

mkdir -p events

cat > events/test-s3-event.sh <<'EOF'
#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}
TEST_FILE=${2:-/tmp/test-data.csv}

echo "🧪 Testing S3 EventBridge integration..."

# Create test file if doesn't exist
if [ ! -f "$TEST_FILE" ]; then
  echo "customer_id,name,email" > $TEST_FILE
  echo "1,Test User,test@example.com" >> $TEST_FILE
fi

# Get bucket name
BUCKET=$(aws s3 ls | grep raw-data-$ENVIRONMENT | awk '{print $3}')

if [ -z "$BUCKET" ]; then
  echo "❌ Bucket not found"
  exit 1
fi

# Upload file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
S3_KEY="landing/test_${TIMESTAMP}.csv"

echo "📤 Uploading to s3://${BUCKET}/${S3_KEY}"
aws s3 cp $TEST_FILE s3://${BUCKET}/${S3_KEY}

echo "✅ File uploaded"
echo ""
echo "🔍 Check EventBridge:"
echo "  aws events describe-rule --name data-platform-s3-landing-upload-${ENVIRONMENT}"
echo ""
echo "🔍 Check if DAG triggered:"
echo "  # Open Airflow UI and check data_ingestion_pipeline DAG runs"
EOF

chmod +x events/test-s3-event.sh
```

### Step 6: Create Documentation (1 hour)

```bash
cd ../docs

cat > EVENT_DRIVEN_ARCHITECTURE.md <<'EOF'
# Event-Driven Data Pipeline Architecture

## Overview

S3 file uploads automatically trigger data processing pipelines via EventBridge.

```
S3 Upload → EventBridge → MWAA → Airflow DAG → ECS Task → dbt → Redshift
```

---

## Components

### 1. S3 Event Source

**Bucket**: `data-platform-raw-data-dev`
**Path**: `landing/*`
**Events**: Object Created (PUT, POST, COPY)

**EventBridge enabled**: S3 bucket configured to send events to EventBridge

### 2. EventBridge Rule

**Rule**: `data-platform-s3-landing-upload-dev`
**Event Pattern**:
```json
{
  "source": ["aws.s3"],
  "detail-type": ["Object Created"],
  "detail": {
    "bucket": {"name": ["data-platform-raw-data-dev"]},
    "object": {"key": [{"prefix": "landing/"}]}
  }
}
```

### 3. EventBridge Target

**Target**: MWAA Environment
**DAG**: `data_ingestion_pipeline`
**Parameters**:
- `s3_bucket`: Source bucket name
- `s3_key`: Object key
- `file_size`: File size in bytes

---

## Event Flow

1. **File Upload**: User/system uploads file to `s3://bucket/landing/`
2. **S3 Event**: S3 emits Object Created event to EventBridge
3. **Rule Match**: EventBridge rule matches event pattern
4. **DAG Trigger**: EventBridge invokes MWAA with DAG configuration
5. **Processing**: Airflow DAG processes file via ECS/dbt
6. **Validation**: Data validated and moved to `/raw/`
7. **Archive**: Original file moved to `/archive/`

---

## Testing

### Manual Test

```bash
# Upload test file
./scripts/events/test-s3-event.sh dev

# Check Airflow UI for triggered DAG run
```

### Automated Test

```bash
# Simulate S3 event
aws events put-events --entries file://test-event.json
```

---

## Monitoring

### CloudWatch Logs

```bash
# EventBridge logs
aws logs tail /aws/events/data-platform-dev --follow

# Check triggered DAG
# (In Airflow UI: DAGs → data_ingestion_pipeline → Runs)
```

### Metrics

- Event rule invocation count
- DAG trigger success/failure
- File processing duration

---

## Troubleshooting

**DAG not triggering**:
1. Check EventBridge rule is enabled
2. Verify MWAA ARN in target
3. Check IAM role permissions
4. Review EventBridge logs

**Wrong DAG triggered**:
1. Verify event pattern matching
2. Check input transformer configuration

**Permission denied**:
1. EventBridge role needs `airflow:CreateCliToken`
2. MWAA execution role needs DAG permissions
EOF
```

---

## End of Day 1 Checklist

- [x] EventBridge Terraform module created
- [x] S3 event notifications enabled
- [x] EventBridge rule configured
- [x] IAM roles created
- [x] Configuration applied
- [x] Event testing script created
- [x] Documentation created

---

## 📝 Daily Standup Notes

**Completed Today**:
- EventBridge module with S3 event rule
- S3 bucket EventBridge notifications
- IAM role for EventBridge→MWAA
- Event testing infrastructure
- Event-driven architecture documentation

**Blockers**:
- None

**Tomorrow's Plan**:
- Create parameterized Airflow DAG
- Test end-to-end event flow
- Add error handling

---

## 🎯 Success Metrics

```bash
# EventBridge rule exists
aws events describe-rule --name data-platform-s3-landing-upload-dev

# S3 notifications enabled
aws s3api get-bucket-notification-configuration \
  --bucket data-platform-raw-data-dev \
  | grep EventBridgeConfiguration

# IAM role exists
aws iam get-role --role-name data-platform-eventbridge-mwaa-dev
```

---

## ⏭️ Next: Day 2

Tomorrow: Create parameterized DAG, test event flow, add validation

**See [day-2.md](./day-2.md)** 🚀
