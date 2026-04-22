# Sprint 2 - Day 2: Networking & Security

**Goal**: Deploy VPC, subnets, and security infrastructure

**Duration**: ~6 hours

**Outcome**: Complete networking foundation in AWS

---

## Morning Session (3 hours)

### Step 1: Create VPC Networking Module (1 hour 30 minutes)

```bash
cd terraform/modules

# Create networking module
mkdir -p networking

cd networking

cat > main.tf <<'EOF'
# ---------------------------------------------------------
# VPC
# ---------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

# ---------------------------------------------------------
# Internet Gateway
# ---------------------------------------------------------

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

# ---------------------------------------------------------
# Public Subnets (for NAT Gateway, Bastion)
# ---------------------------------------------------------

resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-public-subnet-${count.index + 1}"
    Tier = "Public"
  }
}

# ---------------------------------------------------------
# Private Subnets (for MWAA, ECS, Redshift, RDS)
# ---------------------------------------------------------

resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-${var.environment}-private-subnet-${count.index + 1}"
    Tier = "Private"
  }
}

# ---------------------------------------------------------
# NAT Gateway
# ---------------------------------------------------------

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-gateway"
  }

  depends_on = [aws_internet_gateway.main]
}

# ---------------------------------------------------------
# Route Tables
# ---------------------------------------------------------

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-private-rt"
  }
}

resource "aws_route" "private_nat_gateway" {
  count = var.enable_nat_gateway ? 1 : 0

  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[0].id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ---------------------------------------------------------
# VPC Endpoints
# ---------------------------------------------------------

# S3 Gateway Endpoint (free)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${var.project_name}-${var.environment}-s3-endpoint"
  }
}

# ECR API Interface Endpoint
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name = "${var.project_name}-${var.environment}-ecr-api-endpoint"
  }
}

# ECR Docker Interface Endpoint
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name = "${var.project_name}-${var.environment}-ecr-dkr-endpoint"
  }
}

# Secrets Manager Interface Endpoint
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name = "${var.project_name}-${var.environment}-secretsmanager-endpoint"
  }
}

# ---------------------------------------------------------
# Data Sources
# ---------------------------------------------------------

data "aws_region" "current" {}
EOF

cat > security_groups.tf <<'EOF'
# ---------------------------------------------------------
# Security Groups
# ---------------------------------------------------------

# VPC Endpoints Security Group
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-${var.environment}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc-endpoints-sg"
  }
}

# MWAA Security Group (will be used in Sprint 7)
resource "aws_security_group" "mwaa" {
  name        = "${var.project_name}-${var.environment}-mwaa-sg"
  description = "Security group for MWAA environment"
  vpc_id      = aws_vpc.main.id

  # Self-referencing rule for internal communication
  ingress {
    description = "Allow all from self"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-mwaa-sg"
  }
}

# Redshift Security Group (will be used in Sprint 4)
resource "aws_security_group" "redshift" {
  name        = "${var.project_name}-${var.environment}-redshift-sg"
  description = "Security group for Redshift cluster"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redshift from MWAA"
    from_port       = 5439
    to_port         = 5439
    protocol        = "tcp"
    security_groups = [aws_security_group.mwaa.id]
  }

  ingress {
    description     = "Redshift from ECS"
    from_port       = 5439
    to_port         = 5439
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-redshift-sg"
  }
}

# ECS Security Group (will be used in Sprint 8)
resource "aws_security_group" "ecs" {
  name        = "${var.project_name}-${var.environment}-ecs-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-sg"
  }
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

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}
EOF

cat > outputs.tf <<'EOF'
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = var.enable_nat_gateway ? aws_nat_gateway.main[0].id : null
}

output "security_group_ids" {
  description = "Security group IDs"
  value = {
    vpc_endpoints = aws_security_group.vpc_endpoints.id
    mwaa          = aws_security_group.mwaa.id
    redshift      = aws_security_group.redshift.id
    ecs           = aws_security_group.ecs.id
  }
}
EOF
```

**✅ Validation**: Networking module created

### Step 2: Reference Networking Module in Environment (30 minutes)

```bash
cd ../../environments/dev

cat > networking.tf <<'EOF'
module "networking" {
  source = "../../modules/networking"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  enable_nat_gateway = true
}

output "networking" {
  value = {
    vpc_id              = module.networking.vpc_id
    vpc_cidr            = module.networking.vpc_cidr
    public_subnet_ids   = module.networking.public_subnet_ids
    private_subnet_ids  = module.networking.private_subnet_ids
    security_group_ids  = module.networking.security_group_ids
  }
}
EOF

# Format and validate
terraform fmt -recursive ../../
terraform validate

# Create plan
terraform plan

# Expected: Shows ~20 resources to create:
# - 1 VPC
# - 1 Internet Gateway
# - 2 Public subnets
# - 2 Private subnets
# - 1 NAT Gateway
# - 1 EIP
# - Route tables
# - VPC Endpoints
# - Security groups
```

