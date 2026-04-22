# Tech Lead Playbook

## Table of Contents

1. [Project Overview](#project-overview)
2. [Technical Stack](#technical-stack)
3. [Development Workflow](#development-workflow)
4. [Environment Strategy](#environment-strategy)
5. [Team Structure & Responsibilities](#team-structure--responsibilities)
6. [Development Standards](#development-standards)
7. [Testing Strategy](#testing-strategy)
8. [Deployment Process](#deployment-process)
9. [Monitoring & Operations](#monitoring--operations)
10. [Troubleshooting Guide](#troubleshooting-guide)
11. [Risk Management](#risk-management)
12. [Knowledge Transfer](#knowledge-transfer)

## Project Overview

### Business Value
This platform enables automated, scalable data processing with minimal operational overhead. Key benefits:
- **Reduced Time-to-Insight**: From hours to minutes for data processing
- **Cost Efficiency**: Serverless architecture scales to zero
- **Reliability**: Automated monitoring and error handling
- **Maintainability**: Infrastructure as Code enables reproducible deployments

### Success Metrics
- Pipeline success rate: >99%
- Data freshness: <15 minutes from ingestion to availability
- Deployment frequency: Daily (CI/CD)
- Mean time to recovery: <30 minutes
- Infrastructure provisioning: <1 hour for new environment

## Technical Stack

### Core Technologies

| Component | Technology | Version | Purpose |
|-----------|-----------|---------|---------|
| Orchestration | Apache Airflow (MWAA) | 2.8+ | Workflow management |
| Transformation | dbt-core | 1.7+ | Data modeling |
| Warehouse | Amazon Redshift | Latest | Analytics database |
| Container Runtime | AWS Fargate | - | Serverless compute |
| Container Registry | Amazon ECR | - | Image storage |
| IaC | Terraform | 1.6+ | Infrastructure provisioning |
| CI/CD | GitHub Actions | - | Automation |
| Monitoring | CloudWatch | - | Observability |
| Version Control | Git/GitHub | - | Code management |

### Python Dependencies
```
apache-airflow==2.8.0
astronomer-cosmos==1.4.0
dbt-core==1.7.0
dbt-redshift==1.7.0
dbt-external-tables==0.8.0
boto3==1.34.0
awscli==1.32.0
```

## Development Workflow

### Local Development Setup

#### Prerequisites
```bash
# Required tools
- Python 3.11+
- Docker Desktop
- Terraform 1.6+
- AWS CLI v2
- Git
- VSCode or PyCharm (recommended)
```

#### Initial Setup
```bash
# 1. Clone repository
git clone https://github.com/your-org/aws-data-platform.git
cd aws-data-platform

# 2. Create virtual environment
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# 3. Install dependencies
pip install -r requirements-dev.txt

# 4. Configure AWS credentials
aws configure --profile data-platform-dev

# 5. Set up pre-commit hooks
pre-commit install

# 6. Copy environment template
cp .env.example .env.local
# Edit .env.local with your dev credentials

# 7. Initialize Terraform
cd terraform/environments/dev
terraform init

# 8. Set up dbt
cd ../../../dbt
dbt deps
dbt debug --profiles-dir ./profiles --target dev
```

### Git Branching Strategy

**GitFlow Model**:
- `main`: Production-ready code
- `develop`: Integration branch for features
- `feature/*`: Individual features
- `hotfix/*`: Production bug fixes
- `release/*`: Release preparation

**Branch Naming**:
```
feature/JIRA-123-add-customer-model
hotfix/JIRA-456-fix-date-parsing
release/v1.2.0
```

**Commit Messages** (Conventional Commits):
```
feat: add customer dimension model
fix: correct date parsing in orders table
docs: update setup instructions
chore: upgrade dbt to 1.7.1
test: add unit tests for transformations
```

### Pull Request Process

1. **Create PR** with template:
   - Description of changes
   - Testing performed
   - Screenshots (if UI)
   - Checklist completion

2. **Required Checks**:
   - ✅ All tests pass
   - ✅ Code coverage >80%
   - ✅ Terraform plan succeeds
   - ✅ dbt compile succeeds
   - ✅ No security vulnerabilities
   - ✅ Code review approval (2 reviewers)

3. **Review Guidelines**:
   - Review within 24 hours
   - Focus on logic, security, performance
   - Suggest improvements, don't just approve
   - Test locally if complex changes

4. **Merge Strategy**:
   - Squash and merge (keeps history clean)
   - Delete branch after merge
   - Automated deployment to dev environment

## Environment Strategy

### Environment Tiers

| Environment | Purpose | Deployment | Data | Uptime |
|-------------|---------|------------|------|--------|
| **Local** | Developer testing | Manual | Sample/synthetic | On-demand |
| **Dev** | Integration testing | Auto (on merge to develop) | Anonymized production | 9-5 weekdays |
| **Staging** | Pre-production validation | Auto (on release branch) | Production clone | 24/7 |
| **Prod** | Production workloads | Manual approval | Real production data | 24/7 |

### Configuration Management

**Environment Variables** (stored in AWS Secrets Manager):
```
# Dev
REDSHIFT_HOST=dev-cluster.redshift.amazonaws.com
REDSHIFT_USER=dbt_dev_user
REDSHIFT_PASSWORD=<from-secrets-manager>
DBT_TARGET=dev
ENVIRONMENT=dev

# Prod
REDSHIFT_HOST=prod-cluster.redshift.amazonaws.com
REDSHIFT_USER=dbt_prod_user
REDSHIFT_PASSWORD=<from-secrets-manager>
DBT_TARGET=prod
ENVIRONMENT=prod
```

**dbt Profiles** (`profiles.yml`):
```yaml
data_platform:
  target: "{{ env_var('DBT_TARGET', 'dev') }}"

  outputs:
    dev:
      type: redshift
      host: "{{ env_var('REDSHIFT_HOST_DEV') }}"
      user: "{{ env_var('REDSHIFT_USER_DEV') }}"
      password: "{{ env_var('REDSHIFT_PASSWORD_DEV') }}"
      port: 5439
      dbname: analytics_dev
      schema: dbt_dev
      threads: 4
      keepalives_idle: 240
      search_path: public

    prod:
      type: redshift
      host: "{{ env_var('REDSHIFT_HOST_PROD') }}"
      user: "{{ env_var('REDSHIFT_USER_PROD') }}"
      password: "{{ env_var('REDSHIFT_PASSWORD_PROD') }}"
      port: 5439
      dbname: analytics_prod
      schema: analytics
      threads: 8
      keepalives_idle: 240
      search_path: public
```

## Team Structure & Responsibilities

### Roles

**Tech Lead** (You):
- Architecture decisions
- Code review and quality
- Sprint planning and estimation
- Risk management
- Stakeholder communication
- Mentoring team members

**Data Engineers** (2-3):
- dbt model development
- Airflow DAG creation
- Data quality testing
- Documentation
- Code reviews

**DevOps Engineer** (1):
- Terraform infrastructure
- CI/CD pipeline maintenance
- Monitoring and alerting setup
- Security compliance
- Deployment automation

**QA Engineer** (1, part-time):
- Test strategy
- Data validation scripts
- End-to-end testing
- Performance testing

### RACI Matrix

| Task | Tech Lead | Data Engineer | DevOps | QA |
|------|-----------|---------------|--------|-----|
| Architecture Design | **R/A** | C | C | I |
| dbt Model Development | C | **R/A** | I | C |
| Infrastructure Code | C | I | **R/A** | I |
| DAG Development | C | **R/A** | C | I |
| CI/CD Pipeline | A | I | **R** | C |
| Testing Strategy | A | C | I | **R** |
| Production Deployment | **A** | C | R | I |
| Monitoring Setup | C | I | **R/A** | I |
| Documentation | A | **R** | R | C |

*R=Responsible, A=Accountable, C=Consulted, I=Informed*

### Communication Plan

**Daily Standup** (15 min, 9:30 AM):
- What did you complete yesterday?
- What are you working on today?
- Any blockers?

**Sprint Planning** (1 hour, every 3 days):
- Review previous sprint
- Plan next sprint
- Assign tasks

**Weekly Tech Review** (1 hour, Fridays):
- Architecture discussions
- Technical debt review
- Security and compliance
- Knowledge sharing

**Bi-weekly Stakeholder Update**:
- Progress against roadmap
- Upcoming features
- Issues and risks

## Development Standards

### Code Quality Standards

**Python (Airflow DAGs)**:
- PEP 8 compliance
- Type hints for functions
- Docstrings (Google style)
- Max line length: 100
- Max function complexity: 10

**SQL (dbt models)**:
- Lowercase keywords
- 2-space indentation
- CTEs over subqueries
- Explicit column selection (no `SELECT *`)
- Comments for business logic

**Terraform**:
- Follow HashiCorp style guide
- Use modules for reusability
- Variables have descriptions
- Outputs documented
- State management best practices

### File Structure

```
aws-data-platform/
├── .github/
│   └── workflows/
│       ├── terraform-plan.yml
│       ├── terraform-apply.yml
│       ├── dbt-ci.yml
│       └── docker-build.yml
├── terraform/
│   ├── modules/
│   │   ├── networking/
│   │   ├── storage/
│   │   ├── compute/
│   │   ├── orchestration/
│   │   ├── data/
│   │   └── monitoring/
│   ├── environments/
│   │   ├── dev/
│   │   ├── staging/
│   │   └── prod/
│   └── global/
├── dbt/
│   ├── models/
│   │   ├── staging/
│   │   ├── intermediate/
│   │   ├── marts/
│   │   └── external/
│   ├── macros/
│   ├── tests/
│   ├── seeds/
│   ├── snapshots/
│   ├── profiles/
│   │   └── profiles.yml
│   ├── dbt_project.yml
│   ├── packages.yml
│   └── Dockerfile
├── airflow/
│   ├── dags/
│   │   ├── data_ingestion/
│   │   ├── transformations/
│   │   └── utilities/
│   ├── plugins/
│   ├── tests/
│   └── requirements.txt
├── scripts/
│   ├── deploy/
│   ├── setup/
│   └── utilities/
├── tests/
│   ├── integration/
│   ├── unit/
│   └── e2e/
├── docs/
│   ├── architecture/
│   ├── runbooks/
│   └── tutorials/
├── .gitignore
├── .pre-commit-config.yaml
├── requirements.txt
├── requirements-dev.txt
└── README.md
```

### Naming Conventions

**dbt Models**:
- Staging: `stg_{source}__{table}`
  - Example: `stg_salesforce__accounts`
- Intermediate: `int_{entity}_{verb}`
  - Example: `int_customers_deduped`
- Marts: `{entity}_{dim|fct}`
  - Example: `customers_dim`, `orders_fct`
- External: `ext_{source}__{table}`
  - Example: `ext_s3__raw_events`

**Airflow DAGs**:
- `{domain}_{action}_{interval}`
  - Example: `sales_transform_daily`, `customer_ingest_hourly`

**S3 Paths**:
- `s3://bucket/landing/{source}/{date}/`
- `s3://bucket/raw/{source}/{table}/{date}/`
- `s3://bucket/processed/{domain}/{table}/{date}/`

**Terraform Resources**:
- `{resource_type}_{purpose}_{environment}`
  - Example: `s3_bucket_raw_data_prod`, `iam_role_dbt_task_dev`

### Documentation Requirements

**dbt Models**:
```yaml
version: 2

models:
  - name: customers_dim
    description: Customer dimension table with demographic and profile information
    columns:
      - name: customer_id
        description: Primary key - unique identifier for customer
        tests:
          - unique
          - not_null
      - name: email
        description: Customer email address
        tests:
          - not_null
      - name: created_at
        description: Timestamp when customer record was created
```

**Airflow DAGs**:
```python
"""
Customer Data Transformation Pipeline

This DAG orchestrates the daily transformation of customer data:
1. Trigger dbt run for customer models
2. Run data quality checks
3. Send success/failure notifications

Schedule: Daily at 2 AM UTC
Owner: Data Engineering Team
SLA: 2 hours
"""

dag = DAG(
    dag_id='customer_transform_daily',
    description='Daily customer data transformation pipeline',
    # ... rest of DAG definition
)
```

**Terraform Modules**:
```hcl
/**
 * Storage Module
 *
 * Creates and configures S3 buckets for data platform
 * Includes lifecycle policies and replication setup
 *
 * Usage:
 *   module "storage" {
 *     source = "../../modules/storage"
 *     environment = "prod"
 *     project_name = "data-platform"
 *   }
 */
```

## Testing Strategy

### Test Pyramid

```
         ┌─────────────┐
         │   E2E (5%)  │  End-to-end pipeline tests
         ├─────────────┤
         │ Integration │  Component integration tests
         │    (15%)    │
         ├─────────────┤
         │             │
         │    Unit     │  Unit tests (dbt, Python)
         │    (80%)    │
         └─────────────┘
```

### dbt Tests

**Generic Tests** (built-in):
```yaml
- unique
- not_null
- accepted_values
- relationships
```

**Custom Tests** (data quality):
```sql
-- tests/assert_revenue_positive.sql
SELECT *
FROM {{ ref('orders_fct') }}
WHERE revenue < 0
```

**Testing Levels**:
1. **Source Tests**: Data freshness, row counts
2. **Staging Tests**: Unique keys, not null
3. **Intermediate Tests**: Business logic validation
4. **Mart Tests**: Referential integrity, aggregate checks

### Airflow Tests

**Unit Tests** (pytest):
```python
def test_dag_imports():
    """Test that all DAGs can be imported without errors"""
    from airflow.models import DagBag
    dag_bag = DagBag(include_examples=False)
    assert len(dag_bag.import_errors) == 0

def test_dag_schedule():
    """Test that customer DAG has correct schedule"""
    from dags.customer_transform_daily import dag
    assert dag.schedule_interval == '@daily'
```

**Integration Tests**:
```python
def test_ecs_task_execution(ecs_client):
    """Test that ECS task can be triggered from Airflow"""
    # Mock ECS run_task response
    # Verify task execution
```

### Infrastructure Tests

**Terraform Validation**:
```bash
terraform fmt -check -recursive
terraform validate
tflint
checkov --directory .
```

**Integration Tests** (Terratest):
```go
func TestS3BucketCreation(t *testing.T) {
    // Test that S3 bucket is created with correct configuration
}
```

### CI Test Gates

**On Pull Request**:
1. ✅ Linting (pylint, sqlfluff, terraform fmt)
2. ✅ Unit tests (pytest, dbt test)
3. ✅ Security scan (bandit, trivy)
4. ✅ Terraform plan
5. ✅ dbt compile

**On Merge to Develop**:
1. ✅ All PR checks
2. ✅ Integration tests
3. ✅ Deploy to dev environment
4. ✅ Run smoke tests

**On Release**:
1. ✅ All above checks
2. ✅ E2E tests in staging
3. ✅ Performance tests
4. ✅ Manual approval

## Deployment Process

### CI/CD Pipeline

**GitHub Actions Workflow**:

```yaml
# .github/workflows/deploy.yml
name: Deploy Data Platform

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
      - name: Terraform validate
      - name: dbt compile
      - name: Run linters

  test:
    needs: validate
    runs-on: ubuntu-latest
    steps:
      - name: Run unit tests
      - name: Run integration tests
      - name: Code coverage report

  build:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - name: Build dbt Docker image
      - name: Scan image for vulnerabilities
      - name: Push to ECR

  deploy-dev:
    needs: build
    if: github.ref == 'refs/heads/develop'
    runs-on: ubuntu-latest
    steps:
      - name: Terraform apply (dev)
      - name: Update ECS task definition
      - name: Sync Airflow DAGs to S3

  deploy-prod:
    needs: build
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production
    steps:
      - name: Terraform apply (prod)
      - name: Update ECS task definition
      - name: Sync Airflow DAGs to S3
      - name: Run smoke tests
```

### Deployment Checklist

**Pre-Deployment**:
- [ ] All tests passing
- [ ] Code review approved
- [ ] Security scan clean
- [ ] Terraform plan reviewed
- [ ] Deployment window scheduled
- [ ] Stakeholders notified
- [ ] Rollback plan prepared

**During Deployment**:
- [ ] Backup current state
- [ ] Apply infrastructure changes
- [ ] Deploy application changes
- [ ] Run smoke tests
- [ ] Monitor metrics/logs
- [ ] Verify data pipeline execution

**Post-Deployment**:
- [ ] Validate data quality
- [ ] Check monitoring dashboards
- [ ] Update documentation
- [ ] Close deployment ticket
- [ ] Post-mortem (if issues)

### Rollback Procedure

**Infrastructure Rollback**:
```bash
# Rollback Terraform to previous version
cd terraform/environments/prod
terraform state pull > backup.tfstate
terraform apply -var-file=previous-version.tfvars

# Rollback ECS task to previous image
aws ecs update-service \
  --cluster dbt-cluster \
  --service dbt-service \
  --task-definition dbt-task:previous-version
```

**DAG Rollback**:
```bash
# Restore previous DAGs from S3 version
aws s3 cp s3://mwaa-bucket/dags/ ./dags/ --recursive --version-id <previous-version-id>
```

## Monitoring & Operations

### Key Metrics

**Infrastructure Metrics**:
- MWAA worker CPU/memory utilization
- ECS task success/failure rate
- Redshift cluster CPU, disk space
- S3 storage size and growth rate

**Pipeline Metrics**:
- DAG success rate (target: >99%)
- Task execution duration
- Data freshness (latency from ingestion)
- dbt model execution time

**Data Quality Metrics**:
- dbt test pass rate (target: 100%)
- Row count anomalies
- Null rate in critical columns
- Duplicate records detected

### Dashboards

**CloudWatch Dashboard** (Real-time):
- ECS task status
- Redshift query performance
- Error count by service
- S3 event processing rate

**Custom Dashboard** (Grafana/QuickSight):
- Pipeline execution timeline
- Data lineage visualization
- Cost breakdown by service
- SLA compliance tracking

### Alerting Rules

**Critical (Page immediately)**:
- Pipeline failed 3 consecutive runs
- Redshift cluster unavailable
- S3 bucket access denied
- ECS task unable to pull image

**High (Notify within 15 min)**:
- Single pipeline failure
- dbt test failure rate >5%
- Task execution time >2x baseline
- CloudWatch log errors >threshold

**Medium (Notify within 1 hour)**:
- S3 storage growth >20% week-over-week
- Redshift disk space >80%
- Terraform state lock held >1 hour

**Low (Daily digest)**:
- Cost anomaly detection
- Unused resources identified
- Security patches available

### On-Call Runbook

**Incident Response Process**:
1. **Acknowledge** alert within 5 minutes
2. **Assess** impact and severity
3. **Communicate** to stakeholders
4. **Investigate** root cause
5. **Mitigate** or rollback
6. **Resolve** and verify
7. **Document** in post-mortem

**Common Issues**:

**Issue**: DAG fails to trigger
- Check: EventBridge rule enabled
- Check: MWAA environment healthy
- Check: IAM permissions for trigger
- Fix: Re-enable rule or restart environment

**Issue**: dbt run fails
- Check: Redshift cluster status
- Check: ECS task logs in CloudWatch
- Check: Secrets Manager credentials
- Fix: Restart task or update credentials

**Issue**: Terraform apply fails
- Check: State lock in DynamoDB
- Check: AWS service quotas
- Check: IAM permissions
- Fix: Release lock or request quota increase

## Risk Management

### Risk Register

| Risk | Probability | Impact | Mitigation | Owner |
|------|-------------|--------|------------|-------|
| Data loss during migration | Low | High | S3 versioning, backups | DevOps |
| Cost overrun | Medium | Medium | Budget alerts, resource tagging | Tech Lead |
| Security breach | Low | High | Least privilege IAM, encryption | DevOps |
| Skill gap in team | Medium | Medium | Training, documentation | Tech Lead |
| Vendor lock-in (AWS) | High | Medium | Use open standards (dbt, Airflow) | Tech Lead |
| Pipeline downtime | Medium | High | HA setup, monitoring | Data Eng |
| Data quality issues | High | Medium | Comprehensive testing, validation | QA |

### Contingency Plans

**Plan A**: Nominal execution
**Plan B**: Performance degradation, scale up resources
**Plan C**: Service outage, failover to backup region
**Plan D**: Complete failure, restore from backups

## Knowledge Transfer

### Onboarding Checklist (New Team Member)

**Week 1: Environment Setup**
- [ ] Access to GitHub repository
- [ ] AWS account with appropriate permissions
- [ ] Local development environment configured
- [ ] Successfully run dbt locally
- [ ] Review architecture documentation

**Week 2: Shadow & Learn**
- [ ] Shadow senior engineer on DAG development
- [ ] Review existing dbt models
- [ ] Understand CI/CD pipeline
- [ ] Participate in code review
- [ ] Complete Terraform tutorial

**Week 3: First Contribution**
- [ ] Pick up first ticket (starter task)
- [ ] Implement solution with mentorship
- [ ] Create pull request
- [ ] Deploy to dev environment
- [ ] Present work in team meeting

**Month 2-3: Independent Work**
- [ ] Own end-to-end feature development
- [ ] Participate in on-call rotation
- [ ] Contribute to documentation
- [ ] Mentor new team members

### Training Resources

**Internal**:
- This playbook
- Architecture diagrams
- Recorded demo sessions
- Internal wiki

**External**:
- [dbt Learn](https://courses.getdbt.com/)
- [Astronomer Airflow Academy](https://academy.astronomer.io/)
- [AWS Training - Data Analytics](https://aws.amazon.com/training/learn-about/data-analytics/)
- [Terraform Associate Certification](https://www.hashicorp.com/certification/terraform-associate)

## Best Practices Summary

### Do's ✅
- Write comprehensive tests before code
- Use infrastructure as code for all resources
- Implement monitoring from day one
- Document architectural decisions (ADRs)
- Version all artifacts (code, infrastructure, data)
- Automate repetitive tasks
- Follow principle of least privilege
- Encrypt sensitive data at rest and in transit
- Use git branching strategy consistently
- Conduct regular code reviews

### Don'ts ❌
- Don't commit secrets to version control
- Don't skip testing in CI/CD
- Don't manually modify production infrastructure
- Don't use production data in dev/staging without anonymization
- Don't deploy on Fridays (unless critical)
- Don't bypass code review process
- Don't ignore CloudWatch alarms
- Don't hardcode environment-specific values
- Don't use `SELECT *` in dbt models
- Don't ignore technical debt

## Appendix

### Useful Commands

**Terraform**:
```bash
# Initialize and plan
terraform init
terraform plan -out=tfplan

# Apply with approval
terraform apply tfplan

# Show current state
terraform show

# Destroy resources
terraform destroy
```

**dbt**:
```bash
# Install dependencies
dbt deps

# Compile models
dbt compile --profiles-dir ./profiles --target dev

# Run models
dbt run --profiles-dir ./profiles --target dev --select customers_dim

# Test models
dbt test --profiles-dir ./profiles --target dev

# Generate documentation
dbt docs generate
dbt docs serve
```

**AWS CLI**:
```bash
# Sync DAGs to MWAA
aws s3 sync ./airflow/dags/ s3://mwaa-bucket/dags/

# Trigger ECS task
aws ecs run-task \
  --cluster dbt-cluster \
  --task-definition dbt-task \
  --launch-type FARGATE

# Check Redshift cluster status
aws redshift describe-clusters --cluster-identifier data-platform-prod
```

**Docker**:
```bash
# Build dbt image
docker build -t dbt-project:latest ./dbt

# Test locally
docker run -e DBT_TARGET=dev dbt-project:latest dbt run

# Push to ECR
aws ecr get-login-password | docker login --username AWS --password-stdin <ecr-url>
docker tag dbt-project:latest <ecr-url>/dbt-project:latest
docker push <ecr-url>/dbt-project:latest
```

### Contact & Escalation

**Team**:
- Tech Lead: [Name] - [Email] - [Slack]
- DevOps Lead: [Name] - [Email] - [Slack]
- Data Engineering Lead: [Name] - [Email] - [Slack]

**Escalation Path**:
1. Team Lead (respond within 15 min)
2. Engineering Manager (respond within 30 min)
3. VP Engineering (respond within 1 hour)

**External Support**:
- AWS Support: [Account support link]
- GitHub Support: support@github.com
- dbt Community: community.getdbt.com
