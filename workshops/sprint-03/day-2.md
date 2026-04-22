# Sprint 3 - Day 2: EventBridge Integration & Sample Data

**Goal**: Configure S3 event notifications and prepare sample datasets

**Duration**: ~6 hours

**Outcome**: EventBridge rules active, sample data ready for testing

---

## Morning Session (3 hours)

### Step 1: Create EventBridge Terraform Module (1 hour 30 minutes)

```bash
cd terraform/modules

mkdir -p events

cd events

cat > main.tf <<'EOF'
# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------
# EventBridge Rule: S3 Object Created in Landing Zone
# ---------------------------------------------------------

resource "aws_cloudwatch_event_rule" "s3_landing_upload" {
  name        = "${var.project_name}-${var.environment}-s3-landing-upload"
  description = "Trigger when object uploaded to S3 landing zone"

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
    Name = "${var.project_name}-${var.environment}-s3-landing-upload"
  }
}

# ---------------------------------------------------------
# EventBridge Target: CloudWatch Log Group (for now)
# Note: Will add MWAA target in Sprint 10
# ---------------------------------------------------------

resource "aws_cloudwatch_log_group" "s3_events" {
  name              = "/aws/events/${var.project_name}-${var.environment}-s3-events"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-s3-events"
  }
}

resource "aws_cloudwatch_event_target" "log_s3_events" {
  rule      = aws_cloudwatch_event_rule.s3_landing_upload.name
  target_id = "send-to-cloudwatch-logs"
  arn       = aws_cloudwatch_log_group.s3_events.arn
}

# IAM role for EventBridge to write to CloudWatch Logs
resource "aws_iam_role" "eventbridge_logs" {
  name = "${var.project_name}-${var.environment}-eventbridge-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-eventbridge-logs-role"
  }
}

resource "aws_iam_role_policy" "eventbridge_logs" {
  name = "cloudwatch-logs-policy"
  role = aws_iam_role.eventbridge_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.s3_events.arn}:*"
      }
    ]
  })
}

# Resource policy for CloudWatch Logs
resource "aws_cloudwatch_log_resource_policy" "eventbridge" {
  policy_name = "${var.project_name}-${var.environment}-eventbridge-logs-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "events.amazonaws.com",
            "delivery.logs.amazonaws.com"
          ]
        }
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.s3_events.arn}:*"
      }
    ]
  })
}

# ---------------------------------------------------------
# Enable EventBridge Notifications on S3 Bucket
# ---------------------------------------------------------

resource "aws_s3_bucket_notification" "raw_data_events" {
  bucket      = var.raw_data_bucket_id
  eventbridge = true
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
  description = "Raw data S3 bucket name"
  type        = string
}

variable "raw_data_bucket_id" {
  description = "Raw data S3 bucket ID"
  type        = string
}
EOF

cat > outputs.tf <<'EOF'
output "s3_landing_upload_rule_arn" {
  description = "ARN of S3 landing upload EventBridge rule"
  value       = aws_cloudwatch_event_rule.s3_landing_upload.arn
}

output "s3_events_log_group_name" {
  description = "CloudWatch log group for S3 events"
  value       = aws_cloudwatch_log_group.s3_events.name
}
EOF
```

**✅ Validation**: Events module created

### Step 2: Reference Events Module in Environment (30 minutes)

```bash
cd ../../environments/dev

cat > events.tf <<'EOF'
module "events" {
  source = "../../modules/events"

  project_name          = var.project_name
  environment           = var.environment
  raw_data_bucket_name  = module.storage.raw_data_bucket.id
  raw_data_bucket_id    = module.storage.raw_data_bucket.id
}

output "events" {
  value = {
    s3_landing_upload_rule_arn = module.events.s3_landing_upload_rule_arn
    s3_events_log_group_name   = module.events.s3_events_log_group_name
  }
}
EOF

# Format and validate
terraform fmt -recursive ../../
terraform validate

# Create plan
terraform plan

# Expected: EventBridge rule, CloudWatch log group, IAM resources
```

**✅ Validation**: Plan shows event resources

### Step 3: Deploy EventBridge Configuration (1 hour)

```bash
# Apply Terraform
terraform apply

# Type 'yes' when prompted

# Verify EventBridge rule created
aws events list-rules | grep s3-landing-upload

# Verify S3 bucket notification
aws s3api get-bucket-notification-configuration \
  --bucket data-platform-raw-data-dev

# Expected output should show:
# "EventBridgeConfiguration": {}
```

**✅ Validation**: EventBridge rule active

---

## Afternoon Session (3 hours)

### Step 4: Prepare Sample Datasets (1 hour 30 minutes)