**✅ Validation**: Plan shows expected networking resources

---

## Afternoon Session (3 hours)

### Step 3: Deploy Infrastructure (1 hour)

```bash
# Apply Terraform (this will create real AWS resources!)
terraform apply

# Review the plan one more time
# Type 'yes' when ready

# Expected: Apply complete! Resources: 20+ added, 0 changed, 0 destroyed.
# Time: ~5-10 minutes (NAT Gateway takes longest)
```

Monitor the deployment:

```bash
# Watch VPC creation
aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=data-platform-dev-vpc" \
  --query 'Vpcs[0].[VpcId,State,CidrBlock]' \
  --output table

# Watch subnet creation
aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=data-platform-dev-*" \
  --query 'Subnets[].[SubnetId,CidrBlock,AvailabilityZone,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# Check NAT Gateway status
aws ec2 describe-nat-gateways \
  --filter "Name=tag:Name,Values=data-platform-dev-nat-gateway" \
  --query 'NatGateways[0].[NatGatewayId,State]' \
  --output table
```

**✅ Validation**: All resources show "available" or "active" state

### Step 4: Verify Networking (1 hour)

Test VPC connectivity:

```bash
# 1. Verify VPC endpoints
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=$(terraform output -raw networking | jq -r '.vpc_id')" \
  --query 'VpcEndpoints[].[ServiceName,State]' \
  --output table

# All should show "available"

# 2. Test S3 VPC endpoint
# Create test S3 bucket
aws s3 mb s3://test-vpc-endpoint-$(date +%s)

# From EC2 instance in private subnet (if you had one):
# aws s3 ls s3://test-vpc-endpoint-xxx
# Traffic should route through VPC endpoint (check VPC Flow Logs)

# 3. Verify route tables
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$(terraform output -raw networking | jq -r '.vpc_id')" \
  --query 'RouteTables[].[RouteTableId,Tags[?Key==`Name`].Value|[0],Routes[].{Dest:DestinationCidrBlock,Target:GatewayId}]' \
  --output table

# 4. Verify security groups
aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$(terraform output -raw networking | jq -r '.vpc_id')" \
  --query 'SecurityGroups[].[GroupId,GroupName,Description]' \
  --output table
```

**✅ Validation**: All endpoints available, routes configured correctly

### Step 5: Configure VPC Flow Logs (Optional but Recommended) (30 minutes)

```bash
cd terraform/modules/networking

# Add to main.tf
cat >> main.tf <<'EOF'

# ---------------------------------------------------------
# VPC Flow Logs
# ---------------------------------------------------------

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/${var.project_name}-${var.environment}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc-flow-logs"
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "${var.project_name}-${var.environment}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc-flow-logs-role"
  }
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.vpc_flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc-flow-log"
  }
}
EOF

cd ../../environments/dev

# Apply the changes
terraform apply
```

**✅ Validation**: VPC Flow Logs enabled in CloudWatch

### Step 6: Document Network Architecture (30 minutes)

