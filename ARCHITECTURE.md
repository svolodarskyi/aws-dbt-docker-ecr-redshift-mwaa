# Architecture Design

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              AWS Cloud                                   │
│                                                                          │
│  ┌──────────────┐                                                       │
│  │   GitHub     │                                                       │
│  │  Repository  │                                                       │
│  └──────┬───────┘                                                       │
│         │                                                               │
│         │ (Push/PR)                                                     │
│         ▼                                                               │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    CI/CD Pipeline                                 │  │
│  │  ┌────────────┐  ┌────────────┐  ┌──────────────┐                │  │
│  │  │  GitHub    │→ │ CodeBuild  │→ │    ECR       │                │  │
│  │  │  Actions   │  │            │  │  (dbt image) │                │  │
│  │  └────────────┘  └────────────┘  └──────────────┘                │  │
│  │                                                                    │  │
│  │  ┌────────────┐                                                   │  │
│  │  │ Terraform  │→ Provision Infrastructure                        │  │
│  │  │   Apply    │                                                   │  │
│  │  └────────────┘                                                   │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                      Storage Layer                                │  │
│  │                                                                    │  │
│  │  ┌──────────────┐         ┌──────────────┐                       │  │
│  │  │  S3 Bucket   │         │  S3 Bucket   │                       │  │
│  │  │  (Raw Data)  │         │(Terraform St)│                       │  │
│  │  │              │         │              │                       │  │
│  │  │  Landing/    │         │  State Files │                       │  │
│  │  │  Raw/        │         └──────────────┘                       │  │
│  │  │  Processed/  │                                                 │  │
│  │  └──────┬───────┘         ┌──────────────┐                       │  │
│  │         │                 │  DynamoDB    │                       │  │
│  │         │ (Event)         │(State Locks) │                       │  │
│  │         │                 └──────────────┘                       │  │
│  └─────────┼──────────────────────────────────────────────────────┘  │
│            │                                                           │
│            ▼                                                           │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │               Orchestration Layer (MWAA)                          │  │
│  │                                                                    │  │
│  │  ┌─────────────────────────────────────────────────────────────┐ │  │
│  │  │  Apache Airflow (Managed)                                   │ │  │
│  │  │                                                              │ │  │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │ │  │
│  │  │  │EventBridge   │→ │   DAGs       │→ │   Cosmos     │      │ │  │
│  │  │  │   Trigger    │  │              │  │   Operator   │      │ │  │
│  │  │  └──────────────┘  └──────────────┘  └──────┬───────┘      │ │  │
│  │  │                                              │              │ │  │
│  │  └──────────────────────────────────────────────┼──────────────┘ │  │
│  └─────────────────────────────────────────────────┼────────────────┘  │
│                                                     │                   │
│                                                     ▼                   │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │              Compute Layer (ECS/Fargate)                          │  │
│  │                                                                    │  │
│  │  ┌─────────────────────────────────────────────────────────────┐ │  │
│  │  │  ECS Cluster                                                 │ │  │
│  │  │                                                              │ │  │
│  │  │  ┌──────────────────────────────────────────────────────┐   │ │  │
│  │  │  │  Fargate Task (dbt Container)                        │   │ │  │
│  │  │  │                                                       │   │ │  │
│  │  │  │  ┌─────────┐  ┌─────────┐  ┌─────────┐             │   │ │  │
│  │  │  │  │dbt deps │→ │dbt seed │→ │dbt run  │             │   │ │  │
│  │  │  │  └─────────┘  └─────────┘  └─────────┘             │   │ │  │
│  │  │  │                                                       │   │ │  │
│  │  │  │  Environment: PROD Profile                           │   │ │  │
│  │  │  └──────────────────────────────────────────────────────┘   │ │  │
│  │  │                                                              │ │  │
│  │  └─────────────────────────────────────────────────────────────┘ │  │
│  └─────────────────────────────────┬────────────────────────────────┘  │
│                                    │                                   │
│                                    │ (Read S3 External Tables)         │
│                                    │ (Write Transformed Data)          │
│                                    ▼                                   │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │              Data Warehouse Layer                                 │  │
│  │                                                                    │  │
│  │  ┌─────────────────────────────────────────────────────────────┐ │  │
│  │  │  Amazon Redshift Spectrum                                   │ │  │
│  │  │                                                              │ │  │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │ │  │
│  │  │  │  External    │  │  Staging     │  │  Analytics   │      │ │  │
│  │  │  │  Tables      │→ │  Tables      │→ │  Tables      │      │ │  │
│  │  │  │  (S3 Data)   │  │              │  │              │      │ │  │
│  │  │  └──────────────┘  └──────────────┘  └──────────────┘      │ │  │
│  │  │                                                              │ │  │
│  │  └─────────────────────────────────────────────────────────────┘ │  │
│  └────────────────────────────────────────────────────────────────────┘│
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │              Monitoring & Alerting Layer                          │  │
│  │                                                                    │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │  │
│  │  │ CloudWatch  │→ │ CloudWatch  │→ │     SNS     │→ Email        │  │
│  │  │    Logs     │  │   Alarms    │  │    Topic    │               │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘               │  │
│  │                                                                    │  │
│  └────────────────────────────────────────────────────────────────────┘│
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