```bash
# Create sample data directory
mkdir -p ../../sample-data

cd ../../sample-data

# Create sample CSV data (sales orders)
cat > orders.csv <<'EOF'
order_id,customer_id,order_date,order_amount,status
1001,501,2024-01-15,1299.99,completed
1002,502,2024-01-15,450.50,completed
1003,503,2024-01-15,899.99,processing
1004,501,2024-01-16,2499.00,completed
1005,504,2024-01-16,125.75,pending
1006,505,2024-01-16,650.00,completed
1007,502,2024-01-17,1850.25,completed
1008,506,2024-01-17,399.99,processing
1009,503,2024-01-18,775.50,completed
1010,507,2024-01-18,1100.00,completed
EOF

# Create sample JSON data (customers)
cat > customers.json <<'EOF'
[
  {
    "customer_id": 501,
    "customer_name": "Acme Corporation",
    "email": "contact@acme.com",
    "created_date": "2023-06-01",
    "country": "USA"
  },
  {
    "customer_id": 502,
    "customer_name": "Tech Solutions Inc",
    "email": "info@techsol.com",
    "created_date": "2023-07-15",
    "country": "USA"
  },
  {
    "customer_id": 503,
    "customer_name": "Global Trade Ltd",
    "email": "sales@globaltrade.co.uk",
    "created_date": "2023-08-22",
    "country": "UK"
  },
  {
    "customer_id": 504,
    "customer_name": "Innovate Labs",
    "email": "hello@innovatelabs.io",
    "created_date": "2023-09-10",
    "country": "Canada"
  },
  {
    "customer_id": 505,
    "customer_name": "Data Dynamics",
    "email": "info@datadynamics.com",
    "created_date": "2023-10-05",
    "country": "USA"
  },
  {
    "customer_id": 506,
    "customer_name": "Cloud First Co",
    "email": "contact@cloudfirst.io",
    "created_date": "2023-11-12",
    "country": "Australia"
  },
  {
    "customer_id": 507,
    "customer_name": "Enterprise Systems",
    "email": "sales@entsys.de",
    "created_date": "2023-12-01",
    "country": "Germany"
  }
]
EOF

# Create sample Parquet data (products) using Python
cat > create_products_parquet.py <<'EOF'
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

# Sample products data
data = {
    'product_id': [201, 202, 203, 204, 205],
    'product_name': ['Laptop Pro', 'Wireless Mouse', 'USB-C Hub', 'Monitor 27"', 'Keyboard Mechanical'],
    'category': ['Computers', 'Accessories', 'Accessories', 'Monitors', 'Accessories'],
    'unit_price': [1299.99, 29.99, 79.99, 449.99, 159.99],
    'stock_quantity': [150, 500, 300, 75, 200]
}

df = pd.DataFrame(data)

# Write to Parquet
df.to_parquet('products.parquet', engine='pyarrow', compression='snappy')

print("✅ products.parquet created")
print(df)
EOF

# Install required packages (if not already installed)
pip install pandas pyarrow

# Generate Parquet file
python create_products_parquet.py

# Verify files created
ls -lh

# Expected:
# orders.csv
# customers.json
# products.parquet
```

**✅ Validation**: Sample datasets created

### Step 5: Create Data Upload Script (1 hour)

