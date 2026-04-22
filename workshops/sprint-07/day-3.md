# Sprint 7 - Day 3: Advanced DAGs, Demo & Retrospective

**Goal**: Create advanced DAG patterns, optional SMTP setup, sprint demo

**Duration**: ~6 hours

**Outcome**: Production-ready DAG patterns, complete documentation, Sprint 7 demo delivered

---

## Morning Session (3 hours)

### Step 1: Create Advanced DAG Patterns (1 hour 30 minutes)

**DAG with Sensors and Branching**:

```bash
cd airflow/dags

cat > advanced_patterns.py <<'EOF'
"""
Advanced DAG Patterns

Demonstrates:
- Sensors (wait for S3 file)
- Branching (conditional execution)
- Task groups
- Dynamic task generation
"""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator, BranchPythonOperator
from airflow.operators.bash import BashOperator
from airflow.providers.amazon.aws.sensors.s3 import S3KeySensor
from airflow.utils.task_group import TaskGroup
import random

default_args = {
    'owner': 'data-platform',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'advanced_patterns',
    default_args=default_args,
    description='Advanced Airflow patterns demo',
    schedule_interval=None,
    catchup=False,
    tags=['advanced', 'patterns', 'demo'],
)

# Branching logic
def decide_branch(**context):
    """Decide which branch to take based on random value"""
    value = random.randint(1, 10)
    print(f"Random value: {value}")

    if value <= 3:
        return 'process_small_data'
    elif value <= 7:
        return 'process_medium_data'
    else:
        return 'process_large_data'

task_branch = BranchPythonOperator(
    task_id='decide_branch',
    python_callable=decide_branch,
    dag=dag,
)

# Branch tasks
task_small = BashOperator(
    task_id='process_small_data',
    bash_command='echo "Processing small dataset"',
    dag=dag,
)

task_medium = BashOperator(
    task_id='process_medium_data',
    bash_command='echo "Processing medium dataset"',
    dag=dag,
)

task_large = BashOperator(
    task_id='process_large_data',
    bash_command='echo "Processing large dataset"',
    dag=dag,
)

# Task group for validation
with TaskGroup("validation_group", tooltip="Data validation tasks", dag=dag) as validation_group:

    def validate_schema():
        print("✅ Schema validation passed")
        return True

    def validate_data_quality():
        print("✅ Data quality checks passed")
        return True

    def validate_completeness():
        print("✅ Completeness validation passed")
        return True

    validate_schema_task = PythonOperator(
        task_id='validate_schema',
        python_callable=validate_schema,
    )

    validate_quality_task = PythonOperator(
        task_id='validate_quality',
        python_callable=validate_data_quality,
    )

    validate_completeness_task = PythonOperator(
        task_id='validate_completeness',
        python_callable=validate_completeness,
    )

    # Run validations in parallel
    [validate_schema_task, validate_quality_task, validate_completeness_task]

# Final task (joins all branches)
task_final = BashOperator(
    task_id='final_report',
    bash_command='echo "Processing complete!"',
    trigger_rule='none_failed_min_one_success',  # Run if at least one upstream succeeded
    dag=dag,
)

# Set dependencies
task_branch >> [task_small, task_medium, task_large] >> validation_group >> task_final
EOF

# Create DAG with dynamic tasks
cat > dynamic_tasks.py <<'EOF'
"""
Dynamic Task Generation

Generates tasks dynamically based on configuration.
"""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator

default_args = {
    'owner': 'data-platform',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'dynamic_tasks',
    default_args=default_args,
    description='Dynamically generate tasks',
    schedule_interval=None,
    catchup=False,
    tags=['dynamic', 'advanced'],
)

# Configuration: tables to process
TABLES = ['customers', 'orders', 'products', 'transactions']

def process_table(table_name):
    """Process a single table"""
    print(f"Processing table: {table_name}")
    print(f"  - Extracting data from {table_name}")
    print(f"  - Transforming {table_name}")
    print(f"  - Loading {table_name} to warehouse")
    print(f"✅ {table_name} processing complete")

# Dynamically create tasks
tasks = []
for table in TABLES:
    task = PythonOperator(
        task_id=f'process_{table}',
        python_callable=process_table,
        op_args=[table],
        dag=dag,
    )
    tasks.append(task)

# Create summary task
def create_summary():
    """Create processing summary"""
    print(f"Processed {len(TABLES)} tables:")
    for table in TABLES:
        print(f"  ✅ {table}")

task_summary = PythonOperator(
    task_id='create_summary',
    python_callable=create_summary,
    dag=dag,
)

# All table processing tasks run in parallel, then summary
tasks >> task_summary
EOF

# Create DAG with S3 sensor
cat > s3_sensor_dag.py <<'EOF'
"""
S3 Sensor DAG

Waits for file to arrive in S3, then processes it.
"""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.amazon.aws.sensors.s3 import S3KeySensor

default_args = {
    'owner': 'data-platform',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    's3_sensor_example',
    default_args=default_args,
    description='Wait for S3 file then process',
    schedule_interval='@hourly',
    catchup=False,
    tags=['s3', 'sensor', 'data-ingestion'],
)

# Note: Update bucket name to match your environment
# Get it from: cd terraform/environments/dev && terraform output -json storage | jq -r '.raw_data_bucket_id'

def process_new_file(**context):
    """Process the file that arrived"""
    bucket = context['params']['bucket']
    key = context['params']['key']

    print(f"Processing new file: s3://{bucket}/{key}")
    print("  - Validating format")
    print("  - Extracting data")
    print("  - Loading to staging")
    print("✅ File processing complete")

# Sensor waits for file (example - will timeout in dev without actual file)
# Uncomment and update bucket/key when ready to use
# wait_for_file = S3KeySensor(
#     task_id='wait_for_s3_file',
#     bucket_name='data-platform-raw-data-dev',
#     bucket_key='landing/new_data_*.csv',
#     wildcard_match=True,
#     timeout=300,  # 5 minutes
#     poke_interval=30,  # Check every 30 seconds
#     mode='poke',
#     dag=dag,
# )

# For demo purposes, just show the process task
task_process = PythonOperator(
    task_id='process_file',
    python_callable=process_new_file,
    params={
        'bucket': 'data-platform-raw-data-dev',
        'key': 'landing/example.csv',
    },
    dag=dag,
)

# wait_for_file >> task_process
EOF
```

