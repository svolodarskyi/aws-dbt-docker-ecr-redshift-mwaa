# Terraform State Backend Bootstrap

This directory contains the bootstrap configuration to create the Terraform state backend (S3 + DynamoDB).

## The "Chicken and Egg" Problem

Terraform needs a place to store its state, but we want to use Terraform to create that place! The solution is a **bootstrap approach**:

1. Use local state to create the S3 bucket and DynamoDB table
2. Other environments then use this remote backend
3. Bootstrap state is stored locally (backed up manually)

## One-Time Setup

### Step 1: Initialize and Apply Bootstrap

```bash
# Navigate to bootstrap directory
cd terraform/bootstrap

# Initialize Terraform (uses local state)
terraform init

# Review what will be created
terraform plan

# Create the state backend resources
terraform apply
```

This creates:
- **S3 Bucket**: `data-platform-terraform-state`
  - Versioning enabled
  - Encryption enabled
  - Public access blocked
  - Lifecycle rules for old versions
- **DynamoDB Table**: `data-platform-terraform-locks`
  - Pay-per-request billing
  - Point-in-time recovery enabled

### Step 2: Backup the Bootstrap State

The bootstrap state file is stored **locally** in this directory. Back it up:

```bash
# Copy state to a safe location
cp terraform.tfstate ~/backups/terraform-bootstrap-state-$(date +%Y%m%d).tfstate

# Or upload to a personal S3 bucket (not the state bucket!)
aws s3 cp terraform.tfstate s3://my-personal-backup-bucket/terraform/bootstrap-state.tfstate
```

### Step 3: Configure Other Environments

Now that the backend exists, configure your dev/prod environments to use it.

Edit `terraform/environments/dev/main.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "data-platform-terraform-state"
    key            = "env/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "data-platform-terraform-locks"
  }
}
```

Then initialize:

```bash
cd terraform/environments/dev
terraform init
```

## What Gets Created

### S3 Bucket Configuration

| Feature | Setting |
|---------|---------|
| **Versioning** | Enabled (keeps state history) |
| **Encryption** | AES256 server-side encryption |
| **Public Access** | Blocked completely |
| **Lifecycle** | Delete old versions after 90 days |
| **Policy** | Requires TLS (HTTPS only) |

### DynamoDB Table Configuration

| Feature | Setting |
|---------|---------|
| **Billing** | Pay-per-request (no provisioned capacity) |
| **Partition Key** | LockID (String) |
| **Point-in-time Recovery** | Enabled |
| **Encryption** | AWS-managed keys |

## Cost Estimate

**S3 Bucket**:
- Storage: ~$0.023 per GB/month (Standard)
- Typical state file: <1 MB
- **Estimated**: $1-2/month

**DynamoDB Table**:
- Pay-per-request: $1.25 per million writes
- Typical usage: <1000 operations/month
- **Estimated**: <$1/month

**Total**: ~$2-3/month for state backend

## Security Features

1. ✅ **Encryption at rest**: All state files encrypted
2. ✅ **Encryption in transit**: HTTPS only via bucket policy
3. ✅ **Versioning**: Can recover from accidental changes
4. ✅ **Public access blocked**: No public internet access
5. ✅ **State locking**: Prevents concurrent modifications
6. ✅ **Point-in-time recovery**: DynamoDB backup

## Managing the Bootstrap State

### Option 1: Keep Local State (Recommended for Small Teams)

Pros:
- Simple
- One-time setup, rarely changes

Cons:
- State file stored locally
- Need to back up manually

**Best Practice**:
- Keep `terraform.tfstate` in a secure location
- Back up to multiple locations
- Document who has the file

### Option 2: Migrate to Remote State (Advanced)

You can migrate the bootstrap state to the S3 bucket it created:

```bash
cd terraform/bootstrap

# Add backend configuration to main.tf
terraform {
  backend "s3" {
    bucket         = "data-platform-terraform-state"
    key            = "bootstrap/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "data-platform-terraform-locks"
  }
}

# Re-initialize with backend migration
terraform init -migrate-state
```

⚠️ **Warning**: This creates a circular dependency. If you delete the bucket, you can't recreate it with Terraform!

### Option 3: GitOps with Encryption (Best for Teams)

Store the bootstrap state in Git with encryption:

```bash
# Install git-crypt
brew install git-crypt

# Initialize encryption
git-crypt init

# Add .gitattributes
echo "terraform/bootstrap/terraform.tfstate filter=git-crypt diff=git-crypt" >> .gitattributes
echo "terraform/bootstrap/terraform.tfstate.backup filter=git-crypt diff=git-crypt" >> .gitattributes

# Commit encrypted state
git add terraform/bootstrap/terraform.tfstate
git commit -m "Add encrypted bootstrap state"
```

