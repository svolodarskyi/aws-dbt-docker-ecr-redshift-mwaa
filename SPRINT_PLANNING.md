# Sprint Planning - AWS Data Platform

## Project Timeline Overview

**Total Duration**: 42 days (14 sprints × 3 days)
**Team Size**: 4-5 people (Tech Lead, 2 Data Engineers, 1 DevOps, 1 QA part-time)
**Sprint Length**: 3 days each
**Release Strategy**: Incremental releases after Sprint 6, 10, and 14

## Sprint Structure

Each sprint follows this daily pattern:
- **Day 1**: Planning (1 hour) → Development (6 hours) → Daily standup (15 min)
- **Day 2**: Development (6 hours) → Code review (1 hour) → Daily standup (15 min)
- **Day 3**: Testing (3 hours) → Demo (1 hour) → Retrospective (1 hour) → Sprint closure (1 hour)

---

## Phase 1: Foundation (Sprints 1-4) - 12 Days

### Sprint 1: Project Setup & Local Development Environment
**Duration**: Days 1-3
**Goal**: Establish development infrastructure and team workflows

#### Objectives
- Repository structure created
- Local development environment functional
- Team can run basic workflows locally

#### Deliverables

**Day 1**:
- [x] GitHub repository initialized with branch protection
- [x] Project directory structure created
- [x] README, ARCHITECTURE, and this document committed
- [x] .gitignore configured (Terraform state, Python cache, secrets)
- [x] Development dependencies listed (requirements-dev.txt)

**Day 2**:
- [x] Pre-commit hooks configured (black, pylint, terraform fmt, sqlfluff)
- [x] GitHub Actions workflows for linting created
- [x] VSCode workspace settings shared (settings.json, extensions.json)
- [x] Docker Compose for local Airflow development
- [x] Basic dbt project initialized (`dbt init`)

**Day 3**:
- [x] Sample dbt model created and tested locally
- [x] Sample Airflow DAG created
- [x] Team onboarding guide documented
- [x] Demo: Run dbt locally, trigger sample DAG
- [x] Retrospective: Document any setup blockers

#### Acceptance Criteria
- ✅ All team members can clone repo and run setup scripts
- ✅ Sample dbt model compiles and runs
- ✅ Pre-commit hooks execute successfully
- ✅ GitHub Actions CI passes

#### Risks & Gaps
- **Risk**: Team members unfamiliar with dbt → Mitigation: Pair programming sessions
- **Risk**: Docker Desktop licensing issues → Mitigation: Document alternatives (Rancher Desktop)
- **Gap**: No Redshift cluster yet (using DuckDB locally for now)

---

### Sprint 2: AWS Account Setup & Terraform Foundation
**Duration**: Days 4-6
**Goal**: Provision core AWS infrastructure for dev environment

#### Objectives
- AWS accounts configured with proper security
- Terraform state management operational
- Networking foundation in place

#### Deliverables

**Day 1**:
- [x] AWS Organizations structure (if needed)
- [x] IAM users/roles for team members
- [x] S3 bucket for Terraform state created (manually, one-time)
- [x] DynamoDB table for state locks created
- [x] Terraform backend configuration
- [x] AWS credentials configured locally (AWS CLI profiles)

**Day 2**:
- [x] Terraform module: `networking` (VPC, subnets, NAT gateway)
  - 2 public subnets (for NAT, bastion)
  - 4 private subnets (for MWAA, ECS, Redshift)
  - Multi-AZ setup
- [x] Terraform module: `security-groups`
- [x] VPC endpoints (S3, ECR, ECS, Secrets Manager)
- [x] Terraform module: `iam-roles` (basic structure)

**Day 3**:
- [x] Apply Terraform to dev environment
- [x] Validate VPC and subnets created
- [x] Test VPC endpoint connectivity
- [x] Document Terraform structure and usage
- [x] Demo: Show AWS resources in console
- [x] Tag all resources (Environment, Project, ManagedBy)

#### Acceptance Criteria
- ✅ Terraform state stored in S3 with versioning
- ✅ State locks working via DynamoDB
- ✅ VPC with public/private subnets operational
- ✅ VPC endpoints functional (test with CLI)
- ✅ All resources properly tagged

#### Risks & Gaps
- **Risk**: AWS quota limits → Mitigation: Request increases proactively
- **Risk**: Cost overrun → Mitigation: Set up billing alerts (budget $500/month dev)
- **Gap**: No monitoring yet (CloudWatch setup in later sprint)

---

### Sprint 3: S3 Storage & Data Lake Foundation
**Duration**: Days 7-9
**Goal**: Create S3 data lake structure with lifecycle policies

#### Objectives
- S3 buckets created for all data zones
- EventBridge rule for S3 events configured
- Sample data ingestion working

#### Deliverables

**Day 1**:
- [x] Terraform module: `storage`
  - S3 bucket: `{project}-raw-data-dev`
  - S3 bucket: `{project}-dbt-artifacts-dev`
  - S3 bucket: `{project}-mwaa-dev` (for DAGs)
