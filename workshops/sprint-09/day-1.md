# Sprint 9 - Day 1: GitHub Actions CI Workflows

**Goal**: Create CI workflows for Terraform, dbt, and Python code validation

**Duration**: ~6 hours

**Outcome**: Automated testing on every pull request

---

## Morning Session (3 hours)

### Step 1: Create Terraform CI Workflow (1 hour)

```bash
cd .github/workflows

cat > terraform-ci.yml <<'EOF'
name: Terraform CI

on:
  pull_request:
    paths:
      - 'terraform/**'
      - '.github/workflows/terraform-ci.yml'

env:
  TF_VERSION: '1.6.0'
  AWS_REGION: 'us-east-1'

jobs:
  terraform-fmt:
    name: Terraform Format Check
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform fmt check
        run: terraform fmt -check -recursive terraform/
        continue-on-error: false

  terraform-validate:
    name: Terraform Validate
    runs-on: ubuntu-latest
    strategy:
      matrix:
        environment: [dev]
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Init
        run: |
          cd terraform/environments/${{ matrix.environment }}
          terraform init -backend=false

      - name: Terraform Validate
        run: |
          cd terraform/environments/${{ matrix.environment }}
          terraform validate

  tflint:
    name: TFLint
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup TFLint
        uses: terraform-linters/setup-tflint@v4
        with:
          tflint_version: latest

      - name: Init TFLint
        run: tflint --init

      - name: Run TFLint
        run: |
          cd terraform
          find . -type f -name "*.tf" -exec dirname {} \; | sort -u | while read dir; do
            echo "Linting $dir"
            (cd "$dir" && tflint) || true
          done

  terraform-plan:
    name: Terraform Plan (Dev)
    runs-on: ubuntu-latest
    needs: [terraform-fmt, terraform-validate]
    permissions:
      id-token: write
      contents: read
      pull-requests: write
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_GITHUB_ACTIONS_ROLE }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Init
        run: |
          cd terraform/environments/dev
          terraform init

      - name: Terraform Plan
        id: plan
        run: |
          cd terraform/environments/dev
          terraform plan -no-color -out=tfplan
        continue-on-error: true

      - name: Comment PR with Plan
        uses: actions/github-script@v7
        if: github.event_name == 'pull_request'
        env:
          PLAN: "${{ steps.plan.outputs.stdout }}"
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const output = `#### Terraform Plan 📖
            \`\`\`
            ${process.env.PLAN}
            \`\`\`

            *Pushed by: @${{ github.actor }}, Action: \`${{ github.event_name }}\`*`;

            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: output
            })

      - name: Fail if plan failed
        if: steps.plan.outcome == 'failure'
        run: exit 1
EOF

# Create .tflint.hcl configuration
cd ../..
cat > .tflint.hcl <<'EOF'
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.27.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

rule "terraform_naming_convention" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}
EOF
```

### Step 2: Create dbt CI Workflow (1 hour)

```bash
cd .github/workflows

cat > dbt-ci.yml <<'EOF'
name: dbt CI

on:
  pull_request:
    paths:
      - 'dbt/**'
      - '.github/workflows/dbt-ci.yml'

env:
  PYTHON_VERSION: '3.11'
  DBT_VERSION: '1.7.4'

