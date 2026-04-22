# Sprint 1: Project Setup & Local Development Environment

**Duration**: Days 1-3
**Phase**: Foundation
**Difficulty**: Beginner

## 🎯 Learning Objectives

By the end of this sprint, you will:
- ✅ Set up your local development environment
- ✅ Initialize the Git repository with proper structure
- ✅ Configure pre-commit hooks for code quality
- ✅ Run a sample dbt model locally
- ✅ Create and test a sample Airflow DAG
- ✅ Understand the project structure

## 📋 Prerequisites

### Required Tools
- [ ] Python 3.11+ installed
- [ ] Docker Desktop installed and running
- [ ] Git installed
- [ ] VSCode or preferred IDE
- [ ] Terminal/command line access

### Required Knowledge
- Basic command line usage
- Basic Python knowledge
- Basic SQL knowledge
- Git fundamentals

### Estimated Time
- **Day 1**: 6 hours (setup + Git)
- **Day 2**: 6 hours (pre-commit + Docker)
- **Day 3**: 6 hours (dbt + DAG + demo)

## 📚 Daily Breakdown

### [Day 1: Environment Setup & Git](./day-1.md)
- Clone/initialize repository
- Set up Python virtual environment
- Install dependencies
- Configure Git and create initial commit

### [Day 2: Development Tools](./day-2.md)
- Configure pre-commit hooks
- Set up Docker environment
- Create VSCode workspace settings
- Test Docker with local Airflow

### [Day 3: First Models & Demo](./day-3.md)
- Create sample dbt model
- Create sample Airflow DAG
- Run end-to-end locally
- Sprint demo and retrospective

## 🎓 What You'll Build

### Project Structure
```
aws-data-platform/
├── .git/                    # Git repository
├── .github/workflows/       # CI/CD (prepared, not active yet)
├── venv/                    # Python virtual environment
├── dbt/
│   ├── models/
│   │   └── staging/
│   │       └── stg_sample.sql    # ← You'll create this
│   └── profiles/
├── airflow/
│   └── dags/
│       └── sample_dag.py         # ← You'll create this
└── .pre-commit-config.yaml       # ← You'll configure this
```

### Sample dbt Model
A simple staging model that demonstrates:
- Basic SELECT statement
- dbt configuration
- Column documentation
- Tests (unique, not_null)

### Sample Airflow DAG
A hello-world DAG that demonstrates:
- DAG definition
- Task creation
- Task dependencies
- Scheduling

## ✅ Success Criteria

At the end of Sprint 1, you should be able to:

1. **Environment**
   - [ ] Virtual environment created and activated
   - [ ] All dependencies installed without errors
   - [ ] Pre-commit hooks running on git commit

2. **Git Repository**
   - [ ] Repository initialized with clean history
   - [ ] Main and develop branches created
   - [ ] .gitignore properly configured
   - [ ] First commit pushed to remote (if using GitHub)

3. **dbt**
   - [ ] dbt packages installed (`dbt deps`)
   - [ ] Sample model created
   - [ ] Model compiles without errors (`dbt compile`)
   - [ ] Can generate dbt docs (`dbt docs generate`)

4. **Airflow**
   - [ ] Sample DAG created
   - [ ] DAG imports without errors
   - [ ] DAG visible in local Airflow UI (if Docker Compose used)

5. **Documentation**
   - [ ] Team onboarding guide reviewed
   - [ ] README updated with team-specific info
   - [ ] Sprint notes documented

## 🚀 Getting Started

Ready to begin? Start with Day 1:

```bash
cd workshops/sprint-01
cat day-1.md
```

Or jump straight to the setup:

```bash
# Run the automated setup script
./scripts/setup/local-setup.sh

# Then follow day-1.md for Git setup
```

## 📖 Reference Materials

- [dbt Getting Started](https://docs.getdbt.com/docs/get-started/getting-started/overview)
- [Airflow Tutorial](https://airflow.apache.org/docs/apache-airflow/stable/tutorial.html)
- [Git Basics](https://git-scm.com/book/en/v2/Getting-Started-Git-Basics)
- [Pre-commit Hooks](https://pre-commit.com/)

## 💡 Tips

- **Take your time on Day 1** - A solid foundation saves time later
- **Test each step** - Don't skip validation
- **Document issues** - Create GitHub issues for blockers
- **Ask questions** - Better to clarify early

## 🆘 Troubleshooting

See each day's guide for specific troubleshooting steps. Common issues:

**Issue**: Python version mismatch
→ Use `pyenv` to install Python 3.11+

**Issue**: Docker not starting
→ Ensure Docker Desktop is running and has enough resources

**Issue**: dbt deps fails
→ Check internet connection and packages.yml syntax

## ⏭️ Next Sprint

After completing Sprint 1, you'll move to:
- **Sprint 2**: AWS Account Setup & Terraform Foundation
- Prerequisites: AWS account ready, Terraform installed

---

**Let's get started!** Open [day-1.md](./day-1.md) to begin. 🚀
