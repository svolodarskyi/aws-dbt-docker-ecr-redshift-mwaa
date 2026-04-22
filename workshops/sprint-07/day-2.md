# Sprint 7 - Day 2: MWAA Deployment & DAG Testing

**Goal**: Deploy MWAA environment and verify DAG execution

**Duration**: ~6 hours (including 30-minute MWAA deployment wait)

**Outcome**: MWAA environment running, DAGs synced and executable, Airflow UI accessible

---

## Morning Session (3 hours)

### Step 1: Deploy MWAA Environment (1 hour 30 minutes)

```bash
cd terraform/environments/dev

# Review what will be created
terraform plan -target=module.orchestration

# Expected resources:
# - aws_mwaa_environment.airflow
# - aws_iam_role.mwaa_execution
# - aws_iam_role_policy.mwaa_execution
# - aws_security_group.mwaa
# - 5x aws_cloudwatch_log_group (DAG, Scheduler, Task, WebServer, Worker)

# Apply (this will take ~25-35 minutes)
echo "⏰ Starting MWAA deployment (takes ~30 minutes)..."
terraform apply -target=module.orchestration

# Note the start time
START_TIME=$(date +%s)
echo "Started at: $(date)"
```

**While waiting for MWAA deployment**, proceed to Step 2 in a new terminal.

**Monitor deployment**:
```bash
# In original terminal, watch status
watch -n 30 'aws mwaa get-environment \
    --name data-platform-airflow-dev \
    --query "Environment.Status" \
    --output text'

# Status progression:
# - CREATING (0-25 minutes)
# - AVAILABLE (deployment complete)
```

### Step 2: Validate and Test DAGs Locally (30 minutes)

**In a new terminal while MWAA is deploying**:

```bash
cd airflow/dags

# Create DAG testing script
cat > ../../scripts/airflow/test-dags.sh <<'EOF'
#!/bin/bash
set -e

echo "🧪 Testing DAG files for syntax errors..."

DAG_DIR="airflow/dags"

if [ ! -d "$DAG_DIR" ]; then
    echo "❌ Error: $DAG_DIR not found"
    exit 1
fi

FAILED=0
PASSED=0

for dag_file in $DAG_DIR/*.py; do
    if [ "$dag_file" = "$DAG_DIR/.gitkeep" ]; then
        continue
    fi

    echo -n "Testing $(basename $dag_file)... "

    # Try to import the DAG
    if python3 -c "import sys; sys.path.insert(0, 'airflow/dags'); exec(open('$dag_file').read())" 2>/dev/null; then
        echo "✅ PASS"
        ((PASSED++))
    else
        echo "❌ FAIL"
        echo "Error in $dag_file:"
        python3 -c "import sys; sys.path.insert(0, 'airflow/dags'); exec(open('$dag_file').read())" 2>&1 | head -5
        ((FAILED++))
    fi
done

echo ""
echo "Results: $PASSED passed, $FAILED failed"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
EOF

chmod +x ../../scripts/airflow/test-dags.sh

# Run DAG tests
cd ../..
./scripts/airflow/test-dags.sh
```