- [x] S3 bucket policies (encryption, versioning)
- [x] Lifecycle policies defined (IA, Glacier transitions)
- [x] Folder structure in raw-data bucket:
  - `/landing/{source}/{YYYY-MM-DD}/`
  - `/raw/{source}/{table}/{YYYY-MM-DD}/`
  - `/processed/{domain}/{table}/{YYYY-MM-DD}/`

**Day 2**:
- [x] EventBridge rule: S3 object created in /landing/
- [x] Sample data files prepared (CSV, JSON, Parquet)
- [x] Python script to simulate data drops
- [x] S3 event notifications tested
- [x] IAM role for EventBridge → MWAA (placeholder for now)

**Day 3**:
- [x] Apply Terraform for storage resources
- [x] Upload sample data to S3
- [x] Verify EventBridge rule triggers (CloudWatch logs)
- [x] Document S3 bucket structure and naming conventions
- [x] Demo: Upload file, show event trigger in EventBridge console

#### Acceptance Criteria
- ✅ 3 S3 buckets created with encryption
- ✅ Sample data uploaded successfully
- ✅ EventBridge rule triggers on S3 events
- ✅ Bucket policies enforce encryption
- ✅ Versioning enabled on critical buckets

#### Risks & Gaps
- **Risk**: S3 costs escalate with versioning → Mitigation: Short lifecycle for dev
- **Gap**: No MWAA yet, so EventBridge rule doesn't trigger DAG
- **Gap**: No data validation on upload (handled in later sprint)

---

### Sprint 4: Redshift Cluster & Database Setup
**Duration**: Days 10-12
**Goal**: Provision Redshift cluster and configure database schemas

#### Objectives
- Redshift cluster operational in dev
- Database schemas created
- Team can connect and query

#### Deliverables

**Day 1**:
- [x] Terraform module: `data`
  - Redshift cluster (dc2.large, 2 nodes for dev)
  - Redshift subnet group (private subnets)
  - Redshift parameter group (optimized settings)
- [x] Secrets Manager: Redshift master credentials
- [x] IAM role: `redshift-spectrum-role` (S3 read access)
- [x] Attach IAM role to Redshift cluster

**Day 2**:
- [x] Apply Terraform for Redshift
- [x] Connect via SQL client (DBeaver/pgAdmin)
- [x] Create database schemas:
  - `raw_schema` (external tables)
  - `staging_schema` (dbt staging models)
  - `analytics_schema` (dbt marts)
  - `audit_schema` (metadata)
- [x] Create Glue Data Catalog database
- [x] Create external schema pointing to Glue
- [x] Test Redshift Spectrum: query S3 data

**Day 3**:
- [x] Create sample external table in Glue
- [x] Query external table from Redshift
- [x] Document connection strings and access patterns
- [x] Update dbt profiles.yml with Redshift connection
- [x] Test dbt connection: `dbt debug --target dev`
- [x] Demo: Query S3 data via Redshift Spectrum

#### Acceptance Criteria
- ✅ Redshift cluster accessible from VPC
- ✅ Schemas created successfully
- ✅ External schema queries S3 data
- ✅ dbt can connect to Redshift
- ✅ Credentials stored in Secrets Manager (not hardcoded)

#### Risks & Gaps
- **Risk**: Redshift costs (~$600/month) → Mitigation: Pause cluster off-hours (automated script)
- **Risk**: Data catalog confusion (Glue vs Redshift) → Mitigation: Clear documentation
- **Gap**: No external tables via dbt yet (next sprint)

---

## Phase 2: Core Data Pipeline (Sprints 5-8) - 12 Days

### Sprint 5: dbt Core Models & External Tables
**Duration**: Days 13-15
**Goal**: Build dbt transformation pipeline with external tables

#### Objectives
- dbt-external-tables package configured
- Sample data pipeline: S3 → External Table → Staging → Mart
- Data quality tests passing

#### Deliverables

**Day 1**:
- [x] Configure dbt packages.yml:
  ```yaml
  packages:
    - package: dbt-labs/dbt_external_tables
      version: 0.8.7
  ```
- [x] Run `dbt deps`
- [x] Create `models/external/sources.yml`:
  - Define external sources (S3 paths)
  - Configure Glue catalog
- [x] Create `models/external/ext_sales_data.sql`
- [x] Generate external tables: `dbt run-operation stage_external_sources`

**Day 2**:
- [x] Create staging models:
  - `models/staging/stg_sales__orders.sql`
  - `models/staging/stg_sales__customers.sql`
- [x] Create intermediate models:
  - `models/intermediate/int_customers_deduped.sql`
- [x] Create mart models:
  - `models/marts/customers_dim.sql`
  - `models/marts/orders_fct.sql`
- [x] Add dbt tests (unique, not_null, relationships)
- [x] Configure dbt_project.yml (materialization strategies)

