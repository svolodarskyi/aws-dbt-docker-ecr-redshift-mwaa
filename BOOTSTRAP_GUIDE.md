# Terraform Bootstrap Guide

## Why Bootstrap with Terraform?

**The Problem**: Terraform needs a place to store state, but we want to use Terraform to create that storage!

**The Solution**: Bootstrap approach
1. Use Terraform with **local state** to create S3 + DynamoDB
2. Other environments use this **remote state** backend
3. Bootstrap state stays local (backed up manually)

This is better than manual creation because:
- ✅ **Infrastructure as Code**: Backend is version-controlled
- ✅ **Reproducible**: Can recreate in other AWS accounts
- ✅ **Documented**: Configuration shows exactly what exists
- ✅ **Manageable**: Can update backend settings with Terraform

## Quick Start

### 1. Bootstrap the State Backend

```bash
# Navigate to bootstrap directory
cd terraform/bootstrap

# Initialize (uses local state)
terraform init

# Review what will be created
terraform plan

# Apply (creates S3 bucket + DynamoDB table)
terraform apply
```

**What gets created**:
- S3 Bucket: `data-platform-terraform-state`
  - Versioning: Enabled
  - Encryption: AES256
  - Public access: Blocked
- DynamoDB Table: `data-platform-terraform-locks`
  - Billing: Pay-per-request
  - Point-in-time recovery: Enabled

### 2. Back Up Bootstrap State

```bash
# Still in terraform/bootstrap directory

# Copy state to safe location
cp terraform.tfstate ~/backups/terraform-bootstrap-state-$(date +%Y%m%d).tfstate

# Optional: Upload to personal backup bucket
aws s3 cp terraform.tfstate s3://my-personal-backup/terraform-bootstrap.tfstate
```

⚠️ **Important**: The bootstrap state file stays **local**. Keep it safe!

### 3. Configure Dev Environment

```bash
cd ../environments/dev

# Backend is already configured in main.tf:
terraform {
  backend "s3" {
    bucket         = "data-platform-terraform-state"
    key            = "env/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "data-platform-terraform-locks"
  }
}

# Initialize (migrates to remote state)
terraform init
```

### 4. Configure Prod Environment

```bash
cd ../environments/prod

# Same backend, different key
terraform {
  backend "s3" {
    bucket         = "data-platform-terraform-state"
    key            = "env/prod/terraform.tfstate"  # Different key!
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "data-platform-terraform-locks"
  }
}

# Initialize
terraform init
```

## State File Locations

After bootstrap:

```
Local:
├── terraform/bootstrap/terraform.tfstate  # Bootstrap state (LOCAL)

Remote (S3):
├── env/dev/terraform.tfstate              # Dev environment state
└── env/prod/terraform.tfstate             # Prod environment state
```

## Cost

**S3 Bucket**: ~$1-2/month
- State files are typically <1 MB
- Versioning keeps history

**DynamoDB Table**: <$1/month
- Pay-per-request billing
- Minimal operations (only during terraform apply)

**Total**: ~$2-3/month

## Multi-Account Setup

### Same Account (Dev + Prod in one AWS account)

Run bootstrap **once**:
```bash
cd terraform/bootstrap
terraform apply
```

Both environments share the bucket but use different keys:
- Dev: `env/dev/terraform.tfstate`
- Prod: `env/prod/terraform.tfstate`

### Separate Accounts (Dev and Prod in different AWS accounts)

Run bootstrap in **each account**:

```bash
# In dev AWS account
aws-vault exec data-platform-dev -- terraform apply

# In prod AWS account
aws-vault exec data-platform-prod -- terraform apply
```

Creates separate backends:
- Dev account: `data-platform-terraform-state` (dev)
- Prod account: `data-platform-terraform-state` (prod)

## Disaster Recovery

### Lost Bootstrap State File

If you lose `terraform/bootstrap/terraform.tfstate`:

```bash
cd terraform/bootstrap

# Import existing resources
terraform import aws_s3_bucket.terraform_state data-platform-terraform-state
terraform import aws_s3_bucket_versioning.terraform_state data-platform-terraform-state
terraform import aws_s3_bucket_server_side_encryption_configuration.terraform_state data-platform-terraform-state
terraform import aws_s3_bucket_public_access_block.terraform_state data-platform-terraform-state
terraform import aws_dynamodb_table.terraform_locks data-platform-terraform-locks

# Verify
terraform plan  # Should show no changes
```

### Corrupted Environment State

List state versions and restore:

```bash
# List versions
aws s3api list-object-versions \
  --bucket data-platform-terraform-state \
  --prefix env/dev/terraform.tfstate

# Download previous version
aws s3api get-object \
  --bucket data-platform-terraform-state \
  --key env/dev/terraform.tfstate \
  --version-id <VERSION_ID> \
  terraform.tfstate.backup

# Test it
terraform plan
```

## Updating Bootstrap

To modify backend settings:

```bash
cd terraform/bootstrap

# Edit configuration
vim main.tf

# Apply changes
terraform apply

# Back up updated state
cp terraform.tfstate ~/backups/terraform-bootstrap-state-$(date +%Y%m%d).tfstate
```

## Best Practices

1. ✅ **Run bootstrap first** before any other Terraform
2. ✅ **Back up bootstrap state** to multiple locations
3. ✅ **Keep bootstrap simple** (minimal resources)
4. ✅ **Rarely change bootstrap** (it's foundational)
5. ✅ **Document state location** (team wiki, README)
6. ✅ **Restrict S3 bucket access** (IAM policies)
7. ✅ **Enable CloudTrail** (audit state access)

## Comparison: Manual vs Bootstrap

| Aspect | Manual (CLI) | Bootstrap (Terraform) |
|--------|-------------|----------------------|
| **Reproducible** | ❌ No | ✅ Yes |
| **Version Controlled** | ❌ No | ✅ Yes |
| **Documented** | ⚠️ Manual docs | ✅ Code is documentation |
| **Auditable** | ⚠️ Via CloudTrail | ✅ Via Git + CloudTrail |
| **Multi-account** | ⚠️ Repeat manually | ✅ Run bootstrap in each |
| **Updates** | ❌ Manual changes | ✅ `terraform apply` |
| **Complexity** | ✅ Simple (1 command) | ⚠️ More steps |

**Recommendation**: Use **Bootstrap approach** for production projects

## FAQs

### Q: Why not store bootstrap state remotely?

**A**: That creates a circular dependency! The state bucket can't store the state file that creates itself.

### Q: What if I delete the bootstrap state file?

**A**: You can import existing resources back into Terraform (see Disaster Recovery section).

### Q: Can I use Terraform Cloud instead?

**A**: Yes! Terraform Cloud provides remote state without needing S3/DynamoDB. But S3 gives you more control and lower cost.

### Q: Should I commit bootstrap state to Git?

**A**: **No** (unless encrypted with `git-crypt`). Store it securely offline instead.

### Q: What if the bucket name is taken?

**A**: Change the `project_name` variable:
```bash
terraform apply -var="project_name=mycompany-data-platform"
```

## Next Steps

After bootstrap completes:

1. ✅ Back up `terraform/bootstrap/terraform.tfstate`
2. ✅ Initialize dev: `cd environments/dev && terraform init`
3. ✅ Initialize prod: `cd environments/prod && terraform init`
4. ✅ Start Sprint 2: Begin infrastructure provisioning

**Your Terraform backend is now ready!** 🎉

See `terraform/bootstrap/README.md` for more detailed documentation.
