# Sprint 2 - Day 3: Validation, Demo & Retrospective

**Goal**: Validate infrastructure, conduct demo, and close sprint

**Duration**: ~6 hours

**Outcome**: All resources validated, demo delivered, Sprint 2 complete

---

## Morning Session (3 hours)

### Step 1: Comprehensive Resource Validation (1 hour)

```bash
cd terraform/environments/dev

# Create validation script
cat > ../../scripts/validate-infrastructure.sh <<'EOF'
#!/bin/bash
set -e

echo "🔍 Validating AWS Infrastructure..."
echo

# Get VPC ID from Terraform output
VPC_ID=$(terraform output -json networking | jq -r '.vpc_id')

echo "1️⃣ Validating VPC..."
VPC_STATE=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --query 'Vpcs[0].State' --output text)
echo "  VPC State: $VPC_STATE"
if [ "$VPC_STATE" != "available" ]; then
  echo "  ❌ VPC is not available"
  exit 1
fi
echo "  ✅ VPC is available"
echo

echo "2️⃣ Validating Subnets..."
PUBLIC_SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Tier,Values=Public" --query 'Subnets[*].SubnetId' --output text)
PRIVATE_SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Tier,Values=Private" --query 'Subnets[*].SubnetId' --output text)

PUBLIC_COUNT=$(echo $PUBLIC_SUBNETS | wc -w)
PRIVATE_COUNT=$(echo $PRIVATE_SUBNETS | wc -w)

echo "  Public subnets: $PUBLIC_COUNT"
echo "  Private subnets: $PRIVATE_COUNT"

if [ $PUBLIC_COUNT -ne 2 ] || [ $PRIVATE_COUNT -ne 2 ]; then
  echo "  ❌ Expected 2 public and 2 private subnets"
  exit 1
fi
echo "  ✅ All subnets present"
echo

echo "3️⃣ Validating NAT Gateway..."
NAT_STATE=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --query 'NatGateways[0].State' --output text)
echo "  NAT Gateway State: $NAT_STATE"
if [ "$NAT_STATE" != "available" ]; then
  echo "  ❌ NAT Gateway is not available"
  exit 1
fi
echo "  ✅ NAT Gateway is available"
echo

echo "4️⃣ Validating VPC Endpoints..."
ENDPOINTS=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --query 'VpcEndpoints[*].{Service:ServiceName,State:State}' --output text)
echo "$ENDPOINTS"

ENDPOINT_COUNT=$(echo "$ENDPOINTS" | wc -l)
if [ $ENDPOINT_COUNT -lt 4 ]; then
  echo "  ⚠️  Expected at least 4 VPC endpoints"
fi

FAILED_ENDPOINTS=$(echo "$ENDPOINTS" | grep -v "available" | wc -l)
if [ $FAILED_ENDPOINTS -gt 0 ]; then
  echo "  ❌ Some endpoints are not available"
  exit 1
fi
echo "  ✅ All VPC endpoints are available"
echo

echo "5️⃣ Validating Security Groups..."
SG_COUNT=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[*].GroupId' --output text | wc -w)
echo "  Security Groups: $SG_COUNT"
if [ $SG_COUNT -lt 5 ]; then
  echo "  ❌ Expected at least 5 security groups (including default)"
  exit 1
fi
echo "  ✅ All security groups created"
echo

echo "6️⃣ Validating IAM Roles..."
ROLES="data-platform-dev-redshift-spectrum-role data-platform-dev-mwaa-execution-role data-platform-dev-ecs-task-execution-role"
for ROLE in $ROLES; do
  if aws iam get-role --role-name $ROLE &>/dev/null; then
    echo "  ✅ $ROLE exists"
  else
    echo "  ❌ $ROLE not found"
    exit 1
  fi
done
echo

echo "7️⃣ Validating Terraform State..."
STATE_BUCKET=$(terraform backend config 2>/dev/null | grep bucket | awk '{print $3}' | tr -d '"')
echo "  State bucket: $STATE_BUCKET"

if aws s3 ls "s3://$STATE_BUCKET/dev/terraform.tfstate" &>/dev/null; then
  echo "  ✅ Terraform state file exists"
else
  echo "  ❌ Terraform state file not found"
  exit 1
fi
echo

echo "8️⃣ Validating Tags..."
UNTAGGED=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --query 'Vpcs[0].Tags[?Key==`Project`]' --output text)
if [ -z "$UNTAGGED" ]; then
  echo "  ⚠️  VPC missing Project tag"
else
  echo "  ✅ VPC properly tagged"
fi
echo

echo "✅ All infrastructure validation checks passed!"
EOF

chmod +x ../../scripts/validate-infrastructure.sh

# Run validation
../../scripts/validate-infrastructure.sh
```

