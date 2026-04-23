# AWS Data Engineering Platform

## Project Overview

A modern, cloud-native data engineering platform built on AWS, featuring automated data ingestion, transformation, and orchestration using industry best practices.

## Architecture Components

- **Orchestration**: Apache Airflow on AWS MWAA
- **Data Transformation**: dbt (Data Build Tool) containerized on ECS/Fargate
- **Data Warehouse**: Amazon Redshift Spectrum
- **Data Lake**: Amazon S3
- **Container Registry**: Amazon ECR
- **Infrastructure as Code**: Terraform (state in S3, locks in DynamoDB)
- **CI/CD**: GitHub Actions → AWS CodePipeline/CodeBuild
- **Monitoring**: CloudWatch with SNS email notifications
- **Version Control**: GitHub

## Key Features

- **Event-Driven Architecture**: S3 event triggers initiate data processing pipelines
- **External Tables**: dbt-external-tables for S3 data access
- **Environment Separation**: Local dev environment, containerized prod deployment
- **Automated Deployments**: CI/CD pipeline for infrastructure and application code
- **Airflow-dbt Integration**: Cosmos library for seamless orchestration
- **Comprehensive Monitoring**: CloudWatch metrics, logs, and alarms

## Use Cases

1. **Real-time Analytics Platform**: Process streaming data dropped into S3 for real-time dashboards
2. **ETL Automation**: Automated data pipelines from various sources to data warehouse
3. **Data Lake to Warehouse**: Transform raw S3 data into structured Redshift tables
4. **Multi-tenant SaaS Analytics**: Process customer data with isolated pipelines
5. **IoT Data Processing**: Handle high-volume sensor data from S3 to analytics-ready format
6. **Compliance Reporting**: Automated regulatory report generation from source data
7. **ML Feature Engineering**: Prepare training datasets for machine learning models

## Documentation

### Core Documentation
- [Architecture Design](./ARCHITECTURE.md) - Complete system architecture and design decisions
- [Tech Lead Playbook](./TECH_LEAD_PLAYBOOK.md) - Detailed setup and implementation guide
- [Sprint Planning](./SPRINT_PLANNING.md) - Project timeline and sprint breakdown
- [Project Summary](./PROJECT_SUMMARY.md) - Overview of project structure and components

### Getting Started
- [Getting Started Guide](./GETTING_STARTED.md) - Initial setup and prerequisites
- [Bootstrap Guide](./BOOTSTRAP_GUIDE.md) - AWS account and infrastructure bootstrap
- [Quick Start](./docs/QUICKSTART.md) - Fast-track setup for experienced users
- [How to Use](./HOW_TO_USE.md) - Day-to-day development workflow

### Operations
- [Deployment Guide](./DEPLOYMENT_GUIDE.md) - CI/CD and deployment procedures
- [Changes Summary](./CHANGES_SUMMARY.md) - Recent updates and modifications

### Workshop Series

Complete 14-sprint, 42-day hands-on workshop series covering the entire platform from scratch to production:

**Foundation (Weeks 1-2)**
- [Sprint 1: Development Environment Setup](./workshops/sprint-01/) - Local environment and AWS basics
- [Sprint 2: AWS Infrastructure Foundation](./workshops/sprint-02/) - VPC, IAM, S3, Terraform state
- [Sprint 3: S3 Data Lake Setup](./workshops/sprint-03/) - Data lake architecture and S3 configuration
- [Sprint 4: Redshift Data Warehouse](./workshops/sprint-04/) - Redshift cluster and Spectrum setup

**Core Pipeline (Weeks 3-4)**
- [Sprint 5: dbt Transformation Layer](./workshops/sprint-05/) - dbt models, tests, and documentation
- [Sprint 6: Docker Containerization](./workshops/sprint-06/) - ✅ Milestone Release 1
- [Sprint 7: Apache Airflow Setup](./workshops/sprint-07/) - AWS MWAA environment and DAGs
- [Sprint 8: ECS Integration](./workshops/sprint-08/) - Fargate tasks and dbt orchestration

**Automation (Weeks 5-6)**
- [Sprint 9: Full CI/CD Pipeline](./workshops/sprint-09/) - ✅ Milestone Release 2
- [Sprint 10: Event-Driven Pipeline](./workshops/sprint-10/) - ✅ Milestone Release 3 (EventBridge)
- [Sprint 11: Production Environment](./workshops/sprint-11/) - Multi-env setup and security hardening

**Production Ready (Weeks 7-8)**
- [Sprint 12: Monitoring & Alerting](./workshops/sprint-12/) - CloudWatch dashboards and alarms
- [Sprint 13: Data Quality Framework](./workshops/sprint-13/) - 50+ tests and validation framework
- [Sprint 14: Optimization & Handoff](./workshops/sprint-14/) - 🎉 Project Complete

See [workshops/README.md](./workshops/README.md) for complete workshop overview and navigation.

## Quick Start

**New to the project?** Start with [Getting Started Guide](./GETTING_STARTED.md)

**Want hands-on training?** Follow the [Workshop Series](./workshops/) (14 sprints, 42 days)

**Ready to deploy?** See [Tech Lead Playbook](./TECH_LEAD_PLAYBOOK.md) for detailed implementation