**Day 3**:
- [x] Run dbt: `dbt run --target dev`
- [x] Run tests: `dbt test --target dev`
- [x] Fix any failing tests
- [x] Generate docs: `dbt docs generate && dbt docs serve`
- [x] Review data lineage in dbt docs
- [x] Demo: Show end-to-end transformation (S3 → Redshift tables)

#### Acceptance Criteria
- ✅ External tables created via dbt
- ✅ Staging models materialize successfully
- ✅ All dbt tests pass (100%)
- ✅ Data lineage documented
- ✅ dbt docs accessible locally

#### Risks & Gaps
- **Risk**: Data type mismatches (S3 vs Redshift) → Mitigation: Explicit casting in models
- **Risk**: Large S3 files cause OOM → Mitigation: Partition data by date
- **Gap**: No incremental models yet (batch only for now)

---

### Sprint 6: Docker Containerization for dbt
**Duration**: Days 16-18
**Goal**: Containerize dbt project for production deployment

#### Objectives
- Dockerfile optimized for dbt
- Container runs successfully locally
- ECR repository created

#### Deliverables

**Day 1**:
- [x] Create `dbt/Dockerfile`:
  ```dockerfile
  FROM python:3.11-slim

  WORKDIR /usr/app/dbt

  # Install dbt dependencies
  COPY requirements.txt .
  RUN pip install --no-cache-dir -r requirements.txt

  # Copy dbt project
  COPY . .

  # Set environment
  ENV DBT_PROFILES_DIR=/usr/app/dbt/profiles

  ENTRYPOINT ["dbt"]
  CMD ["run"]
  ```
- [x] Create `dbt/requirements.txt`:
  ```
  dbt-core==1.7.4
  dbt-redshift==1.7.1
  dbt-external-tables==0.8.7
  ```
- [x] Create `.dockerignore` (exclude target/, logs/, venv/)
- [x] Build image locally: `docker build -t dbt-project:latest ./dbt`

**Day 2**:
- [x] Test container locally:
  ```bash
  docker run \
    -e REDSHIFT_HOST=... \
    -e REDSHIFT_USER=... \
    -e REDSHIFT_PASSWORD=... \
    -e DBT_TARGET=dev \
    dbt-project:latest dbt run
  ```
- [x] Multi-stage build optimization (reduce image size)
- [x] Create entrypoint script (entrypoint.sh) for flexibility
- [x] Terraform: Create ECR repository
- [x] Push image to ECR:
  ```bash
  aws ecr get-login-password | docker login --username AWS --password-stdin <ecr>
  docker tag dbt-project:latest <ecr>/dbt-project:latest
  docker push <ecr>/dbt-project:latest
  ```

**Day 3**:
- [x] Scan image for vulnerabilities (Trivy)
- [x] Fix any critical/high vulnerabilities
- [x] Document Docker build and push process
- [x] Create GitHub Actions workflow: docker-build.yml
- [x] Demo: Build and push to ECR via CI
- [x] **Milestone Release 1**: Container image ready for orchestration

#### Acceptance Criteria
- ✅ Docker image builds successfully
- ✅ Container runs dbt commands
- ✅ Image pushed to ECR
- ✅ No critical vulnerabilities
- ✅ CI workflow automates build/push

#### Risks & Gaps
- **Risk**: Image size too large → Mitigation: Multi-stage build, slim base image
- **Risk**: Credentials exposure → Mitigation: Use Secrets Manager, not env vars in Dockerfile
- **Gap**: No orchestration yet (next sprint)

---

### Sprint 7: AWS MWAA Environment Setup
**Duration**: Days 19-21
**Goal**: Deploy managed Airflow environment

#### Objectives
- MWAA environment operational
- Team can access Airflow UI
- Sample DAG deployed and running

#### Deliverables

**Day 1**:
- [x] Terraform module: `orchestration`
  - MWAA environment (Medium size)
  - MWAA execution role
  - Security group for MWAA
  - VPC configuration
- [x] Create MWAA S3 bucket structure:
  - `/dags/`
  - `/plugins/`
  - `/requirements.txt`
- [x] Upload requirements.txt to S3:
  ```
  apache-airflow-providers-amazon==8.13.0
  astronomer-cosmos==1.4.0
  ```

**Day 2**:
- [x] Apply Terraform for MWAA (takes ~30 min)
- [x] While waiting: Create sample DAG:
  ```python
  # airflow/dags/sample_dag.py
  from airflow import DAG
  from airflow.operators.bash import BashOperator

  dag = DAG('sample_hello_world', schedule_interval='@daily')

  task = BashOperator(
      task_id='hello',
      bash_command='echo "Hello from MWAA"',
      dag=dag
  )
  ```
- [x] Sync DAG to S3: `aws s3 sync ./airflow/dags/ s3://mwaa-bucket/dags/`
- [x] Wait for MWAA to pick up DAG (5-10 min)
- [x] Configure access to Airflow UI (IAM or Apache auth)

**Day 3**:
- [x] Access Airflow UI
- [x] Trigger sample DAG manually
- [x] Verify task execution and logs
- [x] Configure SMTP for Airflow email alerts (optional)
- [x] Document MWAA access and DAG deployment process
- [x] Demo: Deploy new DAG via S3 sync, trigger in UI