**Create additional test DAG for S3 access**:
```bash
cat > airflow/dags/sample_s3_list.py <<'EOF'
"""
Sample S3 List DAG

Lists objects in the data platform S3 buckets.
"""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.amazon.aws.hooks.s3 import S3Hook

default_args = {
    'owner': 'data-platform',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'sample_s3_list',
    default_args=default_args,
    description='List S3 buckets and objects',
    schedule_interval=None,  # Manual trigger only
    catchup=False,
    tags=['sample', 's3', 'test'],
)

def list_data_buckets():
    """List data platform buckets"""
    s3_hook = S3Hook(aws_conn_id='aws_default')

    # Get S3 client
    s3_client = s3_hook.get_conn()

    # List all buckets
    response = s3_client.list_buckets()
    all_buckets = response['Buckets']

    # Filter for data-platform buckets
    data_buckets = [b['Name'] for b in all_buckets if 'data-platform' in b['Name']]

    print(f"Found {len(data_buckets)} data-platform buckets:")
    for bucket in data_buckets:
        print(f"  - {bucket}")

        # List first 5 objects in each bucket
        try:
            objects = s3_client.list_objects_v2(Bucket=bucket, MaxKeys=5)
            if 'Contents' in objects:
                print(f"    Objects (showing first 5):")
                for obj in objects['Contents']:
                    print(f"      - {obj['Key']} ({obj['Size']} bytes)")
            else:
                print(f"    (empty)")
        except Exception as e:
            print(f"    Error listing: {e}")

        print()

    return data_buckets

def list_raw_data():
    """List raw data files"""
    import boto3

    s3 = boto3.client('s3')

    # List buckets to find raw-data bucket
    buckets = s3.list_buckets()['Buckets']
    raw_bucket = None

    for bucket in buckets:
        if 'raw-data' in bucket['Name']:
            raw_bucket = bucket['Name']
            break

    if not raw_bucket:
        print("No raw-data bucket found")
        return

    print(f"Raw data bucket: {raw_bucket}")

    # List all objects
    response = s3.list_objects_v2(Bucket=raw_bucket)

    if 'Contents' not in response:
        print("No files in raw-data bucket")
        return

    print(f"Files in {raw_bucket}:")
    for obj in response['Contents']:
        size_mb = obj['Size'] / (1024 * 1024)
        print(f"  - {obj['Key']}: {size_mb:.2f} MB")

task_list_buckets = PythonOperator(
    task_id='list_data_buckets',
    python_callable=list_data_buckets,
    dag=dag,
)

task_list_raw_data = PythonOperator(
    task_id='list_raw_data',
    python_callable=list_raw_data,
    dag=dag,
)

task_list_buckets >> task_list_raw_data
EOF

# Test the new DAG
./scripts/airflow/test-dags.sh
```

### Step 3: Check MWAA Deployment Status (30 minutes)

**After ~30 minutes**, check if MWAA is ready:

```bash
cd terraform/environments/dev

# Check status
aws mwaa get-environment --name data-platform-airflow-dev \
    --query 'Environment.{Status:Status,WebserverUrl:WebserverUrl}' \
    --output table

# Get detailed output
terraform output mwaa

# Should show:
# {
#   "environment_name" = "data-platform-airflow-dev"
#   "webserver_url" = "https://xxxxx.airflow.us-east-1.amazonaws.com"
#   "execution_role" = "arn:aws:iam::ACCOUNT:role/..."
#   "status" = "AVAILABLE"
# }

# Save webserver URL for later
MWAA_URL=$(terraform output -json mwaa | jq -r '.webserver_url')
echo "MWAA Webserver URL: https://${MWAA_URL}"
echo "https://${MWAA_URL}" > ../../../.mwaa_url
```

**If status is still "CREATING"**, wait a bit longer and continue with documentation below.

---

## Afternoon Session (3 hours)

### Step 4: Sync DAGs to S3 (30 minutes)

```bash
cd ../../../

# Verify sync script is ready
./scripts/airflow/sync-to-mwaa.sh dev

# Output should show:
# 🚀 Syncing Airflow files to MWAA S3 bucket...
# 📦 MWAA Bucket: data-platform-mwaa-dev
# 📁 Syncing DAGs...
# 📋 Uploading requirements.txt...
# ✅ Sync complete!

# Verify files in S3
MWAA_BUCKET=$(cd terraform/environments/dev && terraform output -json storage | jq -r '.mwaa_bucket_id')

aws s3 ls s3://${MWAA_BUCKET}/dags/ --recursive

# Should show:
# - sample_hello_world.py
# - sample_aws_test.py
# - sample_s3_list.py
```

**Create monitoring script**:
```bash
cat > scripts/airflow/watch-dag-sync.sh <<'EOF'
#!/bin/bash

MWAA_BUCKET=$(cd terraform/environments/dev && terraform output -json storage | jq -r '.mwaa_bucket_id')

echo "📊 Monitoring MWAA DAG sync..."
echo "Bucket: ${MWAA_BUCKET}"
echo ""
echo "DAGs in S3:"
aws s3 ls s3://${MWAA_BUCKET}/dags/ --recursive --human-readable

echo ""
echo "⏰ MWAA picks up changes every ~5 minutes"
echo "Check Airflow UI after sync completes"
EOF

chmod +x scripts/airflow/watch-dag-sync.sh
```

**Wait 5-7 minutes** for MWAA to pick up DAGs, then proceed to Step 5.

### Step 5: Access Airflow UI (1 hour)