```bash
# Update architecture documentation
cat >> ../../docs/NETWORK_ARCHITECTURE.md <<'EOF'
# Network Architecture - Dev Environment

## Overview

The dev environment uses a VPC with public and private subnets across 2 availability zones.

## VPC Configuration

- **VPC CIDR**: 10.0.0.0/16
- **Region**: us-east-1
- **Availability Zones**: us-east-1a, us-east-1b

## Subnets

### Public Subnets
| Subnet | CIDR | AZ | Purpose |
|--------|------|-----|---------|
| public-subnet-1 | 10.0.0.0/24 | us-east-1a | NAT Gateway, Bastion (future) |
| public-subnet-2 | 10.0.1.0/24 | us-east-1b | HA/Redundancy |

### Private Subnets
| Subnet | CIDR | AZ | Purpose |
|--------|------|-----|---------|
| private-subnet-1 | 10.0.10.0/24 | us-east-1a | MWAA, ECS, Redshift |
| private-subnet-2 | 10.0.11.0/24 | us-east-1b | MWAA, ECS, Redshift |

## Routing

### Public Route Table
- Route: 0.0.0.0/0 → Internet Gateway
- Associated with: public-subnet-1, public-subnet-2

### Private Route Table
- Route: 0.0.0.0/0 → NAT Gateway (in public-subnet-1)
- Associated with: private-subnet-1, private-subnet-2

## VPC Endpoints

| Endpoint | Type | Purpose |
|----------|------|---------|
| S3 | Gateway | ECS/MWAA access to S3 (no data charges) |
| ECR API | Interface | Pull Docker images |
| ECR Docker | Interface | Pull Docker image layers |
| Secrets Manager | Interface | Access credentials |

## Security Groups

| Security Group | Purpose | Ingress Rules |
|----------------|---------|---------------|
| vpc-endpoints-sg | VPC Endpoints | 443 from VPC CIDR |
| mwaa-sg | MWAA Environment | Self-referencing all |
| redshift-sg | Redshift Cluster | 5439 from MWAA, ECS |
| ecs-sg | ECS Tasks | None (egress only) |

## Network Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ VPC (10.0.0.0/16)                                           │
│                                                             │
│  ┌─────────────────────┐      ┌─────────────────────┐     │
│  │ Public Subnet       │      │ Public Subnet       │     │
│  │ 10.0.0.0/24         │      │ 10.0.1.0/24         │     │
│  │ us-east-1a          │      │ us-east-1b          │     │
│  │                     │      │                     │     │
│  │ ┌──────────────┐   │      │                     │     │
│  │ │ NAT Gateway  │   │      │                     │     │
│  │ │ + EIP        │   │      │                     │     │
│  │ └──────────────┘   │      │                     │     │
│  └─────────┬───────────┘      └─────────────────────┘     │
│            │                                                │
│            │  Internet Gateway                             │
│            │        ↕                                       │
│         Internet                                           │
│                                                             │
│  ┌─────────────────────┐      ┌─────────────────────┐     │
│  │ Private Subnet      │      │ Private Subnet      │     │
│  │ 10.0.10.0/24        │      │ 10.0.11.0/24        │     │
│  │ us-east-1a          │      │ us-east-1b          │     │
│  │                     │      │                     │     │
│  │ • MWAA              │      │ • MWAA (HA)         │     │
│  │ • ECS Tasks         │      │ • ECS Tasks (HA)    │     │
│  │ • Redshift          │      │ • Redshift (HA)     │     │
│  │                     │      │                     │     │
│  └─────────────────────┘      └─────────────────────┘     │
│                                                             │
│  VPC Endpoints: S3, ECR API, ECR Docker, Secrets Manager   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Cost Optimization

- **NAT Gateway**: ~$32/month (always running)
  - Alternative: NAT Instance (cheaper but less reliable)
  - Consider turning off in dev environment overnight
- **VPC Endpoints**: Interface endpoints ~$7/month each
  - S3 Gateway endpoint: Free
- **Data Transfer**: Through NAT Gateway incurs charges

## Security Best Practices

1. ✅ All services in private subnets
2. ✅ No public IP addresses on resources
3. ✅ VPC Flow Logs enabled
4. ✅ VPC Endpoints reduce internet exposure
5. ✅ Security groups follow least privilege

## Future Enhancements

- [ ] Bastion host for secure SSH access
- [ ] Network ACLs for additional security layer
- [ ] VPC peering for multi-environment access
- [ ] Transit Gateway for complex networking

EOF
```

**✅ Validation**: Network architecture documented

---

## End of Day 2 Checklist

- [x] Networking Terraform module created
- [x] VPC deployed with public/private subnets
- [x] NAT Gateway configured
- [x] VPC Endpoints created (S3, ECR, Secrets Manager)
- [x] Security groups configured
- [x] VPC Flow Logs enabled
- [x] Network architecture documented

---

## 📝 Daily Standup Notes

**Completed Today**:
- Created complete networking infrastructure
- Deployed VPC with 2 public and 2 private subnets
- Configured NAT Gateway and VPC endpoints
- Set up security groups for all services
- Enabled VPC Flow Logs

**Blockers**:
- None

**Tomorrow's Plan**:
- Validate all resources
- Add resource tagging
- Sprint demo preparation
- Sprint retrospective

---

## 🎯 Success Metric

**You're successful if**:

```bash
# All resources deployed
terraform state list | wc -l
# Should show 20+ resources

# VPC is active
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=data-platform-dev-vpc" --query 'Vpcs[0].State'
# Should show "available"

# VPC endpoints are active
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=vpc-xxx" --query 'VpcEndpoints[*].State'
# All should show "available"
```

---

## ⏭️ Next: Day 3

Tomorrow you'll:
- Validate all deployed resources
- Implement comprehensive tagging
- Conduct sprint demo
- Run sprint retrospective

**See [day-3.md](./day-3.md)** 🚀
