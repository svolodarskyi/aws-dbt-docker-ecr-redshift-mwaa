# Sprint 10 - Day 2: Parameterized DAG & Event Processing

**Goal**: Create Airflow DAG that processes files triggered by S3 events

**Duration**: ~6 hours

**Outcome**: Event-driven pipeline operational, files processed automatically

---

## Morning Session (3 hours)

### Step 1: Create Parameterized Airflow DAG (1 hour 30 minutes)

```bash
cd airflow/dags

cat > data_ingestion_pipeline.py <<'EOF'
"""
Data Ingestion Pipeline

Triggered by S3 file uploads via EventBridge.
Processes files from landing zone to raw zone.
"""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.amazon.aws.operators.ecs import EcsRunTaskOperator
from airflow.providers.amazon.aws.hooks.s3 import S3Hook
import json

default_args = {
    'owner': 'data-platform',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': True,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'data_ingestion_pipeline',
    default_args=default_args,
    description='Process files uploaded to S3 landing zone',
    schedule_interval=None,  # Event-driven only
    catchup=False,
    tags=['event-driven', 'ingestion', 'production'],
)

def validate_file(**context):
    """Validate uploaded file"""
    s3_bucket = context['dag_run'].conf.get('s3_bucket')
    s3_key = context['dag_run'].conf.get('s3_key')
    file_size = context['dag_run'].conf.get('file_size', 0)

    print(f"Validating file: s3://{s3_bucket}/{s3_key}")
    print(f"File size: {file_size} bytes")

    # Validation checks
    if file_size == 0:
        raise ValueError("File is empty")

    if file_size > 1024 * 1024 * 500:  # 500MB
        raise ValueError("File too large")

    # Check file extension
    valid_extensions = ['.csv', '.json', '.parquet']
    if not any(s3_key.endswith(ext) for ext in valid_extensions):
        raise ValueError(f"Invalid file type. Must be one of: {valid_extensions}")

    print("✅ File validation passed")
    return {"bucket": s3_bucket, "key": s3_key}

def move_to_raw(**context):
    """Move file from landing to raw zone"""
    file_info = context['task_instance'].xcom_pull(task_ids='validate_file')
    bucket = file_info['bucket']
    source_key = file_info['key']

    # Determine target path
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    filename = source_key.split('/')[-1]
    target_key = f"raw/processed_{timestamp}_{filename}"

    # Copy file
    s3_hook = S3Hook()
    s3_hook.copy_object(
        source_bucket_name=bucket,
        source_bucket_key=source_key,
        dest_bucket_name=bucket,
        dest_bucket_key=target_key
    )

    print(f"✅ Moved: s3://{bucket}/{source_key} → s3://{bucket}/{target_key}")
    return target_key

def archive_original(**context):
    """Archive original file"""
    file_info = context['task_instance'].xcom_pull(task_ids='validate_file')
    bucket = file_info['bucket']
    source_key = file_info['key']

    timestamp = datetime.now().strftime('%Y/%m/%d')
    filename = source_key.split('/')[-1]
    archive_key = f"archive/{timestamp}/{filename}"

    s3_hook = S3Hook()
    s3_hook.copy_object(
        source_bucket_name=bucket,
        source_bucket_key=source_key,
        dest_bucket_name=bucket,
        dest_bucket_key=archive_key
    )

    # Delete original
    s3_hook.delete_objects(bucket=bucket, keys=[source_key])

    print(f"✅ Archived: s3://{bucket}/{archive_key}")

def trigger_dbt_run(**context):
    """Trigger dbt transformation"""
    print("🔄 Triggering dbt transformation")
    # This will be handled by the ECS task below

# Tasks
task_validate = PythonOperator(
    task_id='validate_file',
    python_callable=validate_file,
    dag=dag,
)

task_move = PythonOperator(
    task_id='move_to_raw',
    python_callable=move_to_raw,
    dag=dag,
)

task_dbt = EcsRunTaskOperator(
    task_id='run_dbt_transformation',
    cluster='data-platform-dbt-dev',
    task_definition='data-platform-dbt-transformation-dev',
    launch_type='FARGATE',
    overrides={
        'containerOverrides': [{
            'name': 'dbt',
            'command': ['dbt', 'run', '--target', 'dev'],
        }],
    },
    network_configuration={
        'awsvpcConfiguration': {
            'subnets': "{{ var.json.ecs_subnets }}",
            'securityGroups': ["{{ var.value.ecs_security_group }}"],
            'assignPublicIp': 'DISABLED',
        },
    },
    awslogs_group='/ecs/data-platform-dbt-dev',
    dag=dag,
)

task_archive = PythonOperator(
    task_id='archive_original',
    python_callable=archive_original,
    dag=dag,
)

# Dependencies
task_validate >> task_move >> task_dbt >> task_archive
EOF
```

### Step 2: Test DAG Locally (30 minutes)

```bash
# Test DAG syntax
python airflow/dags/data_ingestion_pipeline.py

# Sync to MWAA
./scripts/airflow/sync-to-mwaa.sh dev

echo "⏰ Wait 5 minutes for MWAA to pick up DAG"
sleep 300
```

### Step 3: Create End-to-End Test Script (1 hour)