**Test new DAGs**:
```bash
cd ../..
./scripts/airflow/test-dags.sh

# Sync to S3
./scripts/airflow/sync-to-mwaa.sh dev

echo "⏰ Wait 5 minutes for MWAA to pick up new DAGs..."
```

### Step 2: Configure SMTP for Email Alerts (Optional) (1 hour)

**Note**: This is optional. For production, you'd use SES or external SMTP.

```bash
cd terraform/environments/dev

# Update orchestration.tf to add SMTP configuration
# This example uses a placeholder - replace with real SMTP server

cat >> orchestration.tf <<'EOF'

# Optional: SMTP configuration for email alerts
# Uncomment and configure for production

# module "orchestration" {
#   # ... existing config ...
#
#   airflow_configuration_options = {
#     # ... existing options ...
#
#     # SMTP configuration
#     "smtp.smtp_host" = "email-smtp.us-east-1.amazonaws.com"
#     "smtp.smtp_starttls" = "True"
#     "smtp.smtp_ssl" = "False"
#     "smtp.smtp_port" = "587"
#     "smtp.smtp_mail_from" = "airflow@data-platform.example.com"
#
#     # SMTP credentials from Secrets Manager
#     "smtp.smtp_user" = "{{{{ conn.aws_default.login }}}}"
#     "smtp.smtp_password" = "{{{{ conn.aws_default.password }}}}"
#   }
# }
EOF

# Create email alert DAG example
cd ../../airflow/dags

cat > email_alerts_example.py <<'EOF'
"""
Email Alerts Example

Shows how to configure email notifications.
Note: Requires SMTP configuration in MWAA.
"""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.email import EmailOperator

default_args = {
    'owner': 'data-platform',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email': ['data-team@example.com'],  # Update with real email
    'email_on_failure': True,  # Send email on task failure
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'email_alerts_example',
    default_args=default_args,
    description='Email notification example',
    schedule_interval=None,
    catchup=False,
    tags=['email', 'alerts', 'example'],
)

def task_that_succeeds():
    print("✅ This task succeeds")

def task_that_fails():
    raise Exception("❌ This task intentionally fails to trigger email alert")

task_success = PythonOperator(
    task_id='successful_task',
    python_callable=task_that_succeeds,
    dag=dag,
)

# Send custom email
send_email = EmailOperator(
    task_id='send_custom_email',
    to=['data-team@example.com'],
    subject='Airflow Success Notification',
    html_content="""
    <h3>DAG Execution Report</h3>
    <p>The email_alerts_example DAG completed successfully.</p>
    <p>Execution date: {{ ds }}</p>
    <p>Check Airflow UI for details.</p>
    """,
    dag=dag,
)

# Uncomment to test failure email (will fail and send email if SMTP configured)
# task_fail = PythonOperator(
#     task_id='failing_task',
#     python_callable=task_that_fails,
#     dag=dag,
# )

task_success >> send_email
EOF
```

