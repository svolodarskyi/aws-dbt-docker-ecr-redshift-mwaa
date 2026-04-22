# Sprint 1 - Day 2: Development Tools & Pre-commit Hooks

**Goal**: Configure development tools and quality checks

**Duration**: ~6 hours

**Outcome**: Pre-commit hooks active, Docker running, VSCode configured

---

## Morning Session (3 hours)

### Step 1: Configure Pre-commit Hooks (1 hour)

Pre-commit hooks automatically check code quality before each commit.

```bash
# Activate virtual environment (if not already)
source venv/bin/activate

# Verify pre-commit installed
pre-commit --version

# Install the pre-commit hooks
pre-commit install

# Verify installation
ls -la .git/hooks/
# Should show pre-commit file

# Test hooks (will run all checks on all files - takes time!)
pre-commit run --all-files

# Expected output:
# - Some checks will pass (✓)
# - Some might fail initially (✗) - that's OK!
# - Hooks will auto-fix some issues
```

**Common failures and fixes**:

1. **Trailing whitespace**: Auto-fixed
2. **End of file fixer**: Auto-fixed
3. **Black formatting**: Auto-fixed
4. **Terraform fmt**: Run `terraform fmt -recursive terraform/`
5. **SQL linting**: May need to adjust .sqlfluff config

Fix any issues:
```bash
# Black auto-formats Python files
black airflow/ scripts/

# Format Terraform
terraform fmt -recursive terraform/

# Check YAML syntax
yamllint .github/workflows/

# Run hooks again
pre-commit run --all-files
# Should pass now (or mostly pass)
```

**✅ Validation**:
```bash
# Create a test file with issues
echo "test = 1   " > test.py  # Has trailing space

# Try to commit
git add test.py
git commit -m "test"

# Pre-commit should run and fix issues
# Then you can commit again

# Clean up
git reset HEAD test.py
rm test.py
```

### Step 2: Configure VSCode (30 minutes)

Create workspace settings:

```bash
# Create .vscode directory
mkdir -p .vscode

# Create settings.json
cat > .vscode/settings.json <<'EOF'
{
  "python.defaultInterpreterPath": "${workspaceFolder}/venv/bin/python",
  "python.linting.enabled": true,
  "python.linting.pylintEnabled": true,
  "python.formatting.provider": "black",
  "python.formatting.blackArgs": ["--line-length=100"],
  "editor.formatOnSave": true,
  "editor.rulers": [100],
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "files.exclude": {
    "**/__pycache__": true,
    "**/*.pyc": true,
    "venv": true,
    ".pytest_cache": true,
    "dbt/target": true,
    "dbt/logs": true,
    "dbt/dbt_packages": true
  },
  "sqlfluff.dialect": "redshift",
  "sqlfluff.executablePath": "${workspaceFolder}/venv/bin/sqlfluff",
  "[terraform]": {
    "editor.defaultFormatter": "hashicorp.terraform",
    "editor.formatOnSave": true
  }
}
EOF
```

Create recommended extensions:

```bash
cat > .vscode/extensions.json <<'EOF'
{
  "recommendations": [
    "ms-python.python",
    "ms-python.vscode-pylance",
    "hashicorp.terraform",
    "redhat.vscode-yaml",
    "github.vscode-pull-request-github",
    "eamodio.gitlens",
    "innoverio.vscode-dbt-power-user",
    "dorzey.vscode-sqlfluff"
  ]
}
EOF
```

**✅ Validation**: Open project in VSCode, should prompt to install extensions

### Step 3: Docker Environment Setup (1 hour 30 minutes)

Verify Docker is running:

```bash
# Check Docker
docker --version
docker ps

# Pull required images (saves time later)
docker pull python:3.11-slim
docker pull apache/airflow:2.8.0

# Test Docker build with dbt
cd dbt
docker build -t dbt-test:local .

# Expected: Build completes successfully
# Time: 5-10 minutes

# Test running dbt in container
docker run --rm dbt-test:local --version
# Should show: dbt version

# Clean up test image
docker rmi dbt-test:local

cd ..
```

**Optional**: Set up local Airflow with Docker Compose:

