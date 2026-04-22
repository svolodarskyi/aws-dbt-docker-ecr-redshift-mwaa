# Sprint 2 Workshop: AWS Account Setup & Terraform Foundation

**Duration**: Days 4-6 (3 days)

**Goal**: Provision core AWS infrastructure for dev environment

---

## Overview

In Sprint 2, you'll:
- Set up AWS accounts with proper security
- Configure Terraform state management
- Deploy VPC and networking foundation
- Create security groups and IAM roles

---

## Prerequisites

Before starting Sprint 2, ensure:
- ✅ Sprint 1 completed successfully
- ✅ AWS account access provided
- ✅ Billing alerts configured
- ✅ MFA enabled on AWS account

---

## Daily Breakdown

### [Day 1](./day-1.md): AWS Setup & Terraform Backend
- AWS account configuration
- IAM users and roles
- S3 + DynamoDB for Terraform state
- Terraform backend initialization

### [Day 2](./day-2.md): Networking & Security
- VPC and subnet configuration
- NAT gateways and internet gateways
- Security groups
- VPC endpoints

### [Day 3](./day-3.md): Deployment & Validation
- Apply Terraform to dev environment
- Validate resources
- Tagging strategy
- Sprint demo and retrospective

---

## Acceptance Criteria

By end of Sprint 2:
- ✅ Terraform state stored in S3 with versioning
- ✅ State locks working via DynamoDB
- ✅ VPC with public/private subnets operational
- ✅ VPC endpoints functional
- ✅ All resources properly tagged

---

## Estimated Story Points

**Total**: 21 points

- AWS setup: 8 points
- Networking: 8 points
- Validation & demo: 5 points

---

## Start Here

👉 Begin with [Day 1: AWS Setup & Terraform Backend](./day-1.md)