## Disaster Recovery

### Scenario 1: Accidentally Deleted S3 Bucket

```bash
# Re-run bootstrap (if you have the state file)
cd terraform/bootstrap
terraform apply

# If you don't have the state file:
# 1. Manually recreate bucket with exact same name
# 2. Import into Terraform:
terraform import aws_s3_bucket.terraform_state data-platform-terraform-state
terraform import aws_dynamodb_table.terraform_locks data-platform-terraform-locks
```

### Scenario 2: Lost Bootstrap State File

```bash
# Import existing resources
cd terraform/bootstrap

# Import S3 bucket
terraform import aws_s3_bucket.terraform_state data-platform-terraform-state
terraform import aws_s3_bucket_versioning.terraform_state data-platform-terraform-state

# Import DynamoDB table
terraform import aws_dynamodb_table.terraform_locks data-platform-terraform-locks

# Verify
terraform plan
```

### Scenario 3: Corrupted Environment State

```bash
# List available state versions
aws s3api list-object-versions \
  --bucket data-platform-terraform-state \
  --prefix env/dev/terraform.tfstate

# Download specific version
aws s3api get-object \
  --bucket data-platform-terraform-state \
  --key env/dev/terraform.tfstate \
  --version-id <VERSION_ID> \
  terraform.tfstate.recovered

# Test the recovered state
terraform plan
```

## Updating Bootstrap Resources

If you need to modify the bootstrap resources:

```bash
cd terraform/bootstrap

# Make changes to .tf files
vim main.tf

# Apply changes
terraform apply

# Back up the updated state
cp terraform.tfstate ~/backups/terraform-bootstrap-state-$(date +%Y%m%d).tfstate
```

## Removing Bootstrap Resources (Dangerous!)

⚠️ **Only do this if you're completely decommissioning the project!**

```bash
# Remove lifecycle protection
# Edit main.tf and remove:
#   lifecycle {
#     prevent_destroy = true
#   }

# Destroy resources
terraform destroy

# Manually empty and delete S3 bucket if needed
aws s3 rm s3://data-platform-terraform-state --recursive
aws s3 rb s3://data-platform-terraform-state
```

## Multi-Account Setup

For separate AWS accounts (dev vs prod):

### Option 1: Shared State Bucket (Same Account)

Both dev and prod use the same state bucket but different keys:
- Dev: `env/dev/terraform.tfstate`
- Prod: `env/prod/terraform.tfstate`

### Option 2: Separate State Buckets (Different Accounts)

Run bootstrap in each AWS account:

```bash
# Dev account
aws-vault exec data-platform-dev -- terraform apply

# Prod account
aws-vault exec data-platform-prod -- terraform apply
```

Creates:
- Dev account: `data-platform-terraform-state` (dev)
- Prod account: `data-platform-terraform-state` (prod)

## Troubleshooting

### Issue: Bucket name already exists

**Cause**: S3 bucket names are globally unique

**Solution**:
```bash
# Change project_name variable
terraform apply -var="project_name=mycompany-data-platform"
```

### Issue: State lock timeout

**Cause**: Previous operation didn't release lock

**Solution**:
```bash
# Force unlock (use with caution!)
terraform force-unlock <LOCK_ID>

# Or remove lock from DynamoDB
aws dynamodb delete-item \
  --table-name data-platform-terraform-locks \
  --key '{"LockID":{"S":"<LOCK_ID>"}}'
```

### Issue: Versioning creates too many old versions

**Solution**: Lifecycle policy automatically deletes versions >90 days old. To adjust:

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  # Change noncurrent_days to your preference
  noncurrent_version_expiration {
    noncurrent_days = 30  # Keep last 30 days only
  }
}
```

## Best Practices

1. ✅ **Run bootstrap once** per AWS account/region
2. ✅ **Back up bootstrap state** to multiple locations
3. ✅ **Enable lifecycle prevent_destroy** (already configured)
4. ✅ **Use separate state keys** for each environment
5. ✅ **Document bootstrap state location** in team wiki
6. ✅ **Restrict access** to state bucket (IAM policies)
7. ✅ **Monitor access** via CloudTrail logs

## Next Steps

After bootstrap completes:

1. ✅ Back up `terraform.tfstate` from this directory
2. ✅ Note the bucket and table names from outputs
3. ✅ Configure backend in `terraform/environments/dev/main.tf`
4. ✅ Initialize dev environment: `cd ../environments/dev && terraform init`
5. ✅ Configure backend in `terraform/environments/prod/main.tf`
6. ✅ Initialize prod environment: `cd ../environments/prod && terraform init`

**You're now ready to use Terraform with remote state!** 🎉