```bash
# Create docker-compose.yml for local development
cat > docker-compose.local.yml <<'EOF'
version: '3.8'

x-airflow-common: &airflow-common
  image: apache/airflow:2.8.0-python3.11
  environment:
    AIRFLOW__CORE__EXECUTOR: LocalExecutor
    AIRFLOW__CORE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:airflow@postgres/airflow
    AIRFLOW__CORE__LOAD_EXAMPLES: 'false'
    AIRFLOW__CORE__DAGS_FOLDER: /opt/airflow/dags
  volumes:
    - ./airflow/dags:/opt/airflow/dags
    - ./airflow/plugins:/opt/airflow/plugins
    - ./airflow/logs:/opt/airflow/logs

services:
  postgres:
    image: postgres:13
    environment:
      POSTGRES_USER: airflow
      POSTGRES_PASSWORD: airflow
      POSTGRES_DB: airflow

  airflow-init:
    <<: *airflow-common
    command: db init
    depends_on:
      - postgres

  airflow-webserver:
    <<: *airflow-common
    command: webserver
    ports:
      - "8080:8080"
    depends_on:
      - postgres
      - airflow-init

  airflow-scheduler:
    <<: *airflow-common
    command: scheduler
    depends_on:
      - postgres
      - airflow-init
EOF

# Start local Airflow (optional, for testing)
docker compose -f docker-compose.local.yml up -d

# Wait for services to start (2-3 minutes)
sleep 120

# Check if running
docker ps
# Should show postgres, airflow-webserver, airflow-scheduler

# Access Airflow UI: http://localhost:8080
# Default credentials: airflow / airflow

# Stop services when done testing
docker compose -f docker-compose.local.yml down
```

**✅ Validation**: Docker build succeeds, containers run

---

## Afternoon Session (3 hours)

### Step 4: Initialize dbt Project (1 hour 30 minutes)

```bash
cd dbt

# Install dbt packages (defined in packages.yml)
dbt deps

# Expected output: Installing packages
# Time: 1-2 minutes

# Verify packages installed
ls dbt_packages/
# Should show: dbt_external_tables, dbt_utils, etc.

# Test dbt debug (will fail - no database yet, that's OK)
dbt debug --profiles-dir ./profiles --target dev

# Expected: Connection test fails (Redshift not set up yet)
# But should see:
# ✓ dbt version check
# ✓ profiles.yml file found
# ✓ profile configured
# ✗ Connection test (expected to fail)

# Compile models (doesn't need database)
dbt compile --profiles-dir ./profiles --target dev

# Expected: All models compile successfully
# Creates target/ directory with compiled SQL
```

Create your first custom dbt model:

```bash
# Create staging directory
mkdir -p models/staging

# Create a simple staging model
cat > models/staging/stg_sample_data.sql <<'EOF'
{{
    config(
        materialized='view',
        tags=['staging', 'sample']
    )
}}

WITH source_data AS (
    SELECT
        1 AS id,
        'Sample Record 1' AS name,
        100.00 AS amount,
        CURRENT_DATE AS created_date

    UNION ALL

    SELECT
        2 AS id,
        'Sample Record 2' AS name,
        250.50 AS amount,
        CURRENT_DATE AS created_date
)

SELECT
    id,
    name,
    amount,
    created_date,
    CURRENT_TIMESTAMP AS loaded_at
FROM source_data
EOF

# Create schema documentation
cat > models/staging/schema.yml <<'EOF'
version: 2

models:
  - name: stg_sample_data
    description: Sample staging model for testing dbt setup
    columns:
      - name: id
        description: Unique identifier
        tests:
          - unique
          - not_null

      - name: name
        description: Record name
        tests:
          - not_null

      - name: amount
        description: Transaction amount
        tests:
          - not_null

      - name: created_date
        description: Date record was created

      - name: loaded_at
        description: Timestamp when data was loaded into warehouse
EOF

# Compile the new model
dbt compile --profiles-dir ./profiles --target dev --select stg_sample_data

# Expected: Compiles successfully
# Check compiled SQL:
cat target/compiled/data_platform/models/staging/stg_sample_data.sql
```

**✅ Validation**:
```bash
# Model compiles without errors
dbt compile --select stg_sample_data

# Compiled SQL exists
test -f target/compiled/data_platform/models/staging/stg_sample_data.sql && echo "✓ Model compiled"
```

### Step 5: Create Sample Airflow DAG (1 hour)

