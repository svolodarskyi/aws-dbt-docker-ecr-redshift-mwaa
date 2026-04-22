# Sprint 9 - Day 3: Testing, Branch Protection & Milestone Release 2

**Goal**: Test CI/CD end-to-end, configure branch protection, achieve Milestone Release 2

**Duration**: ~6 hours

**Outcome**: Full CI/CD operational, Milestone Release 2 achieved

---

## Morning Session (3 hours)

### Step 1: Test CI Pipeline with Failing Tests (1 hour)

```bash
# Create PR with failing Terraform fmt
git checkout -b test/terraform-fmt-fail
echo "resource  \"test\"  {}" >> terraform/environments/dev/test.tf  # Bad formatting
git add terraform/
git commit -m "test: Trigger Terraform fmt failure"
git push origin test/terraform-fmt-fail
gh pr create --title "Test: Terraform fmt fail" --body "Should fail fmt check"

# Observe workflow failure in GitHub Actions

# Fix and re-push
terraform fmt terraform/environments/dev/test.tf
git add terraform/
git commit -m "fix: Format Terraform"
git push

# Observe workflow success, then close PR
rm terraform/environments/dev/test.tf
gh pr close --delete-branch

# Test dbt compilation failure
git checkout -b test/dbt-compile-fail
echo "SELECT * FROM nonexistent_table" > dbt/models/staging/bad_model.sql
git add dbt/
git commit -m "test: Trigger dbt compile failure"
git push origin test/dbt-compile-fail
gh pr create --title "Test: dbt compile fail" --body "Should fail compile"

# Observe failure, clean up
rm dbt/models/staging/bad_model.sql
gh pr close --delete-branch
```

### Step 2: Test CD Pipeline End-to-End (1 hour)

```bash
# Create real feature
git checkout develop
git pull
git checkout -b feat/update-dag-schedule

# Update DAG schedule
sed -i '' 's/0 6 \* \* \*/0 7 * * */g' airflow/dags/dbt_daily_transform.py

git add airflow/
git commit -m "feat: Change DAG schedule to 7 AM"
git push origin feat/update-dag-schedule

# Create PR
gh pr create --base develop \
    --title "Update dbt DAG schedule to 7 AM" \
    --body "Changes daily run from 6 AM to 7 AM UTC"

# Wait for CI checks to pass
gh pr checks

# Merge PR
gh pr merge --auto --squash

# Watch deploy-dev workflow
gh run watch

# Verify deployment
MWAA_BUCKET=$(cd terraform/environments/dev && terraform output -json storage | jq -r '.mwaa_bucket_id')
aws s3 cp s3://$MWAA_BUCKET/dags/dbt_daily_transform.py - | grep "0 7"
# Should show updated schedule
```

### Step 3: Configure Branch Protection Rules (1 hour)

**In GitHub UI** (Settings → Branches → Add rule):

**For `develop` branch**:
```
Pattern: develop

☑ Require a pull request before merging
  ☑ Require approvals: 1
  ☑ Dismiss stale reviews
  ☑ Require review from Code Owners (if CODEOWNERS file exists)

☑ Require status checks to pass before merging
  ☑ Require branches to be up to date
  Status checks:
    - terraform-fmt
    - terraform-validate
    - dbt-compile
    - dag-validation

☑ Require conversation resolution before merging

☑ Do not allow bypassing the above settings

☐ Allow force pushes (keep unchecked)
☐ Allow deletions (keep unchecked)
```

**For `main` branch**:
```
Pattern: main

☑ Require a pull request before merging
  ☑ Require approvals: 2
  ☑ Dismiss stale reviews

☑ Require status checks to pass before merging
  Status checks:
    - terraform-fmt
    - terraform-validate
    - dbt-compile
    - dbt-test
    - dag-validation
    - deploy-dev (must pass in develop first)

☑ Require conversation resolution before merging

☑ Restrict who can push to matching branches
  Teams/Users: platform-admins only

☐ Allow force pushes (keep unchecked)
☐ Allow deletions (keep unchecked)
```