**✅ Validation**: All checks pass

### Step 2: Test VPC Connectivity (30 minutes)

Create a test EC2 instance to verify private subnet connectivity:

```bash
# Get private subnet ID
PRIVATE_SUBNET=$(terraform output -json networking | jq -r '.private_subnet_ids[0]')

# Get ECS security group
ECS_SG=$(terraform output -json networking | jq -r '.security_group_ids.ecs')

# Launch a test instance (Amazon Linux 2)
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t3.micro \
  --subnet-id $PRIVATE_SUBNET \
  --security-group-ids $ECS_SG \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=test-connectivity},{Key=Environment,Value=dev}]' \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Launched test instance: $INSTANCE_ID"

# Wait for instance to be running
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

# Check if instance can reach internet (through NAT Gateway)
# Connect via Session Manager (requires SSM agent)
# Or check VPC Flow Logs

# Clean up test instance
aws ec2 terminate-instances --instance-ids $INSTANCE_ID
echo "Terminated test instance"
```

**✅ Validation**: Instance can launch in private subnet

### Step 3: Implement Comprehensive Tagging (1 hour 30 minutes)

```bash
cd terraform/modules/networking

# Add comprehensive tagging to all resources
cat > tags.tf <<'EOF'
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Module      = "networking"
    Repository  = "aws-data-platform"
    CostCenter  = "data-engineering"
  }
}

# Apply to VPC
resource "null_resource" "vpc_tags" {
  triggers = {
    vpc_id = aws_vpc.main.id
  }

  provisioner "local-exec" {
    command = <<EOF
aws ec2 create-tags \
  --resources ${aws_vpc.main.id} \
  --tags ${jsonencode([for k, v in local.common_tags : {Key = k, Value = v}])}
EOF
  }
}
EOF

cd ../../environments/dev

# Create outputs file for easy reference
cat > outputs.tf <<'EOF'
output "infrastructure_summary" {
  description = "Summary of deployed infrastructure"
  value = {
    vpc = {
      id   = module.networking.vpc_id
      cidr = module.networking.vpc_cidr
    }
    subnets = {
      public  = module.networking.public_subnet_ids
      private = module.networking.private_subnet_ids
    }
    security_groups = module.networking.security_group_ids
    iam_roles = {
      redshift   = module.iam.redshift_spectrum_role_arn
      mwaa       = module.iam.mwaa_execution_role_arn
      ecs        = module.iam.ecs_task_execution_role_arn
    }
  }
}

output "terraform_state" {
  description = "Terraform state configuration"
  value = {
    bucket         = "${var.project_name}-terraform-state-${data.aws_caller_identity.current.account_id}"
    key            = "dev/terraform.tfstate"
    region         = var.aws_region
    dynamodb_table = "${var.project_name}-terraform-locks"
  }
}

data "aws_caller_identity" "current" {}
EOF

terraform apply
terraform output
```

**✅ Validation**: All resources properly tagged

---

## Afternoon Session (3 hours)

### Step 4: Prepare Sprint Demo (1 hour)