jobs:
  dbt-compile:
    name: dbt Compile
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}
          cache: 'pip'

      - name: Install dbt
        run: |
          cd dbt
          pip install -r requirements.txt

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_GITHUB_ACTIONS_ROLE }}
          aws-region: us-east-1

      - name: dbt deps
        run: |
          cd dbt
          dbt deps

      - name: dbt compile
        run: |
          cd dbt
          dbt compile --target dev --profiles-dir ./profiles

  dbt-test:
    name: dbt Test
    runs-on: ubuntu-latest
    needs: dbt-compile
    permissions:
      id-token: write
      contents: read
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}
          cache: 'pip'

      - name: Install dbt
        run: |
          cd dbt
          pip install -r requirements.txt

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_GITHUB_ACTIONS_ROLE }}
          aws-region: us-east-1

      - name: dbt deps
        run: |
          cd dbt
          dbt deps

      - name: dbt test
        run: |
          cd dbt
          dbt test --target dev --profiles-dir ./profiles

  sqlfluff-lint:
    name: SQLFluff Lint
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}

      - name: Install SQLFluff
        run: |
          pip install sqlfluff sqlfluff-templater-dbt

      - name: Create SQLFluff config
        run: |
          cat > .sqlfluff <<'SQLFLUFF'
          [sqlfluff]
          templater = dbt
          dialect = redshift
          exclude_rules = L034,L036

          [sqlfluff:templater:dbt]
          project_dir = dbt/
          profiles_dir = dbt/profiles/
          profile = data_platform
          target = dev

          [sqlfluff:rules]
          max_line_length = 120
          indent_unit = space
          tab_space_size = 2

          [sqlfluff:rules:L010]
          capitalisation_policy = upper

          [sqlfluff:rules:L030]
          capitalisation_policy = upper
          SQLFLUFF

      - name: Lint dbt models
        run: |
          sqlfluff lint dbt/models --format github-annotation
        continue-on-error: true
EOF
```

### Step 3: Create Python/Airflow CI Workflow (1 hour)

```bash
cat > python-ci.yml <<'EOF'
name: Python CI

on:
  pull_request:
    paths:
      - 'airflow/**'
      - 'scripts/**'
      - '.github/workflows/python-ci.yml'

env:
  PYTHON_VERSION: '3.11'