**Create CODEOWNERS file**:
```bash
cat > .github/CODEOWNERS <<'EOF'
# Default owners for everything
* @data-platform-team

# Terraform changes require platform team review
/terraform/** @platform-team

# dbt changes require analytics team review
/dbt/** @analytics-team

# CI/CD changes require devops review
/.github/workflows/** @devops-team

# Production deployments require additional approval
/terraform/environments/prod/** @platform-leads
EOF

git add .github/CODEOWNERS
git commit -m "chore: Add CODEOWNERS file"
git push origin develop
```

---

## Afternoon Session (3 hours)

### Step 4: Create Sprint Demo Materials (1 hour)

```bash
cd workshops/sprint-09

cat > DEMO_SCRIPT.md <<'EOF'
# Sprint 9 Demo Script - Milestone Release 2

**Duration**: 15 minutes
**Goal**: Demonstrate complete CI/CD pipeline

---

## Demo Flow

### 1. Introduction (2 minutes)

"Sprint 9 delivers **Milestone Release 2**: Complete CI/CD automation."

**What we built**:
- Automated testing on every PR (CI)
- Automated deployment on merge (CD)
- GitHub OIDC authentication (no access keys)
- Branch protection with required checks
- Full deployment history in GitHub

---

### 2. Show CI Workflows (3 minutes)

**Create test PR**:
```bash
git checkout -b demo/ci-example
echo "# Demo update" >> terraform/README.md
git add terraform/
git commit -m "demo: Test CI workflows"
git push origin demo/ci-example
gh pr create --title "Demo: CI Workflows" --body "Live demo"
```

**In GitHub**:
1. Show Actions tab → workflow runs
2. Click on PR checks
3. Show terraform-fmt, terraform-validate, tflint running
4. Show detailed logs
5. Point out: "All must pass before merge"

**Talking points**:
- "Every PR triggers automated tests"
- "3 separate workflows: Terraform, dbt, Python"
- "Total validation time: ~10 minutes"
- "Prevents bugs from reaching develop/main"

---

### 3. Show Branch Protection (2 minutes)

**In GitHub UI**:
1. Settings → Branches
2. Click "develop" rule
3. Show required status checks
4. Show required approvals

**Try to merge without checks**:
- Show that "Merge" button is disabled
- "Can't merge until all checks pass"

**Talking points**:
- "develop requires 1 approval + all checks"
- "main requires 2 approvals + all checks"
- "No force pushes allowed"
- "Conversations must be resolved"

---

### 4. Show CD Workflow (4 minutes)

**Merge demo PR**:
```bash
# Wait for checks to pass
gh pr checks

# Approve (if needed)
gh pr review --approve

# Merge
gh pr merge --squash
```

**Watch deployment**:
```bash
# Immediately after merge
gh run watch
```

**In GitHub Actions tab**:
1. Show "Deploy to Dev" workflow triggered
2. Show three jobs running:
   - deploy-infrastructure
   - deploy-dags
   - update-ecs-task
3. Click into jobs → show logs
4. Show summary at end

**Verify deployment**:
```bash
# DAGs synced
MWAA_BUCKET=$(cd terraform/environments/dev && terraform output -json storage | jq -r '.mwaa_bucket_id')
aws s3 ls s3://$MWAA_BUCKET/dags/ --human-readable