#### Acceptance Criteria
- ✅ MWAA environment healthy
- ✅ Team can access Airflow UI
- ✅ Sample DAG runs successfully
- ✅ DAGs auto-sync from S3
- ✅ CloudWatch logs show DAG execution

#### Risks & Gaps
- **Risk**: MWAA expensive (~$700/month) → Mitigation: Right-size for workload
- **Risk**: DAG sync delay → Mitigation: Document sync frequency (5 min)
- **Gap**: No Cosmos integration yet (next sprint)

---

### Sprint 8: Airflow-dbt Integration with Cosmos
**Duration**: Days 22-24
**Goal**: Orchestrate dbt via Airflow using Cosmos

#### Objectives
- Cosmos library configured
- Airflow triggers ECS tasks running dbt
- End-to-end pipeline functional

#### Deliverables

**Day 1**:
- [x] Update MWAA requirements.txt with Cosmos:
  ```
  astronomer-cosmos==1.4.0
  dbt-redshift==1.7.1
  ```
- [x] Sync updated requirements to S3
- [x] Wait for MWAA to update environment (15-20 min)
- [x] Create IAM policy: MWAA → ECS RunTask
- [x] Attach policy to MWAA execution role
- [x] Create IAM role: dbt-task-execution-role (ECR pull, CloudWatch logs)
- [x] Create IAM role: dbt-task-role (S3 access, Redshift connection)

**Day 2**:
- [x] Terraform module: `compute`
  - ECS cluster: `dbt-cluster`
  - ECS task definition: `dbt-transformation-task`
  - CloudWatch log group: `/ecs/dbt-transformation`
- [x] Configure task definition:
  - Image: ECR dbt-project:latest
  - CPU: 2048, Memory: 4096
  - Secrets from Secrets Manager
  - Environment: DBT_TARGET=dev
- [x] Apply Terraform for ECS
- [x] Test ECS task manually:
  ```bash
  aws ecs run-task \
    --cluster dbt-cluster \
    --task-definition dbt-transformation-task \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[...],securityGroups=[...],assignPublicIp=DISABLED}"
  ```

**Day 3**:
- [x] Create Airflow DAG with Cosmos:
  ```python
  from cosmos import DbtTaskGroup, ProjectConfig, ProfileConfig
  from airflow import DAG

  dag = DAG('dbt_transform_daily', schedule_interval='@daily')

  dbt_tg = DbtTaskGroup(
      group_id='dbt_transform',
      project_config=ProjectConfig('/usr/app/dbt'),
      profile_config=ProfileConfig(
          profile_name='data_platform',
          target_name='dev'
      ),
      operator_args={
          'execution_mode': 'ecs',
          'cluster': 'dbt-cluster',
          'task_definition': 'dbt-transformation-task',
          'launch_type': 'FARGATE',
          'network_configuration': {...}
      },
      dag=dag
  )
  ```
- [x] Deploy DAG to MWAA
- [x] Trigger DAG and verify ECS task execution
- [x] Check CloudWatch logs for dbt output
- [x] Verify transformed data in Redshift
- [x] Demo: End-to-end pipeline (S3 upload → EventBridge → Airflow → dbt → Redshift)

#### Acceptance Criteria
- ✅ Cosmos configured in MWAA
- ✅ Airflow triggers ECS Fargate task
- ✅ dbt runs successfully in container
- ✅ Data transformed and loaded to Redshift
- ✅ Logs available in CloudWatch

#### Risks & Gaps
- **Risk**: Cosmos config complexity → Mitigation: Start with simple example, iterate
- **Risk**: ECS task timeout → Mitigation: Set appropriate task timeout (1 hour)
- **Gap**: No EventBridge → Airflow connection yet (next phase)

---

## Phase 3: Automation & CI/CD (Sprints 9-11) - 9 Days

### Sprint 9: GitHub Actions CI/CD Pipeline
**Duration**: Days 25-27
**Goal**: Automate testing, building, and deployment

#### Objectives
- CI pipeline tests all code on PR
- CD pipeline deploys to dev on merge
- Manual approval for prod deployment

#### Deliverables

**Day 1**:
- [x] GitHub Actions workflow: `terraform-ci.yml`
  ```yaml
  on: [pull_request]
  jobs:
    terraform-validate:
      - terraform fmt -check
      - terraform validate
      - tflint
    terraform-plan:
      - terraform plan
  ```
- [x] GitHub Actions workflow: `dbt-ci.yml`
  ```yaml
  on: [pull_request]
  jobs:
    dbt-test:
      - dbt deps
      - dbt compile
      - dbt test
      - sqlfluff lint
  ```
- [x] GitHub Actions workflow: `python-ci.yml`
  ```yaml
  on: [pull_request]
  jobs:
    lint-and-test:
      - pylint airflow/
      - pytest tests/
  ```