jobs:
  pylint:
    name: Pylint
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}

      - name: Install dependencies
        run: |
          pip install pylint
          pip install apache-airflow==2.8.1
          pip install astronomer-cosmos==1.4.0
          pip install apache-airflow-providers-amazon==8.13.0

      - name: Create pylintrc
        run: |
          cat > .pylintrc <<'PYLINTRC'
          [MASTER]
          disable=
              C0111,  # missing-docstring
              C0103,  # invalid-name
              R0913,  # too-many-arguments
              R0914,  # too-many-locals
              W0212,  # protected-access
              W0511,  # fixme

          max-line-length=120

          [BASIC]
          good-names=i,j,k,ex,_,id

          [FORMAT]
          indent-string='    '
          PYLINTRC

      - name: Lint Airflow DAGs
        run: |
          pylint airflow/dags/*.py --rcfile=.pylintrc
        continue-on-error: true

  dag-validation:
    name: DAG Validation
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}

      - name: Install Airflow
        run: |
          pip install apache-airflow==2.8.1
          pip install astronomer-cosmos==1.4.0
          pip install apache-airflow-providers-amazon==8.13.0
          pip install boto3

      - name: Validate DAG files
        run: |
          cd airflow/dags
          for dag in *.py; do
            echo "Validating $dag"
            python -c "exec(open('$dag').read())" || exit 1
          done

  pytest:
    name: Pytest
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}

      - name: Install dependencies
        run: |
          pip install pytest pytest-cov
          pip install apache-airflow==2.8.1
          pip install astronomer-cosmos==1.4.0

      - name: Create tests directory if not exists
        run: |
          mkdir -p tests
          touch tests/__init__.py

      - name: Create sample test
        run: |
          cat > tests/test_dags.py <<'PYTEST'
          import pytest
          import os
          import sys
          from pathlib import Path

          # Add airflow/dags to path
          sys.path.insert(0, str(Path(__file__).parent.parent / "airflow" / "dags"))

          def test_dag_imports():
              """Test that all DAG files can be imported"""
              dags_dir = Path(__file__).parent.parent / "airflow" / "dags"
              for dag_file in dags_dir.glob("*.py"):
                  if dag_file.name.startswith("_"):
                      continue
                  print(f"Testing {dag_file.name}")
                  # Basic syntax check
                  with open(dag_file) as f:
                      compile(f.read(), dag_file.name, 'exec')
          PYTEST

      - name: Run pytest
        run: |
          pytest tests/ -v --cov=airflow --cov-report=term-missing
        continue-on-error: true
EOF

# Commit workflows
cd ../..

git add .github/workflows/
git add .tflint.hcl
git add .sqlfluff  # Will be created by workflow

git status
```

---

## Afternoon Session (3 hours)

### Step 4: Configure GitHub Repository Secrets (30 minutes)

**Manual steps in GitHub UI**:

1. Go to repository → Settings → Secrets and variables → Actions
2. Add repository secrets:
   - `AWS_GITHUB_ACTIONS_ROLE`: ARN of IAM role (will create on Day 2)
   - `REDSHIFT_HOST`: Redshift cluster endpoint (for dbt tests)
   - `REDSHIFT_USER`: Redshift username
   - `REDSHIFT_PASSWORD`: Redshift password
   - `REDSHIFT_DBNAME`: Database name

**Create secrets documentation**:
```bash
cat > docs/GITHUB_ACTIONS_SETUP.md <<'EOF'
# GitHub Actions Setup Guide

## Required Secrets

Configure these in: Repository → Settings → Secrets and variables → Actions

### AWS Authentication

- **`AWS_GITHUB_ACTIONS_ROLE`**: ARN of IAM role for GitHub Actions
  - Format: `arn:aws:iam::ACCOUNT_ID:role/github-actions-role`
  - Created in Sprint 9 Day 2

### Database Credentials (for dbt CI)

- **`REDSHIFT_HOST`**: Redshift cluster endpoint
  - Get from: `terraform output -json data | jq -r '.redshift_endpoint'`

- **`REDSHIFT_USER`**: Database username
  - Default: `admin` (or from Secrets Manager)

- **`REDSHIFT_PASSWORD`**: Database password
  - Get from: AWS Secrets Manager secret `data-platform/dev/redshift/master`

- **`REDSHIFT_DBNAME`**: Database name
  - Default: `dev`

## GitHub OIDC Setup

GitHub Actions uses OpenID Connect (OIDC) to authenticate with AWS without long-lived credentials.

**Benefits**:
- No access keys to rotate
- Temporary credentials per workflow run
- Scoped to specific repositories/branches

**Setup** (Day 2):
1. Create OIDC provider in AWS IAM
2. Create IAM role with trust policy for GitHub
3. Attach policies to role
4. Add role ARN to GitHub secrets

## Workflow Triggers

### Terraform CI (`terraform-ci.yml`)
- **Trigger**: Pull request with changes to `terraform/**`
- **Jobs**: fmt, validate, tflint, plan
- **Duration**: ~3 minutes

### dbt CI (`dbt-ci.yml`)
- **Trigger**: Pull request with changes to `dbt/**`
- **Jobs**: compile, test, sqlfluff
- **Duration**: ~5 minutes

### Python CI (`python-ci.yml`)
- **Trigger**: Pull request with changes to `airflow/**` or `scripts/**`
- **Jobs**: pylint, dag-validation, pytest
- **Duration**: ~2 minutes

## Testing CI Workflows

### Test Terraform CI

```bash
# Make a change to Terraform
echo "# Test comment" >> terraform/environments/dev/variables.tf

# Create branch and PR
git checkout -b test/terraform-ci
git add terraform/
git commit -m "test: Trigger Terraform CI"
git push origin test/terraform-ci

# Create PR via GitHub UI or gh CLI
gh pr create --title "Test Terraform CI" --body "Testing CI workflow"
```

### Test dbt CI

```bash
# Make a change to dbt
echo "-- Test comment" >> dbt/models/staging/stg_customers.sql

# Create branch and PR
git checkout -b test/dbt-ci
git add dbt/
git commit -m "test: Trigger dbt CI"
git push origin test/dbt-ci
gh pr create --title "Test dbt CI" --body "Testing dbt CI workflow"
```

### Test Python CI

```bash
# Make a change to Airflow DAG
echo "# Test comment" >> airflow/dags/dbt_daily_transform.py

# Create branch and PR
git checkout -b test/python-ci
git add airflow/
git commit -m "test: Trigger Python CI"
git push origin test/python-ci
gh pr create --title "Test Python CI" --body "Testing Python CI workflow"
```

## Viewing Workflow Results

### Via GitHub UI
1. Go to repository → Actions tab
2. Select workflow run
3. View job logs
4. Check annotations for errors

### Via GitHub CLI
```bash
# List recent workflow runs
gh run list

# View specific run
gh run view <run-id>

# Watch run in real-time
gh run watch
```

## Troubleshooting

### Workflow not triggering

**Check**:
- Branch protection rules don't block workflows
- Paths in `on.pull_request.paths` match changed files
- Workflow file syntax is valid (use yamllint)

### Authentication failed

**Check**:
- `AWS_GITHUB_ACTIONS_ROLE` secret is set
- IAM role trust policy includes GitHub OIDC
- Role has necessary permissions

### dbt test fails

**Check**:
- Redshift credentials in secrets
- dbt profiles.yml uses environment variables
- Network access to Redshift (GitHub Actions IPs)

## Best Practices

✅ **Use caching** for dependencies (pip, terraform providers)
✅ **Run tests in parallel** where possible
✅ **Set job timeouts** to prevent runaway workflows
✅ **Use `continue-on-error`** sparingly
✅ **Comment PR with results** (terraform plan, test coverage)

❌ **Don't store secrets in code**
❌ **Don't use `actions/checkout@v1`** (deprecated)
❌ **Don't skip validation** in CI

EOF
```

### Step 5: Create Pre-commit Configuration (1 hour)

```bash
# Create pre-commit config
cat > .pre-commit-config.yaml <<'EOF'
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
        args: ['--unsafe']  # Allow custom YAML tags
      - id: check-added-large-files
        args: ['--maxkb=1000']
      - id: check-json
      - id: check-merge-conflict
      - id: detect-private-key

  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.86.0
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_tflint
        args:
          - --args=--config=__GIT_WORKING_DIR__/.tflint.hcl

  - repo: https://github.com/sqlfluff/sqlfluff
    rev: 3.0.0
    hooks:
      - id: sqlfluff-lint
        files: \.sql$
        args: ['--dialect', 'redshift']

  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.1.9
    hooks:
      - id: ruff
        args: ['--fix', '--exit-non-zero-on-fix']

  - repo: local
    hooks:
      - id: dag-validation
        name: Validate Airflow DAGs
        entry: python
        language: system
        files: airflow/dags/.*\.py$
        pass_filenames: false
        args: ['-c', 'import sys; sys.path.insert(0, "airflow/dags"); [__import__(f.replace("/", ".").replace(".py", "")) for f in sys.argv[1:]]']
EOF

# Install pre-commit
pip install pre-commit

# Install hooks
pre-commit install

# Run on all files (optional)
pre-commit run --all-files
```

### Step 6: Create CI Testing Documentation (1 hour 30 minutes)

```bash
cd docs

cat > CI_CD_WORKFLOWS.md <<'EOF'
# CI/CD Workflows Documentation

## Overview

**CI (Continuous Integration)**: Automated testing on every pull request
**CD (Continuous Deployment)**: Automated deployment on merge to main/develop

---

## CI Workflows

### 1. Terraform CI

**Workflow**: `.github/workflows/terraform-ci.yml`
**Trigger**: PR with changes to `terraform/**`

**Jobs**:
1. **terraform-fmt**: Check formatting
2. **terraform-validate**: Validate configuration
3. **tflint**: Lint Terraform code
4. **terraform-plan**: Generate plan (comments on PR)

**Duration**: ~3 minutes

**Example PR**:
```bash
# Make Terraform change
echo "# Comment" >> terraform/environments/dev/main.tf

# Create PR
git checkout -b fix/terraform-update
git commit -am "fix: Update terraform configuration"
git push origin fix/terraform-update
gh pr create --title "Update Terraform" --body "Description"
```

### 2. dbt CI

**Workflow**: `.github/workflows/dbt-ci.yml`
**Trigger**: PR with changes to `dbt/**`

**Jobs**:
1. **dbt-compile**: Compile models
2. **dbt-test**: Run tests
3. **sqlfluff-lint**: Lint SQL code

**Duration**: ~5 minutes

**Example PR**:
```bash
# Add new dbt model
cat > dbt/models/staging/stg_new_table.sql <<SQL
SELECT * FROM raw.new_table
SQL

# Create PR
git checkout -b feat/new-staging-model
git add dbt/
git commit -m "feat: Add new staging model"
git push origin feat/new-staging-model
gh pr create
```

### 3. Python CI

**Workflow**: `.github/workflows/python-ci.yml`
**Trigger**: PR with changes to `airflow/**` or `scripts/**`

**Jobs**:
1. **pylint**: Lint Python code
2. **dag-validation**: Validate DAG syntax
3. **pytest**: Run tests

**Duration**: ~2 minutes

**Example PR**:
```bash
# Update Airflow DAG
vim airflow/dags/dbt_daily_transform.py

# Create PR
git checkout -b feat/update-dag
git add airflow/
git commit -m "feat: Update DAG schedule"
git push origin feat/update-dag
gh pr create
```

---

## CD Workflows (Day 2)

### 1. Docker Build & Push

**Workflow**: `.github/workflows/docker-build.yml`
**Trigger**: Push to `main` or `develop`

**Jobs**:
1. Build dbt Docker image
2. Scan with Trivy
3. Push to ECR
4. Tag with git SHA

### 2. Deploy to Dev

**Workflow**: `.github/workflows/deploy-dev.yml`
**Trigger**: Push to `develop`

**Jobs**:
1. Apply Terraform changes
2. Sync Airflow DAGs to S3
3. Update ECS task definition

---

## Workflow Files

```
.github/workflows/
├── terraform-ci.yml       # Terraform validation
├── dbt-ci.yml            # dbt testing
├── python-ci.yml         # Python/Airflow linting
├── docker-build.yml      # Docker image build (Day 2)
└── deploy-dev.yml        # Dev deployment (Day 2)
```

---

## Branch Strategy

**Main branches**:
- `main`: Production (protected)
- `develop`: Development (protected)

**Feature branches**:
- `feat/*`: New features
- `fix/*`: Bug fixes
- `chore/*`: Maintenance
- `test/*`: Testing changes

**Workflow**:
1. Create feature branch from `develop`
2. Make changes
3. Push and create PR to `develop`
4. CI runs automatically
5. After approval, merge to `develop`
6. CD deploys to dev environment
7. When ready, PR from `develop` to `main`

---

## Status Checks

### Required Checks (Branch Protection)

**For `develop`**:
- terraform-fmt
- terraform-validate
- dbt-compile
- dag-validation

**For `main`**:
- All develop checks
- Manual approval
- terraform-plan

### Optional Checks

- pylint (can merge with warnings)
- sqlfluff-lint (can merge with warnings)
- pytest (can merge if no tests exist)

---

## Caching Strategy

### Terraform

```yaml
- uses: actions/cache@v4
  with:
    path: terraform/.terraform
    key: ${{ runner.os }}-terraform-${{ hashFiles('**/.terraform.lock.hcl') }}
