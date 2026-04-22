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

- [Architecture Design](./ARCHITECTURE.md)
- [Tech Lead Playbook](./TECH_LEAD_PLAYBOOK.md)
- [Sprint Planning](./SPRINT_PLANNING.md)
- [Setup Guide](./docs/SETUP.md)
- [Development Workflow](./docs/DEVELOPMENT.md)

## Quick Start

See [TECH_LEAD_PLAYBOOK.md](./TECH_LEAD_PLAYBOOK.md) for detailed setup and implementation guide.