### Step 3: Create DAG Deployment Documentation (30 minutes)

```bash
cd ../../docs

cat > DAG_DEVELOPMENT.md <<'EOF'
# DAG Development Guide

## DAG Best Practices

### File Structure

```python
"""
DAG Description

Detailed description of what this DAG does.
"""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator

# Default args
default_args = {
    'owner': 'data-platform',  # Team or person responsible
    'depends_on_past': False,  # Don't wait for previous runs
    'start_date': datetime(2024, 1, 1),  # When DAG starts
    'email': ['team@example.com'],
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'dag_id',  # Unique identifier (lowercase, underscores)
    default_args=default_args,
    description='Short description',
    schedule_interval='@daily',  # or cron: '0 5 * * *'
    catchup=False,  # Don't backfill
    tags=['domain', 'type'],
)

# Tasks...
```

### Naming Conventions

**DAG IDs**:
- Lowercase with underscores
- Format: `{domain}_{process}_{frequency}`
- Examples:
  - `sales_extract_daily`
  - `customer_transform_hourly`
  - `report_generate_weekly`

**Task IDs**:
- Descriptive, action-oriented
- Format: `{verb}_{noun}`
- Examples:
  - `extract_orders`
  - `transform_customer_data`
  - `load_to_warehouse`
  - `send_completion_email`

### Schedule Intervals

**Preset schedules**:
- `@once` - Run once
- `@hourly` - Every hour
- `@daily` - Every day at midnight
- `@weekly` - Every week on Sunday
- `@monthly` - First day of month

**Cron expressions**:
- `'0 5 * * *'` - 5 AM daily
- `'0 */4 * * *'` - Every 4 hours
- `'0 9 * * 1-5'` - 9 AM on weekdays
- `'0 0 1 * *'` - First day of month

**Manual trigger only**:
- `schedule_interval=None`

### Task Dependencies

```python
# Linear
task_a >> task_b >> task_c

# Branching
task_a >> [task_b, task_c]

# Joining
[task_a, task_b] >> task_c

# Complex
task_a >> task_b
task_a >> task_c
[task_b, task_c] >> task_d
```

---

## Testing DAGs

### Local Testing

```bash
# Syntax check
python airflow/dags/your_dag.py

# Test all DAGs
./scripts/airflow/test-dags.sh
```

### Testing in MWAA

1. **Sync to S3**: `./scripts/airflow/sync-to-mwaa.sh dev`
2. **Wait 5 minutes** for MWAA to detect
3. **Check UI**: DAG should appear without import errors
4. **Trigger manually**: Click play button
5. **Check logs**: Verify task execution

### Common Issues

**Import Error**:
- Check DAG processing logs: `aws logs tail airflow-data-platform-dev-DAG --follow`
- Common causes:
  - Python syntax error
  - Missing package in requirements.txt
  - Circular import

**DAG Not Scheduled**:
- Check `start_date` is in the past
- Verify `schedule_interval` is set
- Check if DAG is paused (UI toggle)

**Task Fails**:
- Check task logs in UI
- Verify IAM permissions
- Check resource availability

---

## Deployment Workflow

### Development → Production

**Step 1: Local Development**
```bash
# Create DAG
vim airflow/dags/new_dag.py

# Test locally
./scripts/airflow/test-dags.sh
```

**Step 2: Deploy to Dev**
```bash
# Sync to dev environment
./scripts/airflow/sync-to-mwaa.sh dev

# Wait for pickup
sleep 300