**Day 2**:
- [x] GitHub Actions workflow: `docker-build.yml`
  ```yaml
  on:
    push:
      branches: [main, develop]
  jobs:
    build-and-push:
      - Build dbt Docker image
      - Scan with Trivy
      - Push to ECR
      - Tag with git SHA
  ```
- [x] GitHub Actions workflow: `deploy-dev.yml`
  ```yaml
  on:
    push:
      branches: [develop]
  jobs:
    deploy-infrastructure:
      - terraform apply -auto-approve (dev)
    deploy-application:
      - Sync DAGs to S3
      - Update ECS task definition
  ```
- [x] Configure GitHub OIDC provider in AWS
- [x] Create IAM role for GitHub Actions

**Day 3**:
- [x] Test CI pipeline: Create PR with failing test
- [x] Test CD pipeline: Merge to develop, verify auto-deploy
- [x] Configure branch protection rules (require checks to pass)
- [x] Document CI/CD workflows
- [x] Demo: End-to-end CI/CD (PR → review → merge → auto-deploy)
- [x] **Milestone Release 2**: Full CI/CD operational

#### Acceptance Criteria
- ✅ All PRs trigger CI checks
- ✅ Merge to develop auto-deploys to dev
- ✅ Failed checks block merge
- ✅ GitHub Actions use OIDC (no long-lived credentials)
- ✅ Deployment history visible in GitHub

#### Risks & Gaps
- **Risk**: GitHub Actions costs → Mitigation: Use caching, optimize workflows
- **Risk**: Terraform drift → Mitigation: Daily drift detection workflow
- **Gap**: No prod deployment yet (needs manual approval workflow)

---

### Sprint 10: Event-Driven Pipeline (S3 → EventBridge → Airflow)
**Duration**: Days 28-30
**Goal**: Automate pipeline triggering on S3 file uploads

#### Objectives
- S3 events trigger Airflow DAGs
- Data processing fully automated
- Monitoring captures all events

#### Deliverables

**Day 1**:
- [x] Terraform: EventBridge rule for S3 events
  ```hcl
  resource "aws_cloudwatch_event_rule" "s3_upload" {
    name        = "s3-landing-upload"
    description = "Trigger on S3 upload to landing zone"
    event_pattern = jsonencode({
      source      = ["aws.s3"]
      detail-type = ["Object Created"]
      detail = {
        bucket = { name = ["${var.raw_data_bucket}"] }
        object = { key = [{ prefix = "landing/" }] }
      }
    })
  }
  ```
- [x] Terraform: EventBridge target → MWAA
  ```hcl
  resource "aws_cloudwatch_event_target" "mwaa" {
    rule      = aws_cloudwatch_event_rule.s3_upload.name
    arn       = aws_mwaa_environment.main.arn
    role_arn  = aws_iam_role.eventbridge_mwaa.arn
    input     = jsonencode({
      dag_name = "data_ingestion_pipeline"
      conf     = {
        s3_key   = "$.detail.object.key"
        s3_bucket = "$.detail.bucket.name"
      }
    })
  }
  ```
- [x] Create IAM role: eventbridge → trigger MWAA

**Day 2**:
- [x] Update Airflow DAG to accept S3 key parameter:
  ```python
  def process_s3_file(s3_key, **context):
      # Process file from S3
      pass

  dag = DAG('data_ingestion_pipeline', schedule_interval=None)

  task = PythonOperator(
      task_id='process',
      python_callable=process_s3_file,
      op_kwargs={'s3_key': '{{ dag_run.conf.s3_key }}'}
  )
  ```
- [x] Deploy updated DAG
- [x] Test: Upload file to S3, verify DAG triggers
- [x] Add error handling and retries

**Day 3**:
- [x] Create validation step in DAG (file format, schema check)
- [x] Move validated files from /landing/ to /raw/
- [x] Archive original files
- [x] Add CloudWatch metrics (files processed per hour)
- [x] Demo: Drop file into S3, watch automated pipeline execute
- [x] **Milestone Release 3**: Event-driven pipeline complete

#### Acceptance Criteria
- ✅ S3 upload triggers EventBridge rule
- ✅ EventBridge triggers Airflow DAG
- ✅ DAG processes file automatically
- ✅ File moved to /raw/ after validation
- ✅ Failures logged and alerted

#### Risks & Gaps
- **Risk**: Event storm (many files uploaded) → Mitigation: Rate limiting, DAG concurrency limits
- **Risk**: Failed validation blocks pipeline → Mitigation: Dead letter queue for bad files
- **Gap**: No schema evolution handling (addressed in backlog)

---

### Sprint 11: Production Environment Provisioning
**Duration**: Days 31-33
**Goal**: Create production-ready environment with HA and security

#### Objectives
- Prod environment fully provisioned
- Security hardening complete
- Separate from dev environment

#### Deliverables

**Day 1**:
- [x] Create Terraform workspace/directory: `terraform/environments/prod`
- [x] Copy and adapt dev configuration for prod:
  - Larger instance sizes (Redshift: ra3.xlplus, MWAA: Large)
  - Multi-AZ for all services
  - Enhanced monitoring
  - Backup/retention policies
