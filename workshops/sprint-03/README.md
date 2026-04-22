# Sprint 3 Workshop: S3 Storage & Data Lake Foundation

**Duration**: Days 7-9 (3 days)

**Goal**: Create S3 data lake structure with lifecycle policies and EventBridge integration

---

## Overview

In Sprint 3, you'll:
- Create S3 buckets for all data zones (raw, processed, artifacts)
- Implement data lake folder structure
- Configure S3 lifecycle policies
- Set up EventBridge rules for S3 events
- Upload and test sample data

---

## Prerequisites

Before starting Sprint 3, ensure:
- ✅ Sprint 2 completed successfully
- ✅ VPC and networking infrastructure deployed
- ✅ Terraform backend working
- ✅ AWS CLI configured

---

## Daily Breakdown

### Day 1: S3 Bucket Creation & Lifecycle Policies
- Create storage Terraform module
- Deploy S3 buckets (raw-data, dbt-artifacts, mwaa)
- Configure bucket policies and encryption
- Implement lifecycle policies (IA, Glacier transitions)
- Create folder structure in buckets

### Day 2: EventBridge Integration & Sample Data
- Create EventBridge rule for S3 object creation
- Configure event notifications
- Prepare sample datasets (CSV, JSON, Parquet)
- Create Python script to simulate data drops
- Test EventBridge triggers

### Day 3: Validation, Demo & Retrospective
- Upload sample data to S3
- Verify EventBridge rule triggers
- Document S3 bucket structure
- Conduct sprint demo
- Sprint retrospective

---

## Acceptance Criteria

By end of Sprint 3:
- ✅ 3 S3 buckets created with encryption
- ✅ Sample data uploaded successfully
- ✅ EventBridge rule triggers on S3 events
- ✅ Bucket policies enforce encryption
- ✅ Versioning enabled on critical buckets

---

## Key Deliverables

1. **S3 Buckets**:
   - `{project}-raw-data-dev`
   - `{project}-dbt-artifacts-dev`
   - `{project}-mwaa-dev`

2. **Folder Structure**:
   - `/landing/{source}/{YYYY-MM-DD}/`
   - `/raw/{source}/{table}/{YYYY-MM-DD}/`
   - `/processed/{domain}/{table}/{YYYY-MM-DD}/`

3. **EventBridge Rule**: S3 object created in `/landing/` → triggers event

4. **Sample Datasets**: CSV, JSON, Parquet files for testing

---

## Estimated Story Points

**Total**: 13 points

- S3 setup: 5 points
- EventBridge: 3 points
- Sample data: 2 points
- Validation & demo: 3 points

---

## Workshop Materials

Full day-by-day workshop materials will guide you through:
- Creating the storage Terraform module
- Configuring S3 bucket policies
- Setting up EventBridge rules
- Testing data ingestion workflows

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| S3 costs escalate with versioning | Short lifecycle for dev (30 days) |
| EventBridge doesn't trigger MWAA yet | MWAA not deployed until Sprint 7 |
| Data validation missing | Will be addressed in Sprint 13 |

---

## Next Sprint Preview

**Sprint 4**: Redshift Cluster & Database Setup
- Deploy Redshift cluster in private subnets
- Configure database schemas
- Set up Redshift Spectrum
- Connect dbt to Redshift

---

## Resources

- [AWS S3 Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/best-practices.html)
- [EventBridge S3 Events](https://docs.aws.amazon.com/AmazonS3/latest/userguide/EventBridge.html)
- [S3 Lifecycle Policies](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html)

---

👉 **Note**: Detailed day-by-day workshop materials (day-1.md, day-2.md, day-3.md) follow the same format as Sprint 1 and 2. Create them as needed based on the SPRINT_PLANNING.md deliverables.