## Data Flow

1. **Data Ingestion**: Files dropped into S3 landing zone
2. **Manual Trigger**: User triggers Airflow DAG manually via MWAA UI or CLI
3. **Orchestration**: Airflow DAG activated, Cosmos operator prepares dbt task
4. **Transformation**: ECS Fargate task runs dbt container
   - dbt creates external tables pointing to S3
   - Transforms data using SQL models
   - Writes results to Redshift Spectrum
5. **Monitoring**: CloudWatch captures logs/metrics → SNS sends alerts on failures

**Note**: Event-driven triggers (S3 → EventBridge → Airflow) can be added later as an enhancement.

## Component Details

### 1. S3 Buckets

**Raw Data Bucket** (`{project}-raw-data-{env}`)
- **Structure**:
  - `/landing/` - Raw incoming files
  - `/raw/` - Validated files
  - `/processed/` - Post-transformation files
  - `/archive/` - Historical data
- **Lifecycle Policies**:
  - Landing → IA after 30 days
  - Processed → Glacier after 90 days
  - Archive → Deep Archive after 180 days
- **Versioning**: Enabled
- **Encryption**: SSE-S3 (or SSE-KMS for sensitive data)

**Terraform State Bucket** (`{project}-terraform-state-{env}`)
- **Structure**:
  - `/env/{environment}/terraform.tfstate`
- **Versioning**: Enabled (required)
- **Encryption**: SSE-S3
- **Access**: Restricted to CI/CD role only

**MWAA Bucket** (`{project}-mwaa-{env}`)
- **Structure**:
  - `/dags/` - Airflow DAGs
  - `/plugins/` - Custom plugins
  - `/requirements.txt` - Python dependencies
- **Versioning**: Enabled

**dbt Artifacts Bucket** (`{project}-dbt-artifacts-{env}`)
- **Structure**:
  - `/target/` - Compiled models
  - `/logs/` - dbt run logs
  - `/docs/` - Generated documentation

### 2. Amazon MWAA (Managed Airflow)

**Configuration**:
- **Environment Size**: Medium (recommended for production)
- **Airflow Version**: 2.8+ (supports Cosmos)
- **Python Version**: 3.11
- **Scheduler Count**: 2 (HA)
- **Min Workers**: 1
- **Max Workers**: 10 (auto-scaling)
- **Webserver Access**: Private network (VPN/bastion for access)

**Dependencies** (`requirements.txt`):
```
apache-airflow-providers-amazon==8.13.0
astronomer-cosmos==1.4.0
dbt-redshift==1.7.0
boto3==1.34.0
```

**Network**:
- VPC with private subnets (multi-AZ)
- VPC endpoints for S3, ECR, ECS (reduce NAT costs)
- Security groups allow only necessary traffic

### 3. Amazon ECS/Fargate

**ECS Cluster** (`{project}-dbt-cluster`)