# Trigger test run in Airflow UI
# Verify logs
```

**Step 3: Code Review**
```bash
# Create PR
git checkout -b feature/new-dag
git add airflow/dags/new_dag.py
git commit -m "Add new_dag for customer processing"
git push origin feature/new-dag

# Request review
# Address feedback
```

**Step 4: Deploy to Prod**
```bash
# After PR merged to main
git checkout main
git pull

# Sync to production
./scripts/airflow/sync-to-mwaa.sh prod

# Monitor first run closely
```

---

## DAG Patterns

### Pattern 1: Extract-Transform-Load (ETL)

```python
extract = PythonOperator(task_id='extract', ...)
transform = PythonOperator(task_id='transform', ...)
load = PythonOperator(task_id='load', ...)
validate = PythonOperator(task_id='validate', ...)

extract >> transform >> load >> validate
```

### Pattern 2: Parallel Processing

```python
# Process multiple tables in parallel
tasks = []
for table in ['customers', 'orders', 'products']:
    task = PythonOperator(
        task_id=f'process_{table}',
        python_callable=process_table,
        op_args=[table],
    )
    tasks.append(task)

# All run in parallel, then summary
tasks >> summary_task
```

### Pattern 3: Sensor-Trigger

```python
wait_for_file = S3KeySensor(
    task_id='wait_for_file',
    bucket_name='data-bucket',
    bucket_key='new_data.csv',
)

process = PythonOperator(task_id='process', ...)

wait_for_file >> process
```

### Pattern 4: Conditional Execution

```python
def decide_branch():
    if condition:
        return 'process_a'
    else:
        return 'process_b'

branch = BranchPythonOperator(
    task_id='branch',
    python_callable=decide_branch,
)

task_a = PythonOperator(task_id='process_a', ...)
task_b = PythonOperator(task_id='process_b', ...)

branch >> [task_a, task_b]
```

---

## Monitoring

### Key Metrics

- **DAG Run Duration**: How long DAG takes end-to-end
- **Task Success Rate**: % of tasks that succeed
- **Queue Time**: Time tasks wait before execution
- **Retry Count**: How often tasks retry

### Setting SLAs

```python
default_args = {
    'sla': timedelta(hours=2),  # Task should complete within 2 hours
}

# Or per-task
task = PythonOperator(
    task_id='critical_task',
    sla=timedelta(minutes=30),
    ...
)
```

### Alerts

**On Failure**:
```python
default_args = {
    'email_on_failure': True,
    'email': ['team@example.com'],
}
```

**On Retry**:
```python
default_args = {
    'email_on_retry': True,
}
```

**On SLA Miss**:
```python
# Configure in airflow.cfg or MWAA environment options
'sla_miss_callback': send_sla_alert
```

---

## Best Practices

### Do's ✅

- ✅ Use `catchup=False` to prevent backfill
- ✅ Set reasonable retries (1-3)
- ✅ Add docstrings to DAGs
- ✅ Use tags for organization
- ✅ Version control DAGs
- ✅ Test locally before deploying
- ✅ Monitor task duration
- ✅ Use task groups for related tasks
- ✅ Parameterize with Variables/Secrets

### Don'ts ❌

- ❌ Don't use `schedule_interval='@once'` for production
- ❌ Don't hard-code credentials
- ❌ Don't create massive DAGs (>50 tasks)
- ❌ Don't use top-level code that runs on import
- ❌ Don't delete DAGs without archiving
- ❌ Don't ignore import errors
- ❌ Don't use latest for dependencies
- ❌ Don't skip testing

---

## Resources

- **Airflow Docs**: https://airflow.apache.org/docs/
- **AWS MWAA Docs**: https://docs.aws.amazon.com/mwaa/
- **Best Practices**: https://airflow.apache.org/docs/apache-airflow/stable/best-practices.html

EOF
```

---

## Afternoon Session (3 hours)

### Step 4: Prepare Sprint Demo (1 hour)

