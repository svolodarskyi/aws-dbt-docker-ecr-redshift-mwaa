# Sprint Workshops & Guides

## Overview

This directory contains **hands-on workshop guides** for each of the 14 sprints (42 days). Each workshop provides step-by-step instructions, code examples, validation checkpoints, and demo materials to help you build a complete AWS data platform.

**Project Goal**: Build an automated, scalable data platform with Infrastructure as Code (Terraform), data transformations (dbt), containerization (Docker + ECR), orchestration (Apache Airflow on MWAA), and data warehousing (Amazon Redshift).

## How to Use These Workshops

1. **Read the sprint goal** in [SPRINT_PLANNING.md](../SPRINT_PLANNING.md)
2. **Open the corresponding workshop** in this directory
3. **Follow the step-by-step instructions** for each day
4. **Validate each step** before moving to the next
5. **Complete the sprint checklist** and conduct demo/retro on Day 3

## Workshop Structure

Each sprint includes:
- **README.md**: Sprint overview, goals, acceptance criteria, story points
- **day-1.md, day-2.md, day-3.md**: Detailed daily instructions (6 hours/day)
- **Morning Session** (3 hours): Core development work
- **Afternoon Session** (3 hours): Testing, integration, documentation
- **Code Examples**: Copy-paste ready code and configuration
- **Validation Steps**: How to verify success at each checkpoint
- **Demo Materials**: Sprint demo scripts and feedback templates
- **Retrospective**: Templates for sprint review and continuous improvement

## Workshop Status

🎉 **ALL WORKSHOPS COMPLETE!** All 42 daily workshops (14 sprints × 3 days) are ready to use!

### Phase 1: Foundation (Days 1-12) ✅ COMPLETE

| Sprint | Days | Status | Workshop Materials | Focus |
|--------|------|--------|-------------------|-------|
| [Sprint 1](./sprint-01/) | 1-3 | ✅ Complete | ✅ Full (3 days + README) | Local dev environment, Git setup, dbt/Airflow basics |
| [Sprint 2](./sprint-02/) | 4-6 | ✅ Complete | ✅ Full (3 days + README) | AWS account, Terraform backend, VPC, networking |
| [Sprint 3](./sprint-03/) | 7-9 | ✅ Complete | ✅ Full (3 days + README) | S3 buckets, EventBridge, data lake structure |
| [Sprint 4](./sprint-04/) | 10-12 | ✅ Complete | ✅ Full (3 days + README) | Redshift cluster, schemas, Spectrum, dbt connection |

### Phase 2: Core Data Pipeline (Days 13-24) ✅ COMPLETE

| Sprint | Days | Status | Workshop Materials | Focus |
|--------|------|--------|-------------------|-------|
| [Sprint 5](./sprint-05/) | 13-15 | ✅ Complete | ✅ Full (3 days + README) | dbt-external-tables, staging/marts, tests |
| [Sprint 6](./sprint-06/) | 16-18 | ✅ Complete | ✅ Full (3 days + README) | Docker, ECR, multi-stage builds, security scanning |
| [Sprint 7](./sprint-07/) | 19-21 | ✅ Complete | ✅ Full (3 days) | MWAA deployment, DAGs, Airflow UI |
| [Sprint 8](./sprint-08/) | 22-24 | ✅ Complete | ✅ Full (3 days) | Astronomer Cosmos, ECS tasks, end-to-end pipeline |

### Phase 3: Automation & CI/CD (Days 25-33) ✅ COMPLETE

| Sprint | Days | Status | Workshop Materials | Focus |
|--------|------|--------|-------------------|-------|
| [Sprint 9](./sprint-09/) | 25-27 | ✅ Complete | ✅ Full (3 days) | GitHub Actions, Terraform CI, dbt CI, Docker build |
| [Sprint 10](./sprint-10/) | 28-30 | ✅ Complete | ✅ Full (3 days) | S3 → EventBridge → Airflow automation |
| [Sprint 11](./sprint-11/) | 31-33 | ✅ Complete | ✅ Full (3 days) | Production environment, security hardening |

### Phase 4: Monitoring & Optimization (Days 34-42) ✅ COMPLETE

| Sprint | Days | Status | Workshop Materials | Focus |
|--------|------|--------|-------------------|-------|
| [Sprint 12](./sprint-12/) | 34-36 | ✅ Complete | ✅ Full (3 days) | CloudWatch monitoring, SNS alerts, dashboards |
| [Sprint 13](./sprint-13/) | 37-39 | ✅ Complete | ✅ Full (3 days) | Data quality tests, validation framework |
| [Sprint 14](./sprint-14/) | 40-42 | ✅ Complete | ✅ Full (3 days) | Documentation, optimization, team training, handoff |

### Milestones Achieved