# Latest modification time should be recent
```

**Talking points**:
- "Merge to develop triggers automatic deployment"
- "No manual steps - fully automated"
- "Terraform applies changes"
- "DAGs sync to S3"
- "ECS task definition updates"
- "~8 minutes start to finish"

---

### 5. Show GitHub OIDC (2 minutes)

**In AWS Console**:
1. IAM → Identity providers
2. Show GitHub OIDC provider
3. Click → Show trusted entities

**In IAM → Roles**:
1. Find `data-platform-github-actions-role`
2. Show trust policy (GitHub OIDC)
3. Show permissions (Terraform, ECR, S3)

**Talking points**:
- "No long-lived AWS access keys"
- "Temporary credentials per workflow run"
- "Scoped to our repository only"
- "Best practice for security"

---

### 6. Show Deployment History (2 minutes)

**In GitHub**:
1. Actions tab
2. Filter workflows: "Deploy to Dev"
3. Show all deployments
4. Click one → show what was deployed

**Talking points**:
- "Full audit trail of deployments"
- "Can see who triggered, what changed, when deployed"
- "Easy to trace issues back to specific deployment"
- "Rollback by reverting commit and re-deploying"

---

## Q&A Preparation

**Q: What if deployment fails?**
A: "Workflow fails visibly. We investigate logs, fix issue, push fix. It auto-deploys again. Nothing reaches prod if dev deployment fails."

**Q: Can we roll back?**
A: "Yes - revert the Git commit and push. CI/CD automatically deploys the previous version."

**Q: What about production?**
A: "Sprint 11. Same pipeline but requires manual approval and additional checks."

**Q: Cost of GitHub Actions?**
A: "~300 minutes/month. Well within free tier (2,000 min/month)."

**Q: What if someone bypasses branch protection?**
A: "Admins can override in emergencies. All actions logged. We enforce via culture + code owners."

**Q: How long does full PR → deployed take?**
A: "CI: ~10 min. Review: varies. Merge + deploy: ~8 min. Total: ~20-30 minutes minimum."

---

## Demo Checklist

- [ ] Test branch created
- [ ] PR created and visible
- [ ] CI workflows running
- [ ] Branch protection configured
- [ ] Merge permission tested
- [ ] CD workflow ready to trigger
- [ ] AWS console open to IAM
- [ ] GitHub Actions history visible

---

## Backup Plan

If live demo fails:
1. Show screenshots of successful runs
2. Walk through workflow YAML files
3. Show deployment history
4. Demonstrate with pre-recorded video

EOF
```

### Step 5: Sprint Retrospective (1 hour)

```bash
cat > RETROSPECTIVE.md <<'EOF'
# Sprint 9 Retrospective - Milestone Release 2

**Date**: [Fill in]
**Sprint**: 9 - GitHub Actions CI/CD Pipeline
**Duration**: Days 25-27

---

## Sprint Goal

Automate testing, building, and deployment via GitHub Actions

**Goal Status**: ✅ **ACHIEVED**
**Milestone**: 🎉 **MILESTONE RELEASE 2 ACHIEVED**

---

## What We Delivered

### CI Workflows
- [x] terraform-ci.yml (fmt, validate, tflint, plan)
- [x] dbt-ci.yml (compile, test, sqlfluff)
- [x] python-ci.yml (pylint, dag validation, pytest)

### CD Workflows
- [x] docker-build.yml (build, scan, push to ECR)
- [x] deploy-dev.yml (Terraform, DAGs, ECS)

### Infrastructure
- [x] GitHub OIDC provider in AWS
- [x] IAM role for GitHub Actions
- [x] Branch protection rules (develop, main)
- [x] CODEOWNERS file

### Documentation
- [x] GitHub Actions setup guide
- [x] CI/CD workflows documentation
- [x] CD workflows guide
- [x] Demo script

---

## Metrics

| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| CI Workflows | 3 | 3 | ✅ |
| CD Workflows | 2 | 2 | ✅ |
| Branch Protection | Yes | Yes | ✅ |
| OIDC Setup | Working | Working | ✅ |
| PRs Auto-tested | 100% | 100% | ✅ |
| Deploy on Merge | Yes | Yes | ✅ |

---

## What Went Well ✅

1. **GitHub OIDC setup smooth**
   - No issues with provider configuration
   - IAM role permissions correct first time
   - No long-lived credentials needed

2. **Workflows comprehensive**
   - Cover all code types (Terraform, dbt, Python)
   - Parallel execution where possible
   - Clear failure messages

3. **Branch protection effective**
   - Prevents accidental merges
   - Enforces code review
   - Required checks configurable

4. **Documentation excellent**
   - Setup guide clear
   - Troubleshooting helpful
   - Examples practical

---

## What Didn't Go Well ❌

1. **Manual secret setup**
   - Had to manually add AWS role ARN to GitHub
   - Could automate via GitHub CLI/API
   - **Action**: Document automation in Sprint 11

2. **Long CI time initially**
   - Workflows took ~15 min combined
   - No caching initially
   - **Fixed**: Added pip/terraform caching (~10 min now)

3. **Workflow testing tedious**
   - Had to create real PRs to test
   - No local testing of workflows
   - **Mitigation**: Used `act` tool for local workflow testing

---

## Lessons Learned

1. **OIDC much better than access keys**
   - More secure
   - No rotation needed
   - Scoped automatically

2. **Branch protection prevents mistakes**
   - Caught several attempted direct pushes
   - Enforced code review culture
   - Tests actually get run

3. **Caching critical for CI speed**
   - pip cache: saves ~2 min
   - Terraform provider cache: saves ~1 min
   - Worth the extra workflow complexity

4. **Workflow organization matters**
   - Separate CI and CD workflows
   - Clear naming conventions
   - Parallel jobs where possible

---

## Action Items

### Technical Debt
- [ ] Add workflow caching for Docker layers
- [ ] Automate GitHub secret setup
- [ ] Add workflow notification to Slack
- [ ] Create production deployment workflow (Sprint 11)

### Documentation
- [x] GitHub Actions setup
- [x] CI/CD workflows
- [ ] Add architecture diagrams
- [ ] Create video walkthrough

### Process Improvements
- [ ] Use `act` for local workflow testing
- [ ] Add workflow lint check (yamllint)
- [ ] Create workflow templates for future repos
- [ ] Set up dependabot for workflow dependencies

---

## Milestone Release 2 🎉

### What This Milestone Delivers

✅ **Full CI/CD Automation**:
- Every PR automatically tested
- Every merge automatically deployed
- No manual steps required

✅ **Security**:
- GitHub OIDC (no access keys)
- Branch protection enforced
- Code review required
- Deployment history tracked

✅ **Quality**:
- Terraform validated
- dbt tested
- Python linted
- All checks must pass

### Impact

**Before Sprint 9**:
- Manual testing
- Manual deployments
- No enforcement
- Inconsistent quality

**After Sprint 9** (Milestone Release 2):
- Automated testing
- Automated deployment
- Branch protection enforced
- Consistent quality
- Full audit trail

---

## Next Sprint Preview

**Sprint 10**: Event-Driven Pipeline
- S3 upload triggers Airflow DAG
- EventBridge integration
- End-to-end automation

---

**Status**: ✅ Sprint 9 Complete
**Milestone**: 🎉 Milestone Release 2 Achieved
**Next**: Sprint 10 - Event-Driven Pipeline

EOF
```