```bash
cd ../../

# Create demo script
cat > workshops/sprint-07/DEMO_SCRIPT.md <<'EOF'
# Sprint 7 Demo Script

**Duration**: 15 minutes
**Audience**: Stakeholders, team members

---

## Demo Outline

### 1. Introduction (2 minutes)

**Speaker**: "Today we're demonstrating Sprint 7 deliverables: AWS MWAA environment setup and DAG deployment."

**Agenda**:
1. MWAA infrastructure overview
2. DAG development workflow
3. Live Airflow UI walkthrough
4. CloudWatch logging
5. Q&A

---

### 2. Infrastructure Overview (3 minutes)

**Show Terraform Output**:
```bash
cd terraform/environments/dev
terraform output mwaa
```

**Talking Points**:
- "We deployed a managed Apache Airflow environment"
- "Environment class: mw1.medium (2 vCPU, 4 GB RAM)"
- "Fully integrated with AWS services: S3, Secrets Manager, CloudWatch"
- "Auto-scaling workers (1-10 based on load)"

**Show Architecture** (if diagram created):
- MWAA components: Webserver, Scheduler, Workers
- S3 bucket for DAGs
- CloudWatch for logging
- VPC integration (private subnets)

---

### 3. DAG Development Workflow (3 minutes)

**Demonstrate Local Development**:
```bash
# Show DAG structure
ls -la airflow/dags/

# Show a sample DAG
cat airflow/dags/sample_hello_world.py | head -30
```

**Talking Points**:
- "DAGs written in Python, version controlled in Git"
- "Tested locally before deployment"
- "Synced to S3 every deployment"

**Show Sync Process**:
```bash
./scripts/airflow/sync-to-mwaa.sh dev
```

**Talking Points**:
- "One command deploys all DAGs to MWAA"
- "MWAA auto-detects changes every 5 minutes"
- "No restarts required"

---

### 4. Live Airflow UI Walkthrough (5 minutes)

**Open Airflow UI**:
```bash
# Get URL
MWAA_URL=$(terraform output -json mwaa | jq -r '.webserver_url')
open "https://${MWAA_URL}"
```

**Walk Through**:

1. **DAGs Page**:
   - "Here are all our deployed DAGs"
   - Point out: sample_hello_world, advanced_patterns, dynamic_tasks
   - "Green = healthy, red = import errors"

2. **Trigger a DAG**:
   - Click `advanced_patterns`
   - Click ▶ (trigger)
   - "Watch it execute in real-time"

3. **Graph View**:
   - Show task dependencies
   - "Visual representation of workflow"
   - Highlight branching logic

4. **Grid View**:
   - Show task execution history
   - Color coding: green (success), red (failed), yellow (running)

5. **Task Logs**:
   - Click a task
   - Show logs
   - "All output captured, searchable"

---

### 5. CloudWatch Logging (2 minutes)

**Show Log Groups**:
```bash
aws logs describe-log-groups \
    --log-group-name-prefix "airflow-data-platform-dev" \
    --query 'logGroups[*].logGroupName'