**Task Definition**:
```json
{
  "family": "dbt-transformation-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "2048",
  "memory": "4096",
  "executionRoleArn": "arn:aws:iam::ACCOUNT:role/dbt-task-execution-role",
  "taskRoleArn": "arn:aws:iam::ACCOUNT:role/dbt-task-role",
  "containerDefinitions": [
    {
      "name": "dbt-container",
      "image": "ACCOUNT.dkr.ecr.REGION.amazonaws.com/dbt-project:latest",
      "environment": [
        {"name": "DBT_PROFILES_DIR", "value": "/usr/app/profiles"},
        {"name": "DBT_TARGET", "value": "prod"}
      ],
      "secrets": [
        {"name": "REDSHIFT_PASSWORD", "valueFrom": "arn:aws:secretsmanager:..."}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/dbt-transformation",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "dbt"
        }
      }
    }
  ]
}
```

**Container Image** (ECR):
- Base: Python 3.11-slim
- Includes: dbt-core, dbt-redshift, dbt-external-tables
- Multi-stage build for optimization
- Scanned for vulnerabilities

### 4. Amazon Redshift Spectrum

**Cluster Configuration**:
- **Node Type**: ra3.xlplus (recommended for Spectrum)
- **Nodes**: 2+ (multi-node for HA)
- **Enhanced VPC Routing**: Enabled
- **Encryption**: At-rest and in-transit
- **Backup**: Automated snapshots, 7-day retention

**External Schema** (dbt-external-tables):
```sql
CREATE EXTERNAL SCHEMA raw_data
FROM DATA CATALOG
DATABASE 'raw_data_db'
IAM_ROLE 'arn:aws:iam::ACCOUNT:role/redshift-spectrum-role'
CREATE EXTERNAL DATABASE IF NOT EXISTS;
```

**Database Structure**:
- `raw_schema`: External tables (S3 data)
- `staging_schema`: Intermediate transformations
- `analytics_schema`: Final analytical models
- `audit_schema`: Metadata and lineage tracking

### 5. Terraform Infrastructure

**State Management**:
- S3 backend with encryption
- DynamoDB for state locking
- Separate state files per environment

**Backend Configuration**:
```hcl
terraform {
  backend "s3" {
    bucket         = "project-terraform-state-prod"
    key            = "env/prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-locks"
  }
}
```

**Modules**:
- `modules/networking`: VPC, subnets, security groups
- `modules/storage`: S3 buckets, lifecycle policies
- `modules/compute`: ECS cluster, task definitions
- `modules/orchestration`: MWAA environment
- `modules/data`: Redshift cluster, Glue catalog
- `modules/cicd`: CodePipeline, CodeBuild
- `modules/monitoring`: CloudWatch, SNS

### 6. CI/CD Pipeline

**GitHub Actions Only** (Terraform + Docker):
```yaml
Stages:
1. Validate: terraform validate, fmt check (on PR)
2. Plan: terraform plan (on PR)
3. Build: Docker build dbt image (on merge)
4. Test: dbt compile, dbt test (on dev profile)
5. Push: ECR push (on merge to develop/main)
6. Deploy: terraform apply, ECS task update, sync DAGs to S3
```

**Deployment Triggers**:
- Merge to `develop` → Auto-deploy to DEV
- Merge to `main` → Manual approval → Deploy to PROD

### 7. Monitoring & Alerting

**CloudWatch Log Groups**:
- `/aws/mwaa/{environment-name}` - Airflow logs
- `/ecs/dbt-transformation` - dbt container logs
- `/aws/redshift/cluster/{cluster-name}` - Redshift logs

**CloudWatch Metrics**:
- ECS task failures
- MWAA DAG success/failure rate
- Redshift query performance
- S3 event processing latency

**CloudWatch Alarms**:
1. **DAG Failure**: Trigger on task failure
2. **ECS Task Failed**: Trigger on stopped tasks with errors
3. **Redshift Connection**: Trigger on connection issues
4. **High Error Rate**: Trigger on log error patterns

**SNS Topic** (`data-pipeline-alerts`):
- Email subscriptions for team
- Integration with Slack/PagerDuty (optional)

## IAM Roles & Permissions

### 1. Terraform Execution Role
**Role Name**: `terraform-execution-role`

**Trust Policy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:sub": "repo:ORG/REPO:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

**Permissions**:
- S3: Full access to Terraform state bucket
- DynamoDB: Read/Write to state lock table
- IAM: Create/manage service roles
- VPC, EC2: Network resource management
- MWAA: Environment creation/management
- ECS, ECR: Container services management
- Redshift: Cluster management
- CloudWatch: Monitoring setup
- Secrets Manager: Secret management