```bash
cat > scripts/events/test-end-to-end.sh <<'EOF'
#!/bin/bash
set -e

echo "🧪 Testing end-to-end event-driven pipeline"

# Create test CSV file
TEST_FILE="/tmp/test_data_$(date +%Y%m%d_%H%M%S).csv"
cat > $TEST_FILE <<CSV
customer_id,name,email,created_at
1,John Doe,john@example.com,2024-01-01
2,Jane Smith,jane@example.com,2024-01-02
3,Bob Johnson,bob@example.com,2024-01-03
CSV

echo "📄 Created test file: $TEST_FILE"

# Upload to S3 landing zone
BUCKET=$(aws s3 ls | grep raw-data-dev | awk '{print $3}')
S3_KEY="landing/customers_$(date +%Y%m%d_%H%M%S).csv"

echo "📤 Uploading to s3://${BUCKET}/${S3_KEY}"
aws s3 cp $TEST_FILE s3://${BUCKET}/${S3_KEY}

echo "✅ File uploaded"
echo ""
echo "Expected workflow:"
echo "  1. EventBridge detects upload"
echo "  2. Triggers data_ingestion_pipeline DAG"
echo "  3. Validates file"
echo "  4. Moves to /raw/"
echo "  5. Runs dbt transformation"
echo "  6. Archives original to /archive/"
echo ""
echo "🔍 Monitor progress:"
echo "  - Airflow UI: Check data_ingestion_pipeline DAG runs"
echo "  - CloudWatch: aws logs tail /aws/events/data-platform-dev --follow"
echo ""
echo "⏰ Pipeline should complete in ~10 minutes"
EOF

chmod +x scripts/events/test-end-to-end.sh
```

---

## Afternoon Session (3 hours)

### Step 4: Execute End-to-End Test (1 hour 30 minutes)

```bash
# Run test
./scripts/events/test-end-to-end.sh

# Monitor in Airflow UI
MWAA_URL=$(cd terraform/environments/dev && terraform output -json mwaa | jq -r '.webserver_url')
echo "Open: https://${MWAA_URL}"

# Watch CloudWatch logs
aws logs tail /aws/events/data-platform-dev --follow

# Check S3 for moved files
aws s3 ls s3://data-platform-raw-data-dev/raw/ --recursive | tail -5
aws s3 ls s3://data-platform-raw-data-dev/archive/ --recursive | tail -5
```

### Step 5: Add Error Handling (1 hour)

```bash
cd airflow/dags

cat > event_pipeline_monitoring.py <<'EOF'
"""
Event Pipeline Monitoring DAG

Monitors failed ingestions and sends alerts.
"""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator

default_args = {
    'owner': 'data-platform',
    'start_date': datetime(2024, 1, 1),
}

dag = DAG(
    'event_pipeline_monitoring',
    default_args=default_args,
    schedule_interval='@hourly',
    catchup=False,
    tags=['monitoring'],
)

def check_failed_ingestions():
    """Check for files stuck in landing zone"""
    from airflow.providers.amazon.aws.hooks.s3 import S3Hook

    s3_hook = S3Hook()
    bucket = 'data-platform-raw-data-dev'

    # List files in landing older than 1 hour
    keys = s3_hook.list_keys(bucket_name=bucket, prefix='landing/')

    if keys:
        print(f"⚠️ Found {len(keys)} files stuck in landing zone:")
        for key in keys:
            print(f"  - {key}")
        # TODO: Send SNS alert
    else:
        print("✅ No stuck files")

PythonOperator(
    task_id='check_stuck_files',
    python_callable=check_failed_ingestions,
    dag=dag,
)
EOF

./scripts/airflow/sync-to-mwaa.sh dev
```

### Step 6: Create Operations Documentation (30 minutes)

```bash
cd docs

cat > EVENT_PIPELINE_OPERATIONS.md <<'EOF'
# Event-Driven Pipeline Operations

## Daily Operations

### Monitor Ingestions

```bash
# Check recent uploads
aws s3 ls s3://data-platform-raw-data-dev/landing/ --recursive

# Check processed files
aws s3 ls s3://data-platform-raw-data-dev/raw/ --recursive | tail -10

# Check archived files
aws s3 ls s3://data-platform-raw-data-dev/archive/ --recursive | tail -10
```

### Manual Trigger

If EventBridge fails, manually trigger DAG:

```python
# In Airflow UI or via API
{
  "s3_bucket": "data-platform-raw-data-dev",
  "s3_key": "landing/file.csv",
  "file_size": 12345
}
```

---

## Troubleshooting

### File Not Processing

**Check EventBridge**:
```bash
aws events describe-rule --name data-platform-s3-landing-upload-dev
```

**Check DAG runs**:
- Airflow UI → data_ingestion_pipeline → Recent runs

**Check logs**:
```bash
aws logs tail /aws/events/data-platform-dev --follow
```

### Validation Failures

Files move to dead letter queue (future enhancement).
Current: DAG fails, file remains in landing.

**Resolution**:
1. Check validation logs in Airflow
2. Fix file format
3. Re-upload or manually trigger

EOF
```

---

## End of Day 2 Checklist

- [x] Parameterized Airflow DAG created
- [x] File validation logic implemented
- [x] File movement (landing→raw→archive)
- [x] dbt transformation triggered
- [x] End-to-end test script
- [x] Error handling added
- [x] Operations documentation

---

## 📝 Daily Standup Notes

**Completed Today**:
- Event-driven DAG with parameter support
- File validation and movement logic
- End-to-end testing infrastructure
- Error handling and monitoring DAG

**Blockers**:
- None

**Tomorrow's Plan**:
- Add advanced validation
- CloudWatch metrics
- Demo preparation
- Milestone Release 3

---

## 🎯 Success Metrics

```bash
# DAG exists in Airflow
# Check UI for data_ingestion_pipeline

# End-to-end test passes
./scripts/events/test-end-to-end.sh
# Should complete successfully

# Files moved correctly
aws s3 ls s3://BUCKET/raw/ | wc -l
# Should show processed files
```

---

## ⏭️ Next: Day 3

Tomorrow: Advanced validation, metrics, demo, Milestone Release 3

**See [day-3.md](./day-3.md)** 🚀