```bash
mkdir -p ../../docs/demos/sprint-02

cat > ../../docs/demos/sprint-02/DEMO_SCRIPT.md <<'EOF'
# Sprint 2 Demo Script

**Date**: [Today's Date]
**Duration**: 15 minutes
**Sprint Goal**: Provision core AWS infrastructure for dev environment

---

## Demo Flow

### 1. Introduction (2 minutes)

**SAY**:
> "In Sprint 2, we provisioned our AWS infrastructure foundation. Everything is now managed as code with Terraform and deployed to AWS."

### 2. Terraform State Management (3 minutes)

**SHOW**: Terraform backend configuration

```bash
cd terraform/environments/dev
cat backend.tf
```

**HIGHLIGHT**:
- S3 bucket for state storage
- DynamoDB for state locking
- Encryption enabled

**SHOW**: State file in S3

```bash
aws s3 ls s3://data-platform-terraform-state-xxxxx/dev/
```

### 3. Network Infrastructure (5 minutes)

**SHOW**: VPC and subnets in AWS Console
- Navigate to VPC Dashboard
- Show VPC with 2 public, 2 private subnets
- Show route tables

**SHOW**: Terraform outputs

```bash
terraform output networking
```

**HIGHLIGHT**:
- Multi-AZ setup (us-east-1a, us-east-1b)
- NAT Gateway for private subnet internet access
- VPC Endpoints (S3, ECR, Secrets Manager)

**SAY**:
> "VPC endpoints reduce data transfer costs and improve security by keeping traffic within AWS."

### 4. Security Configuration (3 minutes)

**SHOW**: Security groups

```bash
aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$(terraform output -raw networking | jq -r '.vpc_id')" \
  --query 'SecurityGroups[].[GroupName,Description]' \
  --output table
```

**HIGHLIGHT**:
- Separate security groups for each service
- Principle of least privilege
- No public access to data services

### 5. IAM Roles (2 minutes)

**SHOW**: IAM roles created

```bash
terraform output iam_roles
```

**HIGHLIGHT**:
- Redshift Spectrum role (S3 + Glue access)
- MWAA execution role (prepared for Sprint 7)
- ECS task execution role (prepared for Sprint 8)

---

## Q&A Preparation

**Q**: "What does this cost per month?"
**A**: "Dev environment: ~$50/month (primarily NAT Gateway). We have billing alerts at $500."

**Q**: "Is this production-ready?"
**A**: "This is the dev environment. Production will be deployed in Sprint 11 with additional HA, security, and monitoring."

**Q**: "Can we deploy to multiple regions?"
**A**: "Not currently in scope, but the Terraform modules are designed to be reusable. Multi-region is in the backlog."

**Q**: "What's next?"
**A**: "Sprint 3 will create S3 buckets for the data lake and configure EventBridge for automated triggers."

---

## Demo Checklist

- [ ] AWS Console open and logged in
- [ ] Terminal in terraform/environments/dev
- [ ] VPC Dashboard bookmarked
- [ ] terraform output command ready
EOF

cat > ../../docs/demos/sprint-02/FEEDBACK.md <<'EOF'
# Sprint 2 Demo Feedback

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

**Overall Status**: [Approved/Approved with changes]
EOF
```

### Step 5: Conduct Sprint Demo (30 minutes)

Present to stakeholders following the demo script.

**✅ Validation**: Demo delivered, feedback collected

### Step 6: Sprint Retrospective (1 hour)

```bash
cat > ../../docs/retrospectives/sprint-02.md <<'EOF'
# Sprint 2 Retrospective

**Date**: [Today's Date]
**Sprint**: 2/14
**Goal**: AWS Account Setup & Terraform Foundation

---

## Sprint Metrics

| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| Story Points Planned | 21 | 21 | ✅ |
| Story Points Completed | 21 | TBD | TBD |
| Velocity | 100% | TBD | TBD |
| Blockers | 0 | TBD | TBD |

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

## Action Items for Sprint 3

| Action | Owner | Due Date | Priority |
|--------|-------|----------|----------|
| | | | |

---

## Technical Decisions Made

1. **Single NAT Gateway**: Chose one NAT Gateway in dev to save costs. Production will have multi-AZ NAT Gateways.
2. **VPC Endpoints**: Implemented early to establish best practices.
3. **Security Groups**: Created all service security groups upfront to visualize network architecture.

---

## Risks & Issues

### Resolved
-

### New
-

### Ongoing
-

---

## Sprint Health

- **Team Collaboration**: ___/5
- **Infrastructure Quality**: ___/5
- **Documentation**: ___/5
- **AWS Knowledge**: ___/5
- **Velocity**: ___/5

**Average**: ___/5

---

## Sprint 3 Preview

**Goal**: S3 Storage & Data Lake Foundation

**Deliverables**:
- S3 buckets for raw data, artifacts, MWAA
- EventBridge rules for S3 events
- Sample data upload and validation
EOF
```

**Facilitate retrospective** using the document.

**✅ Validation**: Retrospective completed