```bash
# Get MWAA webserver URL
cd terraform/environments/dev
MWAA_URL=$(terraform output -json mwaa | jq -r '.webserver_url')

echo "🌐 Airflow UI: https://${MWAA_URL}"
echo ""
echo "Opening Airflow UI in browser..."
echo "You will be redirected to AWS SSO for authentication"

# Open in browser (macOS)
open "https://${MWAA_URL}"

# For Linux
# xdg-open "https://${MWAA_URL}"
```

**In Airflow UI**:

1. **Verify DAGs appear**:
   - Should see: `sample_hello_world`, `sample_aws_test`, `sample_s3_list`
   - All should show green (no import errors)

2. **Check DAG details**:
   - Click on `sample_hello_world`
   - Verify graph view shows tasks
   - Check schedule: Daily
   - Check tags: sample, hello-world

3. **Trigger manual run**:
   - Click play button (▶) next to DAG name
   - Confirm "Trigger DAG"
   - Watch task progress in Grid view

4. **View logs**:
   - Click on task (e.g., "hello")
   - Click "Logs" tab
   - Should see: "Hello from MWAA!"

**Create UI access documentation**:
```bash
cd ../../../docs

cat > MWAA_UI_ACCESS.md <<'EOF'
# MWAA UI Access Guide

## Getting the Webserver URL

```bash
cd terraform/environments/dev
terraform output -json mwaa | jq -r '.webserver_url'
```

## Authentication

MWAA uses **AWS IAM authentication** by default.

### Required IAM Permissions

To access Airflow UI, users need:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "airflow:CreateWebLoginToken",
      "Resource": "arn:aws:airflow:REGION:ACCOUNT:environment/data-platform-airflow-dev"
    }
  ]
}
```

### Create IAM Policy for Airflow Access

```bash
cat > /tmp/mwaa-webserver-policy.json <<'POLICY'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "airflow:CreateWebLoginToken",
      "Resource": "arn:aws:airflow:*:*:environment/data-platform-airflow-*"
    }
  ]
}
POLICY

aws iam create-policy \
    --policy-name DataPlatformMWAAWebAccess \
    --policy-document file:///tmp/mwaa-webserver-policy.json

# Attach to user or role
aws iam attach-user-policy \
    --user-name YOUR_USERNAME \
    --policy-arn arn:aws:iam::ACCOUNT_ID:policy/DataPlatformMWAAWebAccess
```

## Airflow Roles

After first login, users get assigned Airflow roles:

- **Admin**: Full access (create, edit, delete DAGs and tasks)
- **Op**: Operator role (trigger DAGs, view logs)
- **User**: Read-only access
- **Viewer**: View DAGs only
- **Public**: No access

### Setting Default Role

In Terraform (`terraform/modules/orchestration/main.tf`):

```hcl
airflow_configuration_options = {
  "webserver.default_ui_role" = "Op"  # Default for new users
}
```

## Accessing via AWS Console

1. Go to **MWAA Console**
2. Select environment: `data-platform-airflow-dev`
3. Click **Open Airflow UI** button
4. Authenticate with your AWS credentials
5. Redirected to Airflow UI

## Direct URL Access

```bash
# Get URL
MWAA_URL=$(cd terraform/environments/dev && terraform output -json mwaa | jq -r '.webserver_url')

# Open in browser
open "https://${MWAA_URL}"
```

## Troubleshooting Access Issues

### Error: "Access Denied"

**Cause**: Missing IAM permission `airflow:CreateWebLoginToken`

**Solution**: Add IAM policy (see above)

### Error: "Environment not found"

**Cause**: Wrong region or environment name

**Solution**: Verify region and environment name match

### UI Loads but Shows "No DAGs"

**Cause**: DAGs not synced to S3, or import errors

**Solution**:
1. Check S3: `aws s3 ls s3://MWAA_BUCKET/dags/`
2. Check DAG processing logs: `aws logs tail airflow-data-platform-dev-DAG --follow`

### Can't Create Web Login Token

**Cause**: Network connectivity or MWAA environment not healthy

**Solution**:
1. Check MWAA status: `aws mwaa get-environment --name data-platform-airflow-dev`
2. Verify security group allows outbound HTTPS

EOF
```

### Step 6: Test DAG Execution and Verify Logs (1 hour 30 minutes)

**Trigger all sample DAGs**:

```bash
# Via AWS CLI (alternative to UI)
cat > scripts/airflow/trigger-dag.sh <<'EOF'
#!/bin/bash
set -e

DAG_ID=$1
ENVIRONMENT=${2:-dev}