```bash
cd ../scripts/data

cat > upload-sample-data.sh <<'EOF'
#!/bin/bash
set -e

# Configuration
BUCKET=${1:-data-platform-raw-data-dev}
DATE=$(date +%Y-%m-%d)
SAMPLE_DATA_DIR="../../sample-data"

echo "📤 Uploading sample data to S3..."
echo "Bucket: ${BUCKET}"
echo "Date: ${DATE}"
echo ""

# Function to upload file and trigger event
upload_file() {
    local source=$1
    local destination=$2

    echo "Uploading: ${source} → s3://${BUCKET}/${destination}"
    aws s3 cp ${source} s3://${BUCKET}/${destination}
    echo "✅ Uploaded"
    echo ""
}

# Upload CSV to landing zone (will trigger EventBridge)
upload_file \
    "${SAMPLE_DATA_DIR}/orders.csv" \
    "landing/sales/${DATE}/orders.csv"

# Upload JSON to landing zone
upload_file \
    "${SAMPLE_DATA_DIR}/customers.json" \
    "landing/customers/${DATE}/customers.json"

# Upload Parquet to landing zone
upload_file \
    "${SAMPLE_DATA_DIR}/products.parquet" \
    "landing/products/${DATE}/products.parquet"

# Also upload to raw zone for Spectrum testing
echo "📦 Copying validated data to raw zone..."

upload_file \
    "${SAMPLE_DATA_DIR}/orders.csv" \
    "raw/sales/orders/${DATE}/orders.csv"

upload_file \
    "${SAMPLE_DATA_DIR}/customers.json" \
    "raw/customers/${DATE}/customers.json"

upload_file \
    "${SAMPLE_DATA_DIR}/products.parquet" \
    "raw/products/${DATE}/products.parquet"

echo "✅ All sample data uploaded!"
echo ""
echo "📊 Verify uploads:"
echo "aws s3 ls s3://${BUCKET}/landing/ --recursive"
echo "aws s3 ls s3://${BUCKET}/raw/ --recursive"
EOF

chmod +x upload-sample-data.sh

# Create verification script
cat > verify-s3-events.sh <<'EOF'
#!/bin/bash
set -e

LOG_GROUP="/aws/events/data-platform-dev-s3-events"

echo "🔍 Checking EventBridge logs for S3 events..."
echo "Log Group: ${LOG_GROUP}"
echo ""

# Wait a few seconds for events to arrive
echo "Waiting 10 seconds for events to propagate..."
sleep 10

# Get recent log streams
STREAMS=$(aws logs describe-log-streams \
    --log-group-name ${LOG_GROUP} \
    --order-by LastEventTime \
    --descending \
    --max-items 5 \
    --query 'logStreams[*].logStreamName' \
    --output text)

if [ -z "$STREAMS" ]; then
    echo "⚠️  No log streams found yet. Events may not have triggered."
    echo "Try uploading a file to landing/ and check again."
    exit 1
fi

# Get logs from most recent stream
LATEST_STREAM=$(echo $STREAMS | awk '{print $1}')
echo "Reading from stream: ${LATEST_STREAM}"
echo ""

aws logs get-log-events \
    --log-group-name ${LOG_GROUP} \
    --log-stream-name ${LATEST_STREAM} \
    --limit 10 \
    | jq '.events[].message | fromjson'

echo ""
echo "✅ EventBridge events captured!"
EOF

chmod +x verify-s3-events.sh
```

**✅ Validation**: Upload scripts created

### Step 6: Test Event-Driven Pipeline (30 minutes)

```bash
# Upload sample data (this will trigger EventBridge)
./upload-sample-data.sh

# Expected output:
# Uploading: orders.csv → s3://data-platform-raw-data-dev/landing/sales/...
# ✅ Uploaded
# ...

# Wait for events to propagate (10 seconds)
sleep 10

# Verify EventBridge captured the events
./verify-s3-events.sh

# Expected: Should show JSON event data with:
# - bucket name
# - object key
# - event time
# - event type (Object Created)

# Verify files in S3
aws s3 ls s3://data-platform-raw-data-dev/landing/ --recursive
aws s3 ls s3://data-platform-raw-data-dev/raw/ --recursive

# Count uploaded files
echo "Files in landing zone:"
aws s3 ls s3://data-platform-raw-data-dev/landing/ --recursive | wc -l

echo "Files in raw zone:"
aws s3 ls s3://data-platform-raw-data-dev/raw/ --recursive | wc -l

# Expected: 3 files in each zone
```

**✅ Validation**: Events triggered and logged

---

## End of Day 2 Checklist

- [x] EventBridge Terraform module created
- [x] EventBridge rule deployed for S3 events
- [x] S3 bucket notification configured
- [x] CloudWatch log group receiving events
- [x] Sample datasets created (CSV, JSON, Parquet)
- [x] Data upload script created
- [x] Event verification script created
- [x] Sample data uploaded successfully
- [x] EventBridge events verified in logs

---

## 📝 Daily Standup Notes

**Completed Today**:
- Created EventBridge rules for S3 object creation
- Configured S3 event notifications
- Created sample datasets (CSV, JSON, Parquet)
- Built data upload scripts
- Tested event-driven triggers successfully

**Blockers**:
- None

**Tomorrow's Plan**:
- Validate all S3 resources
- Document S3 bucket structure and naming conventions
- Prepare sprint demo
- Conduct retrospective

---

## 🎯 Success Metric

**You're successful if**:

```bash
# EventBridge rule exists
aws events list-rules | grep s3-landing-upload
# Should show the rule

# S3 notification enabled
aws s3api get-bucket-notification-configuration --bucket data-platform-raw-data-dev
# Should show EventBridgeConfiguration

# Sample data uploaded
aws s3 ls s3://data-platform-raw-data-dev/landing/sales/ --recursive
# Should show orders.csv

# Events captured in logs
aws logs tail /aws/events/data-platform-dev-s3-events --since 1h
# Should show event JSON
```

---

## ⏭️ Next: Day 3

Tomorrow you'll:
- Validate all deployed resources
- Document S3 naming conventions
- Prepare and deliver sprint demo
- Conduct sprint retrospective

**See [day-3.md](./day-3.md)** 🚀