```bash
cd ../airflow/dags

# Create a sample DAG for testing
cat > sample_hello_world.py <<'EOF'
"""
Sample Hello World DAG

This is a simple DAG to test Airflow setup.
It demonstrates basic DAG structure and task dependencies.

Schedule: Manual trigger only (for now)
Owner: Data Engineering Team
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator


def print_context(**context):
    """Print Airflow context information"""
    print(f"Execution Date: {context['execution_date']}")
    print(f"DAG: {context['dag'].dag_id}")
    print(f"Task: {context['task'].task_id}")
    print("✓ Airflow context loaded successfully!")
    return "Success"


# Default arguments for all tasks
default_args = {
    'owner': 'data-engineering',
    'depends_on_past': False,
    'email': ['data-team@example.com'],
    'email_on_failure': False,  # Don't email for this sample DAG
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

# Create DAG
with DAG(
    dag_id='sample_hello_world',
    default_args=default_args,
    description='Simple hello world DAG for testing',
    schedule_interval=None,  # Manual trigger only
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['sample', 'test', 'sprint-1'],
) as dag:

    # Task 1: Print hello message
    hello_task = BashOperator(
        task_id='say_hello',
        bash_command='echo "Hello from Airflow! Today is $(date)"',
    )

    # Task 2: Print context information
    context_task = PythonOperator(
        task_id='print_context',
        python_callable=print_context,
    )

    # Task 3: Print goodbye message
    goodbye_task = BashOperator(
        task_id='say_goodbye',
        bash_command='echo "Goodbye from Airflow! DAG completed successfully."',
    )

    # Define task dependencies
    hello_task >> context_task >> goodbye_task
EOF

# Test DAG imports without errors
python sample_hello_world.py

# Expected: No errors (if errors, check syntax)

# If no output, that's good! It means no errors.
echo "✓ DAG imports successfully"
```

**✅ Validation**:
```bash
# DAG file imports without errors
python sample_hello_world.py && echo "✓ DAG is valid"

# Check DAG structure (requires airflow installed)
# This will fail without Airflow DB, but shows DAG can be parsed
cd ../..
python -c "from airflow.models import DagBag; dag_bag = DagBag(dag_folder='airflow/dags', include_examples=False); print(f'DAGs found: {len(dag_bag.dags)}'); print(f'Import errors: {len(dag_bag.import_errors)}')" || echo "⚠ Airflow DB not initialized (expected)"
```

### Step 6: Generate dbt Documentation (30 minutes)

```bash
cd dbt

# Generate dbt docs
dbt docs generate --profiles-dir ./profiles --target dev

# Expected: Creates documentation artifacts in target/

# Serve documentation locally
# Note: This starts a web server, leave it running
dbt docs serve --port 8001

# Open browser to: http://localhost:8001
# You should see:
# - Project overview
# - Data lineage graph
# - Model documentation (stg_sample_data)

# Press Ctrl+C to stop the server when done
```

Explore the documentation:
- Click on "stg_sample_data" model
- View lineage graph (should be simple with 1 model)
- Check column descriptions
- View compiled SQL

**✅ Validation**: dbt docs opens in browser, shows sample model

---

## End of Day 2 Checklist

- [x] Pre-commit hooks installed and working
- [x] VSCode workspace configured
- [x] Docker verified and test build successful
- [x] dbt packages installed (`dbt deps`)
- [x] Sample dbt model created (`stg_sample_data`)
- [x] Sample Airflow DAG created (`sample_hello_world`)
- [x] DAG imports without errors
- [x] dbt docs generated and viewable

## 📝 Daily Standup Notes

**Completed Today**:
- Configured pre-commit hooks for code quality
- Set up VSCode workspace settings
- Verified Docker environment
- Created first dbt staging model
- Created sample Airflow DAG

**Blockers**:
- None (or list any issues)

**Tomorrow's Plan**:
- Run end-to-end test (dbt + DAG)
- Prepare sprint demo
- Conduct retrospective

## 🎯 Success Metric

**You're successful if**:
```bash
# All these commands work:
pre-commit run --all-files  # Passes
dbt compile --select stg_sample_data  # Compiles
python airflow/dags/sample_hello_world.py  # No errors
dbt docs serve  # Opens in browser
```

---

## ⏭️ Next: Day 3

Tomorrow you'll:
- Test everything end-to-end
- Prepare and deliver sprint demo
- Conduct sprint retrospective
- Plan Sprint 2

**Almost done with Sprint 1!** Open [day-3.md](./day-3.md) when ready. 🚀