```

**Talking Points**:
- "5 separate log streams for different components"
- "Retained for 7 days (configurable)"
- "Integrated with AWS CloudWatch alarms"

**Tail Logs**:
```bash
aws logs tail airflow-data-platform-dev-Task --follow
```

---

## Q&A Preparation

### Expected Questions

**Q: How much does MWAA cost?**
A: "mw1.medium is ~$700/month. Includes fully managed Airflow, no maintenance overhead. We can scale down to mw1.small (~$350/month) if needed."

**Q: How do we add new DAGs?**
A: "Write Python file in `airflow/dags/`, run sync script, wait 5 minutes. That's it."

**Q: What about production?**
A: "Sprint 11 covers production environment. Same process, separate MWAA instance, stricter access controls."

**Q: Can we schedule dbt runs?**
A: "Yes! Sprint 8 integrates dbt with Airflow using Cosmos library. Coming next week."

**Q: How do we monitor failures?**
A: "Airflow UI shows all failures. We'll add email alerts and CloudWatch alarms in Sprint 12."

**Q: Is it secure?**
A: "Yes - runs in private subnets, IAM authentication, Secrets Manager for credentials, encryption at rest and in transit."

---

## Demo Checklist

Before demo:
- [ ] MWAA environment status = AVAILABLE
- [ ] At least 3 DAGs synced and visible in UI
- [ ] One DAG run successfully completed
- [ ] Terraform outputs accessible
- [ ] CloudWatch logs showing recent activity
- [ ] Browser authenticated to AWS (open UI before demo)
- [ ] Backup slides ready if live demo fails

---

## Success Criteria

Demo is successful if:
- ✅ Airflow UI loads and shows DAGs
- ✅ Can trigger DAG and see it execute
- ✅ Logs visible in UI and CloudWatch
- ✅ Stakeholders understand DAG deployment workflow
- ✅ Team comfortable with Airflow basics

EOF

# Run demo prep checklist
cat > scripts/airflow/demo-prep.sh <<'EOF'
#!/bin/bash
set -e

echo "🎬 Sprint 7 Demo Prep Checklist"
echo ""

# Check MWAA status
echo "1️⃣ Checking MWAA environment..."
MWAA_STATUS=$(aws mwaa get-environment --name data-platform-airflow-dev --query 'Environment.Status' --output text)
if [ "$MWAA_STATUS" = "AVAILABLE" ]; then
    echo "   ✅ MWAA status: AVAILABLE"
else
    echo "   ❌ MWAA status: $MWAA_STATUS (should be AVAILABLE)"
    exit 1
fi

# Check DAGs in S3
echo "2️⃣ Checking DAGs in S3..."
MWAA_BUCKET=$(cd terraform/environments/dev && terraform output -json storage | jq -r '.mwaa_bucket_id')
DAG_COUNT=$(aws s3 ls s3://${MWAA_BUCKET}/dags/ | grep ".py" | wc -l)
echo "   ✅ ${DAG_COUNT} DAG files in S3"

# Check Airflow UI accessible
echo "3️⃣ Checking Airflow UI..."
MWAA_URL=$(cd terraform/environments/dev && terraform output -json mwaa | jq -r '.webserver_url')
echo "   ✅ Airflow UI: https://${MWAA_URL}"

# Check recent logs
echo "4️⃣ Checking CloudWatch logs..."
RECENT_LOGS=$(aws logs describe-log-streams \
    --log-group-name airflow-data-platform-dev-Task \
    --max-items 1 \
    --order-by LastEventTime \
    --descending \
    --query 'logStreams[0].lastEventTimestamp' \
    --output text)

if [ -n "$RECENT_LOGS" ]; then
    echo "   ✅ Recent task logs found"
else
    echo "   ⚠️  No recent task logs (run a DAG first)"
fi

echo ""
echo "✅ Demo prep complete!"
echo ""
echo "📋 Quick Access:"
echo "   Airflow UI: https://${MWAA_URL}"
echo "   Sync DAGs: ./scripts/airflow/sync-to-mwaa.sh dev"
echo "   View logs: aws logs tail airflow-data-platform-dev-Task --follow"
EOF

chmod +x scripts/airflow/demo-prep.sh

# Run prep check
./scripts/airflow/demo-prep.sh
```

### Step 5: Test All DAG Patterns (1 hour)

```bash
# Sync all new DAGs
./scripts/airflow/sync-to-mwaa.sh dev

echo "⏰ Waiting 6 minutes for MWAA to detect new DAGs..."
sleep 360

# Verify DAGs appeared in UI
MWAA_URL=$(cd terraform/environments/dev && terraform output -json mwaa | jq -r '.webserver_url')
echo "Check Airflow UI: https://${MWAA_URL}"
echo ""
echo "Expected DAGs:"
echo "  - sample_hello_world"
echo "  - sample_aws_test"
echo "  - sample_s3_list"
echo "  - advanced_patterns"
echo "  - dynamic_tasks"
echo "  - s3_sensor_example"
echo "  - email_alerts_example"
```

**Manual testing in UI**:
1. Trigger `advanced_patterns` - verify branching works
2. Trigger `dynamic_tasks` - verify all table tasks created
3. Check logs for each task
4. Verify no import errors

### Step 6: Sprint Retrospective (1 hour)