if [ -z "$DAG_ID" ]; then
    echo "Usage: $0 <dag_id> [environment]"
    echo "Example: $0 sample_hello_world dev"
    exit 1
fi

# Get MWAA environment name
MWAA_ENV="data-platform-airflow-${ENVIRONMENT}"

echo "🚀 Triggering DAG: ${DAG_ID} in ${MWAA_ENV}..."

# Create CLI token
TOKEN=$(aws mwaa create-cli-token --name ${MWAA_ENV} --query CliToken --output text)

# Get webserver URL
WEBSERVER_URL=$(aws mwaa get-environment --name ${MWAA_ENV} --query 'Environment.WebserverUrl' --output text)

# Trigger DAG via Airflow API
RESPONSE=$(curl -s -X POST \
    "https://${WEBSERVER_URL}/api/v1/dags/${DAG_ID}/dagRuns" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"conf":{}}')

if echo "$RESPONSE" | grep -q "dag_run_id"; then
    RUN_ID=$(echo "$RESPONSE" | jq -r '.dag_run_id')
    echo "✅ DAG triggered successfully!"
    echo "Run ID: ${RUN_ID}"
    echo ""
    echo "Check status in Airflow UI or run:"
    echo "  aws logs tail airflow-${ENVIRONMENT}-Task --follow --filter-pattern \"${DAG_ID}\""
else
    echo "❌ Failed to trigger DAG"
    echo "Response: $RESPONSE"
    exit 1
fi
EOF

chmod +x scripts/airflow/trigger-dag.sh

# Trigger sample DAGs (or use UI)
# ./scripts/airflow/trigger-dag.sh sample_hello_world dev
# ./scripts/airflow/trigger-dag.sh sample_aws_test dev
# ./scripts/airflow/trigger-dag.sh sample_s3_list dev
```

**Monitor task execution via CloudWatch**:
```bash
# Follow task logs
aws logs tail airflow-data-platform-dev-Task --follow

# Filter for specific DAG
aws logs tail airflow-data-platform-dev-Task \
    --follow \
    --filter-pattern "sample_hello_world"

# In another terminal, follow scheduler logs
aws logs tail airflow-data-platform-dev-Scheduler --follow
```

**In Airflow UI**, verify for each DAG run:

1. **Grid View**:
   - All tasks show green (success)
   - Execution time reasonable (<1 minute for simple tasks)

2. **Graph View**:
   - All task dependencies correct
   - Task flow makes sense

3. **Task Logs** (click task → Logs):
   - `sample_hello_world`: Should see "Hello from MWAA!"
   - `sample_aws_test`: Should list S3 buckets, Secrets Manager access
   - `sample_s3_list`: Should list data-platform buckets and objects

**Create log viewing script**:
```bash
cat > scripts/airflow/view-dag-logs.sh <<'EOF'
#!/bin/bash

DAG_ID=$1
ENVIRONMENT=${2:-dev}

if [ -z "$DAG_ID" ]; then
    echo "Usage: $0 <dag_id> [environment]"
    echo "Example: $0 sample_hello_world dev"
    exit 1
fi

echo "📋 Viewing logs for DAG: ${DAG_ID}"
echo "Press Ctrl+C to stop"
echo ""

# Tail task logs for specific DAG
aws logs tail "airflow-data-platform-${ENVIRONMENT}-Task" \
    --follow \
    --filter-pattern "${DAG_ID}" \
    --format short
EOF

chmod +x scripts/airflow/view-dag-logs.sh

# Usage:
# ./scripts/airflow/view-dag-logs.sh sample_hello_world dev
```

**Verification checklist in Airflow UI**:

- [ ] All 3 DAGs appear without import errors
- [ ] `sample_hello_world` runs successfully
- [ ] Task logs visible for all tasks
- [ ] `sample_aws_test` accesses S3 and Secrets Manager
- [ ] `sample_s3_list` lists data-platform buckets
- [ ] No errors in scheduler logs
- [ ] CloudWatch Log Groups created and receiving logs

---

## End of Day 2 Checklist

- [x] MWAA environment deployed (Status: AVAILABLE)
- [x] DAGs validated and synced to S3
- [x] MWAA picked up DAGs (visible in UI)
- [x] Airflow UI accessible
- [x] IAM access configured
- [x] Sample DAGs executed successfully
- [x] CloudWatch logs show task execution
- [x] UI access documentation created

---

## 📝 Daily Standup Notes

**Completed Today**:
- Deployed MWAA environment (~30 minutes)
- Synced DAGs to S3 bucket
- Accessed Airflow UI via AWS authentication
- Triggered and verified all 3 sample DAGs
- Confirmed CloudWatch logging operational
- Created DAG trigger and log viewing scripts
- Documented UI access procedures

**Blockers**:
- None

**Tomorrow's Plan**:
- Create more complex DAGs with sensors
- Configure SMTP for email alerts (optional)
- Document complete DAG deployment workflow
- Sprint demo: Deploy DAG via S3 sync, trigger in UI
- Retrospective

---

## 🎯 Success Metrics

```bash
# MWAA environment healthy
aws mwaa get-environment --name data-platform-airflow-dev \
    --query 'Environment.Status' \
    --output text