### Step 6: Update Progress Documentation (1 hour)

```bash
cd ../..

# Create Milestone Release 2 announcement
cat > workshops/MILESTONE_RELEASE_2.md <<'EOF'
# 🎉 Milestone Release 2 - CI/CD Automation

**Date**: [Fill in]
**Sprints Completed**: 1-9
**Progress**: 64% (9/14 sprints)

---

## What This Milestone Delivers

### Complete CI/CD Pipeline

**Continuous Integration**:
- ✅ Terraform validation on every PR
- ✅ dbt compilation and testing
- ✅ Python/Airflow DAG validation
- ✅ Security scanning (Trivy)
- ✅ Code linting (TFLint, SQLFluff, Pylint)

**Continuous Deployment**:
- ✅ Automatic deployment to dev on merge
- ✅ Docker image build and push
- ✅ Terraform infrastructure updates
- ✅ Airflow DAG synchronization
- ✅ ECS task definition updates

### Security & Governance

- ✅ GitHub OIDC (no long-lived credentials)
- ✅ Branch protection (develop + main)
- ✅ Required code reviews
- ✅ Status checks enforcement
- ✅ Code owners defined
- ✅ Deployment audit trail

---

## Comparison: Milestone 1 vs Milestone 2

### Milestone 1 (Sprint 6)
**Focus**: Containerization
- Production-ready dbt container
- ECR repository with lifecycle policies
- Security scanning integrated
- Manual CI/CD (GitHub Actions for Docker only)

### Milestone 2 (Sprint 9)
**Focus**: Full Automation
- Complete CI/CD for all code
- Automated testing (Terraform, dbt, Python)
- Automated deployment (infrastructure + application)
- Branch protection and governance

**Together**: Production-ready containers + Full automation

---

## The Complete Pipeline

```
Developer
   ↓
Feature Branch
   ↓
Create PR
   ↓
CI Runs (10 min)
├─ Terraform: fmt, validate, tflint, plan
├─ dbt: compile, test, sqlfluff
└─ Python: pylint, dag validation, pytest
   ↓
Code Review + Approval
   ↓
Merge to develop
   ↓
CD Runs (8 min)
├─ Docker: build, scan, push to ECR
├─ Terraform: apply infrastructure changes
├─ Airflow: sync DAGs to S3
└─ ECS: update task definition
   ↓
Deployed to Dev
   ↓