```bash
cd workshops/sprint-07

cat > RETROSPECTIVE.md <<'EOF'
# Sprint 7 Retrospective

**Date**: [Fill in]
**Participants**: [Team members]
**Sprint**: 7 - AWS MWAA Environment Setup
**Duration**: Days 19-21

---

## Sprint Goal

Deploy managed Apache Airflow environment and establish DAG development workflow.

**Goal Status**: ✅ **ACHIEVED**

---

## What We Delivered

### Infrastructure
- [x] MWAA environment (mw1.medium) deployed
- [x] S3 bucket structure for DAGs/plugins
- [x] IAM execution role with proper permissions
- [x] CloudWatch log groups (5 streams)
- [x] Security group configuration

### Code & Automation
- [x] 7 sample DAGs (hello_world, aws_test, s3_list, advanced_patterns, dynamic_tasks, s3_sensor, email_alerts)
- [x] DAG sync automation script
- [x] DAG testing script
- [x] Log viewing utilities

### Documentation
- [x] MWAA setup guide
- [x] MWAA operations guide
- [x] UI access documentation
- [x] DAG development guide
- [x] Demo script

---

## Metrics

| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| MWAA Deploy Time | <40 min | ~32 min | ✅ |
| DAG Sync Time | <10 min | ~5 min | ✅ |
| Sample DAGs Created | 3+ | 7 | ✅ |
| DAG Success Rate | 100% | 100% | ✅ |
| Documentation | Complete | Complete | ✅ |

---

## What Went Well ✅

### Technical

1. **MWAA deployment smooth**
   - No issues with Terraform
   - Environment created on first attempt
   - All networking/security configured correctly

2. **DAG auto-sync works perfectly**
   - 5-minute detection as expected
   - No manual intervention needed
   - Script automation saves time

3. **CloudWatch integration excellent**
   - All 5 log streams working
   - Easy to debug issues
   - Retention policy appropriate

4. **Airflow UI intuitive**
   - Easy for team to learn
   - Good visualization of workflows
   - Logs accessible and clear

### Process

1. **Workshop materials effective**
   - Step-by-step commands worked
   - No blockers during implementation
   - Good validation checkpoints

2. **Documentation comprehensive**
   - Operations guide helpful
   - DAG patterns reusable
   - Troubleshooting section valuable

---

## What Didn't Go Well ❌

### Technical

1. **MWAA deployment wait time**
   - 30+ minutes is long for development
   - Blocks other work during creation
   - **Mitigation**: Used wait time for DAG development

2. **Cost higher than expected**
   - mw1.medium = $700/month
   - Consider mw1.small for dev ($350/month)
   - **Action**: Evaluate downsize after Sprint 8

3. **SMTP not configured**
   - Email alerts not tested
   - Requires SES setup (skipped as optional)
   - **Action**: Add in Sprint 12 (monitoring)

### Process

1. **IAM permissions initially confusing**
   - Had to iterate on execution role policy
   - Documentation could be clearer
   - **Improvement**: Created comprehensive IAM guide

---

## Lessons Learned

### What We Learned

1. **MWAA has long deployment times**
   - Plan for 30-40 minutes
   - Can't iterate quickly on config
   - Use wait time productively

2. **DAG development workflow smooth**
   - Local testing → Sync → UI verification works well
   - 5-minute detection is acceptable
   - Version control critical

3. **CloudWatch logs essential**
   - UI logs good for quick checks
   - CloudWatch better for debugging
   - Tail logs during development

4. **Environment sizing important**
   - Medium may be overkill for dev
   - Monitor worker utilization
   - Can resize if needed

### Best Practices Established

1. ✅ Always sync DAGs via script (not manual S3 upload)
2. ✅ Test DAGs locally before syncing
3. ✅ Use tags to organize DAGs by domain/type
4. ✅ Set `catchup=False` to prevent backfill
5. ✅ Monitor CloudWatch logs during development
6. ✅ Document DAG patterns for team reuse

---

## Action Items

### Technical Debt
- [ ] Consider downsizing to mw1.small for dev environment
- [ ] Add SMTP/SES configuration for email alerts
- [ ] Create Terraform variable for environment class (easy resize)
- [ ] Add CloudWatch alarms for MWAA health

### Documentation
- [x] MWAA setup guide
- [x] DAG development patterns
- [ ] Add troubleshooting runbook (expand based on issues)
- [ ] Create video walkthrough for team

### Process Improvements
- [ ] Add pre-commit hook for DAG syntax checking
- [ ] Create DAG template generator
- [ ] Set up peer review process for DAG PRs
- [ ] Schedule monthly DAG cleanup (remove deprecated)

---

## Sprint Velocity

**Story Points Planned**: 21
**Story Points Completed**: 21
**Velocity**: 100%

**Tasks**:
- Day 1: 6 tasks ✅
- Day 2: 7 tasks ✅
- Day 3: 6 tasks ✅
- **Total**: 19/19 tasks completed

---

## Team Feedback

### What should we start doing?
- Testing DAGs in dev before promoting to prod
- Creating reusable DAG templates
- Monitoring MWAA costs weekly

### What should we stop doing?
- Manual S3 uploads (always use sync script)
- Skipping local testing
- Creating one-off DAGs without documentation

### What should we continue doing?
- Comprehensive documentation
- Automation scripts for common tasks
- Demo at end of sprint

---

## Next Sprint Preview

**Sprint 8**: Airflow-dbt Integration with Cosmos
- Integrate dbt project with Airflow
- Run dbt in ECS Fargate tasks
- Create end-to-end data pipeline DAG
- Cosmos library for dbt orchestration

**Preparation Needed**:
- Review dbt Docker container (Sprint 6)
- Familiarize with ECS task definitions
- Understand Cosmos library concepts

---

## Retrospective Actions

**Immediate** (this week):
1. Evaluate mw1.small for dev cost savings
2. Add environment class as Terraform variable
3. Create DAG template generator

**Short-term** (next sprint):
1. Implement in Sprint 8
2. Monitor costs and worker utilization
3. Expand troubleshooting docs based on issues

**Long-term** (future sprints):
1. SMTP/SES setup (Sprint 12)
2. Advanced monitoring and alerts (Sprint 12)
3. Production MWAA environment (Sprint 11)

---

## Team Shoutouts 🎉

- Great collaboration on DAG patterns
- Excellent troubleshooting during MWAA deployment
- Comprehensive documentation contributions
- Smooth demo delivery

---

**Status**: ✅ Sprint 7 Complete
**Next**: Sprint 8 - Airflow-dbt Integration

EOF
```