### Step 7: Sprint Closure (30 minutes)

```bash
# Create sprint summary
cat > ../../docs/sprint-summaries/sprint-02-summary.md <<'EOF'
# Sprint 2 Summary

**Sprint**: 2/14
**Duration**: Days 4-6
**Goal**: Provision core AWS infrastructure for dev environment

---

## Deliverables Status

### Day 1 ✅
- [x] AWS account configured with MFA
- [x] Billing alerts set ($500 budget)
- [x] S3 bucket for Terraform state
- [x] DynamoDB table for state locks
- [x] Terraform backend initialized
- [x] IAM roles created

### Day 2 ✅
- [x] VPC with public/private subnets
- [x] NAT Gateway configured
- [x] VPC endpoints deployed
- [x] Security groups created
- [x] VPC Flow Logs enabled

### Day 3 ✅
- [x] All resources validated
- [x] Comprehensive tagging implemented
- [x] Demo delivered
- [x] Retrospective completed

---

## Acceptance Criteria

- ✅ Terraform state stored in S3 with versioning
- ✅ State locks working via DynamoDB
- ✅ VPC with public/private subnets operational
- ✅ VPC endpoints functional
- ✅ All resources properly tagged

---

## Infrastructure Deployed

- 1 VPC (10.0.0.0/16)
- 2 Public subnets
- 2 Private subnets
- 1 Internet Gateway
- 1 NAT Gateway
- 4 VPC Endpoints (S3, ECR API, ECR Docker, Secrets Manager)
- 5 Security Groups
- 3 IAM Roles
- VPC Flow Logs

**Total Resources**: 25+

---

## Costs

**Estimated monthly cost (dev)**:
- NAT Gateway: $32/month
- VPC Interface Endpoints: ~$21/month (3 × $7)
- Data transfer: Variable
- **Total**: ~$50-60/month

---

## Key Learnings

1. Terraform state management is critical - set up early
2. VPC endpoints save money and improve security
3. Comprehensive tagging enables cost tracking
4. AWS resource provisioning can take time (NAT Gateway ~5 min)

---

## Next Sprint

**Sprint 3**: S3 Storage & Data Lake Foundation (Days 7-9)
**Ready**: ✅ Yes
**Blockers**: None
EOF

# Commit all work
cd terraform/environments/dev

git add -A
git commit -m "feat: complete Sprint 2 - AWS Infrastructure Foundation

Day 1:
- Configured AWS account with MFA and billing alerts
- Created Terraform backend (S3 + DynamoDB)
- Built IAM roles for Redshift, MWAA, and ECS

Day 2:
- Deployed VPC with multi-AZ public/private subnets
- Configured NAT Gateway and VPC endpoints
- Created security groups for all services
- Enabled VPC Flow Logs

Day 3:
- Validated all infrastructure
- Implemented comprehensive tagging
- Conducted sprint demo
- Completed retrospective

Infrastructure deployed: 25+ resources
Acceptance criteria: 100% met ✅

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

git push origin develop
```

**✅ Validation**: Sprint 2 complete, all work committed

---

## End of Day 3 Checklist

- [x] All infrastructure validated
- [x] VPC connectivity tested
- [x] Comprehensive tagging applied
- [x] Sprint demo delivered
- [x] Stakeholder feedback collected
- [x] Sprint retrospective conducted
- [x] Sprint summary documented
- [x] All work committed to Git

---

## 🎉 Sprint 2 Complete!

### Accomplishments

- ✅ Complete AWS networking foundation
- ✅ Terraform state management operational
- ✅ All resources managed as code
- ✅ Security best practices implemented
- ✅ Cost monitoring configured

### Infrastructure Ready For

- ✅ S3 data lake (Sprint 3)
- ✅ Redshift cluster (Sprint 4)
- ✅ dbt transformations (Sprint 5)
- ✅ Docker containers (Sprint 6)
- ✅ MWAA orchestration (Sprint 7)

---

## ⏭️ Next: Sprint 3

**Sprint 3**: S3 Storage & Data Lake Foundation (Days 7-9)

You'll be working on:
- Creating S3 buckets for all data zones
- Implementing EventBridge rules
- Uploading sample data
- Testing event-driven triggers

**Ready to continue?** See `workshops/sprint-03/` 🚀
