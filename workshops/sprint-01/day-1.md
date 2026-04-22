# Sprint 1 - Day 1: Environment Setup & Git

**Goal**: Set up local development environment and initialize Git repository

**Duration**: ~6 hours

**Outcome**: Working Python environment, Git repository initialized, dependencies installed

---

## Morning Session (3 hours)

### Step 1: System Prerequisites Check (30 minutes)

Verify all required tools are installed:

```bash
# Check Python version (must be 3.11+)
python3 --version
# Expected: Python 3.11.x or higher

# Check Docker
docker --version
# Expected: Docker version 20.x or higher

docker ps
# Should show running containers (or empty list if none running)

# Check Git
git --version
# Expected: git version 2.x

# Check available disk space (need at least 10GB)
df -h .
```

**If any checks fail**, install missing tools:
- Python: Use `pyenv` or download from python.org
- Docker: Install Docker Desktop
- Git: Install via package manager or git-scm.com

### Step 2: Clone or Initialize Repository (15 minutes)

**Option A: Starting from this template**
```bash
# You already have the files, just initialize Git
cd /Users/erfolg/Documents/projects/data/aws-dbt-docker-ecr-redshift-mwaa

# Initialize Git repository
git init

# Check status
git status
# Should show all untracked files
```

**Option B: Clone from GitHub** (if already pushed)
```bash
# Clone repository
git clone https://github.com/your-org/aws-data-platform.git
cd aws-data-platform
```

### Step 3: Create Python Virtual Environment (15 minutes)

```bash
# Ensure you're in project root
pwd
# Should end with: /aws-dbt-docker-ecr-redshift-mwaa

# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate

# Verify activation (should show venv path)
which python
# Expected: .../venv/bin/python

# Upgrade pip
pip install --upgrade pip

# Verify pip version
pip --version
# Expected: pip 24.x or higher
```

**✅ Validation**: Running `which python` should show the venv path.

### Step 4: Install Python Dependencies (30 minutes)

```bash
# Still in project root, venv activated

# Install development dependencies
pip install -r requirements-dev.txt

# This installs:
# - dbt-core, dbt-redshift
# - pytest, black, pylint
# - pre-commit
# - terraform-compliance
# and more...

# May take 5-10 minutes depending on internet speed
```

**⚠️ Troubleshooting**:
- If `psycopg2` fails: Install PostgreSQL dev libraries
  - macOS: `brew install postgresql`
  - Ubuntu: `sudo apt-get install libpq-dev`
- If any package fails: Check Python version is 3.11+

**✅ Validation**:
```bash
# Verify dbt installed
dbt --version
# Should show dbt version 1.7.x

# Verify pytest installed
pytest --version
# Should show pytest version

# Verify black installed
black --version
# Should show black version
```

### Step 5: Configure Git (30 minutes)

```bash
# Set up Git identity (if not already configured)
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# Verify configuration
git config --list | grep user

# Configure Git aliases (optional but helpful)
git config --global alias.st status
git config --global alias.co checkout
git config --global alias.br branch
git config --global alias.cm commit

# Test alias
git st
# Should show: On branch master / No commits yet
```

Create `.gitignore` if not present:
```bash
# Verify .gitignore exists
cat .gitignore

# Should include:
# - venv/
# - __pycache__/
# - *.pyc
# - .env
# - terraform.tfstate*
# - dbt/target/
# - dbt/logs/
```

**✅ Validation**: `git config --list` shows your name and email

---

## Afternoon Session (3 hours)

### Step 6: Initial Git Commit (1 hour)

```bash
# Check current status
git status
# Should show many untracked files

# Stage all files
git add .

# Check what's staged
git status
# Should show files "Changes to be committed"

# Create initial commit
git commit -m "Initial setup: AWS Data Engineering Platform

- Complete project structure
- Infrastructure code (Terraform)
- dbt models framework
- Airflow DAGs templates
- CI/CD pipelines (GitHub Actions)
- Documentation and guides
- Setup scripts

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

# Verify commit
git log
# Should show your commit
```

**✅ Validation**: `git log` shows 1 commit

### Step 7: Create Branch Structure (30 minutes)

```bash
# Rename current branch to main (if needed)
git branch -M main

# Create develop branch
git checkout -b develop

# Verify branches
git branch
# Should show:
#   * develop
#     main

# Push to remote (if using GitHub)
# First, create repository on GitHub, then:
git remote add origin https://github.com/your-org/aws-data-platform.git
git push -u origin main
git push -u origin develop

# Set develop as current branch
git checkout develop
```

**✅ Validation**: `git branch` shows main and develop branches

### Step 8: Set Up Project Documentation (1 hour)

Update README with team-specific information:

```bash
# Edit README.md
vim README.md

# Add to the top:
## Team Information

- **Team**: Data Engineering
- **Tech Lead**: [Your Name]
- **Project Start**: [Today's Date]
- **Sprint**: 1/14 (Project Setup)

## Getting Started

1. Read [HOW_TO_USE.md](./HOW_TO_USE.md)
2. Follow [workshops/sprint-01/README.md](./workshops/sprint-01/README.md)
3. Check [SPRINT_PLANNING.md](./SPRINT_PLANNING.md) for daily tasks
```

Create a team-specific .env.local:

```bash
# Copy example
cp .env.example .env.local

# Edit with placeholder values
vim .env.local

# Update these (real values will come later):
PROJECT_NAME=data-platform
ENVIRONMENT=dev
AWS_REGION=us-east-1
```

**✅ Validation**: README has team info, .env.local exists

### Step 9: Verify Everything Works (30 minutes)

Run the verification script:

```bash
# Make sure script is executable
chmod +x scripts/setup/verify-setup.sh

# Run verification
./scripts/setup/verify-setup.sh

# Expected output:
# ✓ Python environment
# ✓ dbt installation
# ✓ Docker
# ✓ .env.local
# ⚠ AWS credentials (expected to fail - not set up yet)
# ⚠ dbt packages (expected to fail - will install tomorrow)
```

Manual verification checklist:
```bash
# 1. Python environment active
echo $VIRTUAL_ENV
# Should show venv path

# 2. dbt installed
dbt --version

# 3. Git repository initialized
git log

# 4. Correct branch
git branch
# Should show develop with asterisk

# 5. Files not tracked
git status
# Should be clean or show only .env.local (ignored)
```

**✅ Validation**: Verification script passes (except expected failures)

---

## End of Day 1 Checklist

Before ending Day 1, verify:

- [x] Python 3.11+ installed
- [x] Virtual environment created and activated
- [x] Dependencies installed (`pip install -r requirements-dev.txt`)
- [x] Git repository initialized
- [x] Initial commit created
- [x] Main and develop branches created
- [x] .gitignore configured
- [x] .env.local created from template
- [x] README updated with team info
- [x] Verification script passes (with expected failures)

## 📝 Daily Standup Notes

Document for tomorrow's standup:

**Completed Today**:
- Set up local Python environment
- Initialized Git repository
- Installed all dependencies
- Created branch structure

**Blockers**:
- None (or list any issues)

**Tomorrow's Plan**:
- Configure pre-commit hooks
- Set up Docker environment
- Test local Airflow (optional)

## 🎯 Success Metric

**You're successful if**: You can run these commands without errors:
```bash
source venv/bin/activate
dbt --version
git log
git branch
```

---

## ⏭️ Next: Day 2

Tomorrow you'll:
- Set up pre-commit hooks for code quality
- Configure Docker environment
- Test local Airflow (if time permits)

**See you tomorrow!** Open [day-2.md](./day-2.md) when ready. 🚀