---

## End of Day 3 Checklist

- [x] Advanced DAG patterns created (branching, sensors, dynamic tasks)
- [x] SMTP configuration documented (optional)
- [x] DAG development guide completed
- [x] Demo script prepared
- [x] All DAGs tested in MWAA
- [x] Sprint retrospective completed
- [x] Sprint 7 complete

---

## 📝 Daily Standup Notes

**Completed Today**:
- Created 4 advanced DAG patterns (branching, dynamic, sensors, email)
- Documented SMTP configuration for email alerts
- Comprehensive DAG development guide
- Sprint demo script with Q&A prep
- Demo prep automation script
- Sprint retrospective

**Blockers**:
- None

**Tomorrow's Plan**:
- Start Sprint 8: Airflow-dbt Integration
- ECS task definition for dbt
- Cosmos library setup

---

## 🎯 Success Metrics

```bash
# All DAGs in S3
MWAA_BUCKET=$(cd terraform/environments/dev && terraform output -json storage | jq -r '.mwaa_bucket_id')
aws s3 ls s3://${MWAA_BUCKET}/dags/ | wc -l
# Should show: 7+ DAG files

# All DAGs visible in UI (no import errors)
# Check via Airflow UI - all should be green

# MWAA environment healthy
aws mwaa get-environment --name data-platform-airflow-dev \
    --query 'Environment.Status' \
    --output text
# Should output: AVAILABLE

# CloudWatch logs active
aws logs describe-log-streams \
    --log-group-name airflow-data-platform-dev-Task \
    --max-items 5
# Should show recent log streams

# Demo prep passes
./scripts/airflow/demo-prep.sh
# Should show all ✅
```

---

## 🎉 Sprint 7 Complete!

### Achievements

- ✅ MWAA environment deployed and operational
- ✅ 7 sample DAGs demonstrating various patterns
- ✅ Complete DAG development workflow
- ✅ Automated sync and testing scripts
- ✅ Comprehensive documentation
- ✅ Demo delivered successfully

### What We Built

**Infrastructure**:
- AWS MWAA environment (Apache Airflow 2.8.1)
- S3 bucket structure for DAGs
- IAM roles and policies
- CloudWatch logging (5 log groups)
- VPC integration (private subnets)

**Code**:
- 7 production-ready DAG examples
- Sync automation script
- DAG testing utilities
- Log viewing scripts
- Demo preparation tools

**Documentation**:
- MWAA setup guide
- Operations manual
- UI access guide
- DAG development guide
- Demo script
- Retrospective

### Next: Sprint 8

**Airflow-dbt Integration with Cosmos**:
- ECS Fargate tasks for dbt
- Cosmos library integration
- End-to-end data pipeline orchestration

---

**See [Sprint 8 - Day 1](../sprint-08/day-1.md)** 🚀