- [x] Update dbt profiles for prod target
- [x] Create prod-specific IAM roles (separate from dev)
- [x] Enable Redshift automated snapshots (cross-region)

**Day 2**:
- [x] Apply Terraform for prod (requires approval in GitHub Actions)
- [x] While provisioning: Security hardening
  - Enable AWS GuardDuty
  - Configure AWS Config rules
  - S3 bucket: block public access
  - Redshift: Enhanced VPC routing
  - MWAA: Private webserver access (VPN required)
- [x] Create bastion host for secure Redshift access
- [x] Configure VPN or AWS Client VPN
- [x] Secrets rotation policy (Secrets Manager)

**Day 3**:
- [x] Smoke test prod environment:
  - Upload sample file to prod S3
  - Verify EventBridge triggers
  - Check dbt runs in prod profile
  - Validate data in prod Redshift
- [x] Document prod access procedures
- [x] Create runbook for prod operations
- [x] Set up prod deployment approval workflow
- [x] Demo: Show prod environment, explain HA setup

#### Acceptance Criteria
- ✅ Prod environment provisioned and healthy
- ✅ Multi-AZ redundancy configured
- ✅ Security hardening complete
- ✅ Prod credentials in Secrets Manager
- ✅ Smoke tests pass

#### Risks & Gaps
- **Risk**: Cost shock (~$2500/month prod) → Mitigation: Budget alerts, cost optimization
- **Risk**: Insufficient access controls → Mitigation: Principle of least privilege review
- **Gap**: No disaster recovery tested yet (next phase)

---

## Phase 4: Monitoring & Optimization (Sprints 12-14) - 9 Days

### Sprint 12: CloudWatch Monitoring & Alerting
**Duration**: Days 34-36
**Goal**: Comprehensive observability and proactive alerting

#### Objectives
- All services send logs to CloudWatch
- Critical metrics monitored
- SNS alerts configured for failures

#### Deliverables

**Day 1**:
- [x] Terraform module: `monitoring`
  - CloudWatch log groups for all services
  - Log retention policies (7 days dev, 30 days prod)
  - Metric filters for error patterns
  - Custom metrics dashboard
- [x] Configure CloudWatch Logs:
  - `/aws/mwaa/{env}` - Airflow logs
  - `/ecs/dbt-transformation` - dbt logs
  - `/aws/redshift/cluster/{cluster}` - Redshift logs
  - `/aws/lambda/data-validation` - Lambda logs (if used)

**Day 2**:
- [x] Create CloudWatch alarms:
  1. **DAG Failure Alarm**:
     - Metric: DAG run state = failed
     - Threshold: 1 failure
     - Action: SNS notification
  2. **ECS Task Failed**:
     - Metric: ECS task stopped with error
     - Threshold: 1 failure
     - Action: SNS notification
  3. **Redshift Disk Space**:
     - Metric: Disk usage > 80%
     - Threshold: 80%
     - Action: SNS warning
  4. **High Error Rate**:
     - Metric: Error log count > 10 in 5 min
     - Action: SNS notification
- [x] Create SNS topic: `data-pipeline-alerts-{env}`
- [x] Subscribe team emails to SNS topic
- [x] Test alarms (intentionally trigger failure)

**Day 3**:
- [x] Create CloudWatch dashboard:
  - Pipeline execution timeline
  - ECS task success/failure rate
  - Redshift query performance (WLM)
  - S3 storage growth trend
  - Cost breakdown by service
- [x] Set up CloudWatch Insights queries for common issues
- [x] Document alerting thresholds and escalation
- [x] Integrate with Slack (optional): SNS → Lambda → Slack webhook
- [x] Demo: Show dashboard, trigger test alert

#### Acceptance Criteria
- ✅ All services logging to CloudWatch
- ✅ 4+ critical alarms configured
- ✅ SNS topic sends email alerts
- ✅ Dashboard shows key metrics
- ✅ Log retention policies applied

#### Risks & Gaps
- **Risk**: Alert fatigue → Mitigation: Tune thresholds based on baselines
- **Risk**: Log costs → Mitigation: Short retention for debug logs
- **Gap**: No APM (application performance monitoring) - consider later

---

### Sprint 13: Data Quality & Testing Framework
**Duration**: Days 37-39
**Goal**: Robust data quality checks and automated testing

#### Objectives
- Data quality tests in dbt expanded
- Custom data validation framework
- Automated data anomaly detection

#### Deliverables

**Day 1**:
- [x] Expand dbt tests:
  - Generic tests (unique, not_null, accepted_values)
  - Relationship tests (foreign keys)
  - Custom tests (business logic validation)
  - Schema tests (column types, nullability)
- [x] Create dbt macros for common validations:
  - `test_row_count_threshold.sql`
  - `test_freshness_threshold.sql`
  - `test_percent_null_threshold.sql`
- [x] Add tests to all critical models (100% coverage for marts)