### 2. MWAA Execution Role
**Role Name**: `mwaa-execution-role`

**Trust Policy**: MWAA service

**Permissions**:
- S3: Read DAGs bucket, read/write data buckets
- ECS: RunTask on dbt cluster
- IAM: PassRole for ECS task role
- CloudWatch: Write logs
- ECR: Pull dbt images
- EventBridge: Receive events

**Policy Example**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:RunTask",
        "ecs:DescribeTasks"
      ],
      "Resource": "*",
      "Condition": {
        "ArnEquals": {
          "ecs:cluster": "arn:aws:ecs:REGION:ACCOUNT:cluster/dbt-cluster"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": [
        "arn:aws:iam::ACCOUNT:role/dbt-task-execution-role",
        "arn:aws:iam::ACCOUNT:role/dbt-task-role"
      ]
    }
  ]
}
```

### 3. ECS Task Execution Role
**Role Name**: `dbt-task-execution-role`

**Trust Policy**: ECS Tasks service

**Permissions**:
- ECR: Pull images from registry
- CloudWatch: Create log groups, put log events
- Secrets Manager: Get secret values (Redshift credentials)

### 4. ECS Task Role
**Role Name**: `dbt-task-role`

**Trust Policy**: ECS Tasks service

**Permissions**:
- S3: Read raw data bucket, write processed data
- Redshift: Connect, query, create tables
- Glue: Access Data Catalog (for external tables)
- CloudWatch: Put custom metrics

**Policy Example**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::project-raw-data-prod",
        "arn:aws:s3:::project-raw-data-prod/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::project-raw-data-prod/processed/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "glue:GetDatabase",
        "glue:GetTable",
        "glue:CreateTable",
        "glue:UpdateTable"
      ],
      "Resource": "*"
    }
  ]
}
```

### 5. Redshift Spectrum Role
**Role Name**: `redshift-spectrum-role`

**Trust Policy**: Redshift service

**Permissions**:
- S3: Read access to raw data bucket
- Glue: Access to Data Catalog

**Policy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::project-raw-data-prod",
        "arn:aws:s3:::project-raw-data-prod/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "glue:GetDatabase",
        "glue:GetTable",
        "glue:GetPartitions"
      ],
      "Resource": "*"
    }
  ]
}
```

### 6. CloudWatch Events Role
**Role Name**: `eventbridge-trigger-role`

**Trust Policy**: Events service

**Permissions**:
- MWAA: Trigger DAG execution

## Security Best Practices

1. **Least Privilege**: Each role has minimum required permissions
2. **Encryption**:
   - At-rest: All S3 buckets, Redshift, EBS volumes
   - In-transit: TLS for all connections
3. **Secrets Management**: Secrets Manager for credentials (not environment variables)
4. **Network Security**:
   - Private subnets for compute resources
   - VPC endpoints to avoid public internet
   - Security groups with minimal ingress rules
5. **Auditing**: CloudTrail enabled for all API calls
6. **MFA**: Required for console access to production
7. **Resource Tagging**: Consistent tagging for cost allocation and governance
8. **Backup**: Automated backups for Redshift, versioning for S3

## Cost Optimization

1. **MWAA**: Use minimum viable worker count, auto-scaling
2. **ECS**: Fargate Spot for non-critical workloads
3. **Redshift**: Pause during off-hours (if applicable), use RA3 nodes with managed storage
4. **S3**: Lifecycle policies to move to cheaper storage classes
5. **VPC Endpoints**: Reduce NAT gateway data transfer costs
6. **CloudWatch**: Log retention policies (7-30 days)
7. **Reserved Capacity**: Consider RIs for predictable workloads

## Disaster Recovery

- **RTO**: 4 hours
- **RPO**: 1 hour
- **Backup Strategy**:
  - Redshift: Automated snapshots, cross-region copy
  - S3: Cross-region replication for critical data
  - Terraform state: Versioning enabled
- **Recovery Plan**:
  1. Restore Terraform state from backup
  2. Re-apply infrastructure in DR region
  3. Restore Redshift from snapshot
  4. Sync S3 data from replica
  5. Deploy latest dbt container
  6. Validate data integrity