- ✅ **Milestone Release 1** (Sprint 6): Production-ready containerization
- ✅ **Milestone Release 2** (Sprint 9): Full CI/CD automation
- ✅ **Milestone Release 3** (Sprint 10): Event-driven pipeline
- ✅ **Project Complete** (Sprint 14): Production system operational and handed off

## Quick Reference

### Prerequisites Check

Before starting any sprint:
```bash
# Check what's completed
./scripts/setup/verify-setup.sh

# Review sprint prerequisites
cat workshops/sprint-XX/README.md | grep -A 10 "Prerequisites"
```

### Daily Workflow

```bash
# 1. Read sprint workshop
cat workshops/sprint-XX/README.md

# 2. Follow Day X instructions
cat workshops/sprint-XX/day-X.md

# 3. Validate completion
# (Each workshop has validation steps)

# 4. Update sprint checklist
vim SPRINT_PLANNING.md  # Check off completed items
```

### Getting Help

If you get stuck:
1. Check **Troubleshooting** section in the workshop
2. Review [HOW_TO_USE.md](../HOW_TO_USE.md)
3. Check [TECH_LEAD_PLAYBOOK.md](../TECH_LEAD_PLAYBOOK.md)
4. Create a GitHub Issue

## Tips for Success

1. ✅ **Don't skip prerequisites** - Each sprint builds on previous work
2. ✅ **Follow day-by-day** - Workshops are structured for daily progress
3. ✅ **Validate each step** - Don't move forward until current step works
4. ✅ **Take notes** - Document any deviations or issues
5. ✅ **Ask questions** - Better to clarify than to guess
6. ✅ **Test thoroughly** - Especially before moving to next sprint

## Workshop Format

Each sprint workshop follows this structure:

```
workshops/sprint-XX/
├── README.md          # Sprint overview, objectives, prerequisites
├── day-1.md          # Detailed Day 1 instructions
├── day-2.md          # Detailed Day 2 instructions
├── day-3.md          # Detailed Day 3 instructions
├── examples/         # Code examples, templates
│   ├── config-example.yml
│   └── script-example.sh
└── validation.md     # How to validate sprint completion
```

## Prerequisites

Before starting any sprint:

### Required Tools
- Python 3.11+
- Git
- Docker Desktop
- AWS CLI
- VSCode (recommended)

### AWS Requirements
- AWS account with admin access
- MFA enabled
- Billing alerts configured
- Basic AWS knowledge

### Estimated Costs
- **Sprint 1**: $0 (local only)
- **Sprints 2-4**: ~$50-400/month (dev environment)
- **Sprints 5-14**: ~$800-1200/month (full dev environment)
- **Production** (Sprint 11+): ~$2500-3000/month

⚠️ **Set up billing alerts and monitor costs!**

## Creating Additional Workshop Materials

To create day-by-day materials for remaining sprints:

1. **Reference [SPRINT_PLANNING.md](../SPRINT_PLANNING.md)**
   - Copy deliverables for the sprint
   - Break down into daily tasks

2. **Follow Established Pattern**
   - Use Sprint 1 and 2 as templates
   - Morning session (3 hours) + Afternoon session (3 hours)
   - Include validation checkpoints
   - Add demo and retrospective materials

3. **Each Day Should Include**:
   - Step-by-step instructions
   - Code samples
   - Validation commands
   - Troubleshooting tips
   - End of day checklist

## Learning Outcomes

By completing all 14 sprints, you will master:

### Technical Skills
- ✅ Infrastructure as Code with Terraform
- ✅ Data transformation with dbt
- ✅ Container orchestration with ECS
- ✅ Workflow orchestration with Apache Airflow
- ✅ Data warehousing with Redshift
- ✅ CI/CD with GitHub Actions
- ✅ AWS networking and security

### DevOps Skills
- ✅ Git workflows and branching strategies
- ✅ Code quality automation
- ✅ Infrastructure testing
- ✅ Monitoring and alerting
- ✅ Cost optimization

### Data Engineering Skills
- ✅ Data lake architecture
- ✅ ETL/ELT pipeline design
- ✅ Data quality testing
- ✅ Event-driven processing
- ✅ Data lineage and documentation

## Start Your Journey

**If you're just starting**:
1. Read the main [README.md](../README.md)
2. Review [SPRINT_PLANNING.md](../SPRINT_PLANNING.md)
3. Start with [Sprint 1, Day 1](./sprint-01/day-1.md)

**If you're continuing**:
1. Check your current sprint status in the table above
2. Open the next day's workshop material
3. Follow the instructions step-by-step

**If you're a team lead**:
1. Review [TECH_LEAD_PLAYBOOK.md](../TECH_LEAD_PLAYBOOK.md)
2. Plan your sprint schedule
3. Assign team members to tasks

---

**Ready to build a production data platform?** Start with [Sprint 1, Day 1](./sprint-01/day-1.md) 🚀