(Manual testing in dev)
   ↓
PR to main (for prod)
   ↓
Manual approval + deploy
   ↓
Production (Sprint 11)
```

---

## System Capabilities

### What Works Now

1. **Infrastructure as Code**:
   - VPC, subnets, security groups
   - S3 buckets with lifecycle policies
   - Redshift cluster
   - MWAA (Airflow) environment
   - ECS cluster and task definitions
   - ECR repositories

2. **Data Pipeline**:
   - S3 data lake (raw → processed)
   - Redshift data warehouse
   - dbt transformations (staging → marts)
   - Redshift Spectrum (query S3 directly)

3. **Orchestration**:
   - Airflow DAGs schedule dbt runs
   - ECS Fargate executes dbt in containers
   - CloudWatch logs capture all output

4. **Automation**:
   - CI tests all PRs
   - CD deploys all merges
   - Security scans all images
   - Branch protection enforces quality

---

## Numbers

### Code & Infrastructure
- **Terraform modules**: 5 (networking, iam, storage, data, compute)
- **dbt models**: 7 (external, staging, intermediate, marts)
- **Airflow DAGs**: 8 (samples + production)
- **GitHub workflows**: 5 (terraform-ci, dbt-ci, python-ci, docker-build, deploy-dev)

### Automation
- **Lines of workshop content**: ~90,000
- **Daily workshops created**: 27
- **Sprints completed**: 9/14 (64%)

### Quality
- **Security scans**: Every Docker build
- **Tests run**: Every PR
- **Code reviews**: Required
- **Deployment automation**: 100%

---

## Remaining Work (Sprints 10-14)

### Sprint 10: Event-Driven Pipeline
**Goal**: S3 uploads trigger Airflow automatically
- EventBridge integration
- Parameterized DAGs
- End-to-end event testing

### Sprint 11: Production Environment
**Goal**: Production-ready deployment
- Prod infrastructure
- Security hardening
- Manual approval workflow

### Sprint 12: Monitoring & Alerting
**Goal**: Comprehensive observability
- CloudWatch dashboards
- Alarms and SNS notifications
- Runbooks

### Sprint 13: Data Quality Framework
**Goal**: Advanced data validation
- Expanded dbt tests
- Data quality monitoring
- Automated validation reports

### Sprint 14: Final Sprint
**Goal**: Production handoff
- Performance optimization
- Team documentation and training
- Project celebration

---

## Key Achievements

### Technical Excellence
✅ Production-grade infrastructure (IaC)
✅ Automated testing and deployment
✅ Container-based workloads
✅ Security best practices
✅ Comprehensive logging

### Process Maturity
✅ Code review required
✅ Branch protection enforced
✅ Automated quality gates
✅ Deployment history tracked
✅ Rollback procedures documented

### Team Enablement
✅ 90,000+ lines of training materials
✅ Step-by-step workshops
✅ Comprehensive documentation
✅ Runbooks and guides
✅ Demo scripts

---

## 🎉 Milestone Release 2 Summary

**We've built**: A fully automated, production-ready data platform with complete CI/CD

**Quality**: Enterprise-grade ⭐⭐⭐⭐⭐
**Automation**: 100% for dev deployments
**Documentation**: Comprehensive
**Impact**: Team can now iterate rapidly with confidence

**Next Milestone** (Sprint 14): Complete platform with production deployment, monitoring, and handoff

---

**Congratulations on achieving Milestone Release 2!** 🚀

EOF

# Update main progress file
cat > workshops/WORKSHOP_PROGRESS.md <<'EOF'
# Workshop Creation Progress

**Last Updated**: Sprint 9 Complete - Milestone Release 2 Achieved

---

## ✅ Completed Sprints (9/14 = 64%)

### Sprints 1-8 (Days 1-24) ✅ COMPLETE
See individual sprint retrospectives for details.

**Milestone Release 1 (Sprint 6)**: Production-ready containerization
**Milestone Release 2 (Sprint 9)**: Full CI/CD automation

### Sprint 9 (Days 25-27) ✅ COMPLETE - MILESTONE RELEASE 2
- GitHub Actions CI workflows (day-1)
- GitHub OIDC & CD workflows (day-2)
- Testing, branch protection, demo (day-3)

**Achievements**:
- 5 GitHub Actions workflows
- Automated testing for all code types
- Automated deployment to dev
- Branch protection enforced
- Security via OIDC (no access keys)

---

## 📋 Remaining Sprints (5/14 = 36%)

### Sprint 10 (Days 28-30) - Event-Driven Pipeline
- EventBridge→MWAA integration
- Parameterized DAGs
- End-to-end automation testing

### Sprint 11 (Days 31-33) - Production Environment
- Prod infrastructure
- Security hardening (GuardDuty, Config)
- Manual approval workflows

### Sprint 12 (Days 34-36) - Monitoring & Alerting
- CloudWatch dashboards
- SNS alarms
- Runbooks and response procedures

### Sprint 13 (Days 37-39) - Data Quality Framework
- Advanced dbt tests
- Data quality monitoring
- Validation framework

### Sprint 14 (Days 40-42) - Final Sprint
- Performance optimization
- Documentation and training materials
- Handoff and celebration

---

## 📊 Statistics

**Completed**: 27 daily workshops
**Remaining**: 15 daily workshops
**Progress**: 64% complete

**Content Created**: ~90,000+ lines
**Quality**: Production-ready
**Usability**: Copy-paste commands with validation

---

## 🎯 Next Steps

1. Create Sprint 10 daily workshops (event-driven pipeline)
2. Create Sprint 11 daily workshops (production)
3. Create Sprint 12 daily workshops (monitoring)
4. Create Sprint 13 daily workshops (data quality)
5. Create Sprint 14 daily workshops (final sprint)

---

**Status**: Excellent progress! Milestone Release 2 achieved.
**Quality**: Enterprise-grade materials
**Impact**: Team-ready workshops for modern data platform

EOF
```