**Day 2**:
- [x] Create Python data validation framework:
  ```python
  # scripts/data_validation.py
  class DataValidator:
      def check_row_count_anomaly(table, threshold=0.2):
          # Compare with historical averages
          pass

      def check_schema_drift(table, expected_schema):
          # Validate schema hasn't changed
          pass

      def check_data_freshness(table, max_age_hours=24):
          # Ensure data is recent
          pass
  ```
- [x] Integrate validation into Airflow DAG:
  ```python
  validate_task = PythonOperator(
      task_id='validate_data',
      python_callable=run_validations
  )

  dbt_task >> validate_task >> alert_task
  ```
- [x] Store validation results in `audit_schema.data_quality_checks`

**Day 3**:
- [x] Create data quality dashboard (Redshift tables → QuickSight/Metabase):
  - Test pass rate over time
  - Failed tests by model
  - Data freshness by source
- [x] Set up alerts for data quality failures
- [x] Document data quality SLAs
- [x] Demo: Show failed test, notification, dashboard update

#### Acceptance Criteria
- ✅ 50+ dbt tests defined
- ✅ All tests passing (or expected failures documented)
- ✅ Custom validation framework operational
- ✅ Data quality metrics tracked
- ✅ Failures trigger alerts

#### Risks & Gaps
- **Risk**: Over-testing slows pipeline → Mitigation: Balance coverage with performance
- **Risk**: False positives cause alert fatigue → Mitigation: Tune thresholds
- **Gap**: No ML-based anomaly detection (future enhancement)

---

### Sprint 14: Documentation, Optimization & Handoff
**Duration**: Days 40-42
**Goal**: Production-ready system with comprehensive documentation

#### Objectives
- All documentation complete and up-to-date
- Performance optimized
- Team trained on operations
- Project handed off to BAU team

#### Deliverables

**Day 1**:
- [x] Performance optimization:
  - Redshift: Analyze query performance (SVL_QUERY_REPORT)
  - Redshift: Add sort/dist keys to tables
  - dbt: Optimize models (incremental vs full refresh)
  - ECS: Right-size task CPU/memory
  - MWAA: Tune worker auto-scaling
- [x] Cost optimization review:
  - S3: Verify lifecycle policies active
  - Redshift: Consider RA3 reserved instances (if long-term)
  - ECS: Evaluate Fargate Spot for non-critical tasks
- [x] Create cost dashboard (Cost Explorer API → dashboard)

**Day 2**:
- [x] Complete all documentation:
  - [x] README.md (updated)
  - [x] ARCHITECTURE.md (updated)
  - [x] TECH_LEAD_PLAYBOOK.md (updated)
  - [x] RUNBOOK.md (operational procedures)
  - [x] TROUBLESHOOTING.md (common issues and fixes)
  - [x] API.md (if exposing data via API)
- [x] Generate dbt documentation:
  ```bash
  dbt docs generate --target prod
  # Host on S3 static website
  ```
- [x] Create video tutorials:
  - Deploying new dbt model
  - Troubleshooting failed DAG
  - Adding new data source
- [x] Knowledge transfer sessions (3 x 1-hour sessions):
  - Session 1: Architecture & Infrastructure
  - Session 2: DAG Development & Deployment
  - Session 3: Monitoring & Troubleshooting

**Day 3**:
- [x] Final production smoke test:
  - Deploy sample change via CI/CD
  - Verify full pipeline execution
  - Check all monitoring/alerts
- [x] Security audit:
  - IAM permissions review
  - Secrets rotation verification
  - Access logs review
- [x] Retrospective: Full project review
  - What went well
  - What could improve
  - Lessons learned documented
- [x] Project handoff meeting with stakeholders
- [x] **Final Release**: Production system operational
- [x] Celebrate! 🎉

#### Acceptance Criteria
- ✅ All documentation complete and accurate
- ✅ Performance benchmarks met (SLAs defined)
- ✅ Team trained and confident
- ✅ Production system stable (no critical issues)
- ✅ Handoff accepted by business owners

#### Risks & Gaps
- **Risk**: Insufficient knowledge transfer → Mitigation: Record sessions, shadowing period
- **Gap**: No advanced features (ML, real-time streaming) - backlog for future

---

## Post-Sprint Backlog (Future Enhancements)

### High Priority
1. **Incremental dbt Models** (3 days)
   - Convert large fact tables to incremental
   - Implement backfill strategy
   - Test performance improvements

2. **Disaster Recovery Testing** (2 days)
   - Document DR procedures
   - Conduct DR drill
   - Measure RTO/RPO

3. **Advanced Monitoring** (3 days)
   - Data lineage tracking
   - Query performance profiling
   - Cost attribution by dataset

4. **Security Enhancements** (2 days)
   - Enable AWS CloudTrail
   - Implement data masking for PII
   - Conduct penetration testing

### Medium Priority
5. **Staging Environment** (3 days)
   - Clone prod infrastructure
   - Automated prod → staging data refresh
   - Pre-prod testing automation