# Should output: AVAILABLE

# DAGs in S3
MWAA_BUCKET=$(cd terraform/environments/dev && terraform output -json storage | jq -r '.mwaa_bucket_id')
aws s3 ls s3://${MWAA_BUCKET}/dags/
# Should show: 3 DAG files

# Can access Airflow UI
MWAA_URL=$(cd terraform/environments/dev && terraform output -json mwaa | jq -r '.webserver_url')
curl -I "https://${MWAA_URL}" 2>&1 | grep "HTTP"
# Should show: HTTP/2 200 or 302 (redirect to auth)

# DAG runs succeeded
aws logs tail airflow-data-platform-dev-Task --since 10m | grep "success"
# Should show successful task completions

# CloudWatch log groups exist
aws logs describe-log-groups \
    --log-group-name-prefix "airflow-data-platform-dev" \
    --query 'logGroups[*].logGroupName'
# Should show 5 log groups (DAG, Scheduler, Task, WebServer, Worker)
```

---

## 💡 Key Learnings

### MWAA Deployment Time
- Initial deployment: 25-35 minutes
- Updates (config changes): 10-20 minutes
- DAG sync: ~5 minutes auto-detection

### DAG Development Workflow
1. Write DAG locally in `airflow/dags/`
2. Test syntax: `./scripts/airflow/test-dags.sh`
3. Sync to S3: `./scripts/airflow/sync-to-mwaa.sh dev`
4. Wait 5 minutes for MWAA to detect
5. Check Airflow UI for DAG appearance
6. Trigger manually or wait for schedule

### CloudWatch Logs
- **DAG logs**: Import errors, parsing issues
- **Scheduler logs**: Scheduling decisions, DAG file processing
- **Task logs**: Individual task execution output
- **Worker logs**: Worker startup, health
- **WebServer logs**: UI access, authentication

### Cost Awareness
- **mw1.medium**: ~$700/month (~$0.95/hour)
- **Always running** (no stop/start)
- **Log storage**: $0.50/GB/month (retention: 7 days)

---

## 🔧 Troubleshooting

### MWAA Stuck in "CREATING" Status

**Check**:
```bash
aws mwaa get-environment --name data-platform-airflow-dev \
    --query 'Environment.{Status:Status,LastUpdate:LastUpdate}'
```

**If stuck >40 minutes**:
- Check S3 bucket exists and has `requirements.txt`
- Verify private subnets have routes to NAT gateway
- Check security group allows self-referencing traffic
- Review CloudFormation events in AWS console

**Solution**: May need to destroy and recreate:
```bash
terraform destroy -target=module.orchestration
terraform apply -target=module.orchestration
```

### DAGs Not Appearing in UI

**Check S3**:
```bash
aws s3 ls s3://${MWAA_BUCKET}/dags/
```

**Check DAG processing logs**:
```bash
aws logs tail airflow-data-platform-dev-DAG --follow
```

**Common causes**:
- Python syntax errors
- Missing imports (package not in requirements.txt)
- Circular imports
- DAG ID conflicts

### Cannot Access Airflow UI

**Check IAM permissions**:
```bash
aws iam get-user-policy --user-name YOUR_USER --policy-name MWAAWebAccess
```

**Verify MWAA status**:
```bash
aws mwaa get-environment --name data-platform-airflow-dev
```

**Check region**: Ensure you're in the correct AWS region (us-east-1)

---

## ⏭️ Next: Day 3

Tomorrow: Advanced DAG patterns, SMTP configuration, demo, retrospective

**See [day-3.md](./day-3.md)** 🚀