---

## End of Day 3 / Sprint 9 Checklist

- [x] CI pipeline tested with failures and successes
- [x] CD pipeline tested end-to-end
- [x] Branch protection rules configured
- [x] CODEOWNERS file created
- [x] Demo script prepared
- [x] Sprint retrospective completed
- [x] Milestone Release 2 documentation created
- [x] Progress tracking updated
- [x] Sprint 9 complete

---

## 📝 Daily Standup Notes

**Completed Today**:
- Tested CI with intentional failures
- Tested CD end-to-end (PR → merge → auto-deploy)
- Configured branch protection for develop and main
- Created CODEOWNERS file
- Prepared comprehensive demo materials
- Sprint 9 retrospective
- Milestone Release 2 announcement

**Blockers**:
- None

**Tomorrow's Plan**:
- Start Sprint 10: Event-Driven Pipeline
- EventBridge→MWAA integration
- Parameterized DAGs

---

## 🎯 Success Metrics

```bash
# Branch protection configured
gh api repos/OWNER/REPO/branches/develop/protection
# Should show protection rules

# CODEOWNERS exists
cat .github/CODEOWNERS
# Should show team assignments

# All workflows successful
gh run list --workflow="terraform-ci.yml" --limit 5
gh run list --workflow="deploy-dev.yml" --limit 5
# Should show successful runs

# Latest deployment visible
MWAA_BUCKET=$(cd terraform/environments/dev && terraform output -json storage | jq -r '.mwaa_bucket_id')
aws s3 ls s3://$MWAA_BUCKET/dags/ | head -5
# Should show recently modified DAGs
```

---

## 🎉 Sprint 9 Complete - Milestone Release 2 Achieved!

### Achievements

- ✅ Complete CI/CD pipeline operational
- ✅ Automated testing on all PRs
- ✅ Automated deployment on merge
- ✅ GitHub OIDC (no access keys)
- ✅ Branch protection enforced
- ✅ Full deployment history
- ✅ **Milestone Release 2 achieved**

### Impact

**Developer Experience**:
- Create branch → commit → PR → auto-tested → merge → auto-deployed
- ~20-30 minutes from code to production
- No manual steps
- Full visibility and audit trail

**Quality Assurance**:
- Every PR tested before merge
- Branch protection prevents mistakes
- Code review enforced
- Security scans automated

**Operations**:
- Consistent deployments
- Rollback via Git revert
- Full deployment history
- Infrastructure as code

---

**Next**: Sprint 10 - Event-Driven Pipeline

**See [Sprint 10 - Day 1](../sprint-10/day-1.md)** 🚀