6. **Schema Evolution** (3 days)
   - Handle schema changes gracefully
   - Version control for schemas
   - Backward compatibility testing

7. **Data Catalog** (3 days)
   - AWS Glue Data Catalog enrichment
   - Data dictionary in dbt docs
   - Searchable metadata

8. **Advanced Orchestration** (5 days)
   - Complex DAG dependencies
   - Dynamic DAG generation
   - SLA monitoring and alerting

### Low Priority
9. **ML Integration** (5 days)
   - SageMaker for model training
   - Feature store in Redshift
   - Batch inference pipelines

10. **Streaming Data** (5 days)
    - Kinesis Data Streams → Firehose → S3
    - Near real-time transformations
    - Lambda for streaming validation

11. **Multi-Region** (5 days)
    - Deploy to secondary region
    - Cross-region replication
    - Failover testing

12. **API Layer** (5 days)
    - API Gateway + Lambda → Redshift
    - GraphQL API for data access
    - Rate limiting and authentication

---

## Sprint Metrics & Tracking

### Velocity Tracking

| Sprint | Planned Story Points | Completed Story Points | Velocity |
|--------|---------------------|------------------------|----------|
| 1      | 13                  | 13                     | 100%     |
| 2      | 21                  | 21                     | 100%     |
| 3      | 13                  | 13                     | 100%     |
| 4      | 21                  | 21                     | 100%     |
| 5      | 21                  | TBD                    | TBD      |
| 6      | 13                  | TBD                    | TBD      |
| ...    | ...                 | ...                    | ...      |

### Risk Heatmap

| Sprint | Technical Risk | Schedule Risk | Resource Risk | Overall |
|--------|---------------|---------------|---------------|---------|
| 1      | Low           | Low           | Low           | 🟢      |
| 2      | Medium        | Low           | Low           | 🟡      |
| 3      | Low           | Low           | Low           | 🟢      |
| 4      | Medium        | Medium        | Low           | 🟡      |
| 5      | High          | Medium        | Medium        | 🟠      |
| 6      | Medium        | Low           | Low           | 🟡      |
| ...    | ...           | ...           | ...           | ...     |

### Definition of Done (DoD)

A sprint is considered "Done" when:
- ✅ All planned deliverables completed
- ✅ Code merged to main/develop branch
- ✅ Tests written and passing (>80% coverage)
- ✅ Documentation updated
- ✅ Demo conducted with stakeholders
- ✅ Retrospective completed
- ✅ Deployed to target environment (dev/staging/prod)
- ✅ Monitoring/alerting configured
- ✅ No critical bugs outstanding

---

## Communication & Ceremonies

### Daily Standup (15 min, async Slack or quick call)
- Yesterday's accomplishments
- Today's plan
- Blockers

### Sprint Planning (Day 1, 1 hour)
- Review previous sprint
- Plan next sprint tasks
- Assign ownership
- Identify dependencies

### Sprint Demo (Day 3, 1 hour)
- Show completed work to stakeholders
- Gather feedback
- Adjust backlog if needed

### Sprint Retrospective (Day 3, 1 hour)
- What went well?
- What didn't go well?
- What should we improve?
- Action items for next sprint

### Weekly Technical Review (Fridays, 1 hour)
- Architecture discussions
- Code review deep dives
- Security/compliance topics
- Knowledge sharing

---

## Success Criteria

### Technical Success
- ✅ Pipeline success rate: >99%
- ✅ Mean time to recovery: <30 min
- ✅ Data freshness: <15 min from ingestion
- ✅ Test coverage: >80%
- ✅ Deployment frequency: Daily
- ✅ Infrastructure provisioning: <1 hour

### Business Success
- ✅ Reduced manual data processing effort by 90%
- ✅ Data available for analysis within SLA
- ✅ Cost predictable and optimized
- ✅ Team self-sufficient in operations
- ✅ Scalable to 10x data volume

### Team Success
- ✅ All team members trained
- ✅ Documentation comprehensive
- ✅ On-call runbooks tested
- ✅ Positive team feedback (retrospectives)
- ✅ Skills developed (dbt, Airflow, Terraform, AWS)

---

## Appendix: Sprint Estimation

### Story Point Scale (Fibonacci)
- **1 point**: Trivial (e.g., update README)
- **3 points**: Simple (e.g., add dbt test)
- **5 points**: Moderate (e.g., create new dbt model)
- **8 points**: Complex (e.g., new Terraform module)
- **13 points**: Very complex (e.g., MWAA environment setup)
- **21 points**: Epic (e.g., entire CI/CD pipeline) - should be broken down

### Team Capacity
- Tech Lead: 50% hands-on (30 hours/sprint)
- Data Engineers (2): 100% (60 hours each)
- DevOps: 100% (60 hours)
- QA: 50% (30 hours)
- **Total**: 240 hours per 3-day sprint

### Assumptions
- No major blockers (AWS quota issues, critical bugs)
- Team available full-time (no PTO during critical sprints)
- Stakeholders responsive for approvals/feedback
- Third-party services (AWS) stable