```

### Python/pip

```yaml
- uses: actions/setup-python@v5
  with:
    python-version: '3.11'
    cache: 'pip'
```

### dbt

```yaml
- uses: actions/cache@v4
  with:
    path: dbt/dbt_packages
    key: ${{ runner.os }}-dbt-${{ hashFiles('dbt/packages.yml') }}
```

---

## Cost Optimization

### GitHub Actions Minutes

**Free tier**: 2,000 minutes/month (public repos unlimited)

**Our usage estimate**:
- Terraform CI: ~3 min/PR
- dbt CI: ~5 min/PR
- Python CI: ~2 min/PR
- Total per PR: ~10 minutes

**Monthly estimate** (20 PRs/month):
- CI: 20 PRs × 10 min = 200 minutes
- CD: 20 merges × 5 min = 100 minutes
- **Total**: ~300 minutes/month (well within free tier)

### Optimization Tips

1. ✅ Use caching for dependencies
2. ✅ Run jobs in parallel
3. ✅ Use `paths` filters to skip unnecessary runs
4. ✅ Set job timeouts
5. ✅ Use `continue-on-error` for optional checks

---

## Monitoring

### Via GitHub UI

1. Actions tab → Workflow runs
2. Click run → View jobs → View logs
3. Check annotations for errors

### Via Email

Configure in: Settings → Notifications
- Workflow failures
- Required check failures

### Via Slack (Optional)

Use GitHub app for Slack:
- `/github subscribe owner/repo workflows:{event:"pull_request"}`

---

## Troubleshooting

### Workflow not running

**Check**:
- Workflow file in `.github/workflows/`
- YAML syntax valid (use `yamllint`)
- `paths` filter matches changed files
- Branch protection doesn't block workflows

### Authentication errors

**Check**:
- Secrets are set (Settings → Secrets)
- IAM role ARN is correct
- Role trust policy allows GitHub OIDC

### Tests failing

**Check**:
- Tests pass locally
- Dependencies installed correctly
- Environment variables set
- Secrets available to workflow

### Slow workflows

**Optimize**:
- Add caching
- Reduce test scope
- Run jobs in parallel
- Skip optional checks

---

## Next Steps

**Day 2**:
- GitHub OIDC provider setup
- Docker build/push workflow
- Deploy to dev workflow

**Day 3**:
- Branch protection rules
- End-to-end testing
- Milestone Release 2

EOF
```

---

## End of Day 1 Checklist

- [x] Terraform CI workflow created
- [x] dbt CI workflow created
- [x] Python/Airflow CI workflow created
- [x] TFLint configuration
- [x] SQLFluff configuration
- [x] Pylint configuration
- [x] Pre-commit hooks configured
- [x] GitHub Actions documentation created
- [x] CI/CD workflows documented

---

## 📝 Daily Standup Notes

**Completed Today**:
- Created 3 CI workflows (Terraform, dbt, Python)
- Configured linting tools (TFLint, SQLFluff, Pylint)
- Set up pre-commit hooks
- Comprehensive GitHub Actions documentation
- CI testing procedures documented

**Blockers**:
- GitHub OIDC setup needed (Day 2)
- Repository secrets need to be configured manually

**Tomorrow's Plan**:
- Configure GitHub OIDC provider in AWS
- Create IAM role for GitHub Actions
- Docker build/push workflow
- Deploy to dev workflow

---

## 🎯 Success Metrics

```bash
# Workflow files exist
ls -la .github/workflows/
# Should show: terraform-ci.yml, dbt-ci.yml, python-ci.yml

# Pre-commit hooks installed
pre-commit run --all-files
# Should show checks running

# Workflows validate
cd .github/workflows
for workflow in *.yml; do
  echo "Validating $workflow"
  yamllint $workflow || echo "Install yamllint: pip install yamllint"
done
```

---

## ⏭️ Next: Day 2

Tomorrow: GitHub OIDC setup, Docker build workflow, deploy to dev workflow

**See [day-2.md](./day-2.md)** 🚀
