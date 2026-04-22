# Sprint 4 Workshop: Redshift Cluster & Database Setup

**Duration**: Days 10-12 (3 days)

**Goal**: Provision Redshift cluster and configure database schemas

---

## Overview

In Sprint 4, you'll:
- Deploy Redshift cluster in private subnets
- Configure database schemas for data layers
- Set up Redshift Spectrum for querying S3 data
- Create Glue Data Catalog integration
- Connect dbt to Redshift
- Test end-to-end: S3 → Spectrum → Redshift

---

## Prerequisites

Before starting Sprint 4, ensure:
- ✅ Sprint 3 completed successfully
- ✅ S3 buckets with sample data available
- ✅ VPC private subnets operational
- ✅ Security groups configured
- ✅ IAM roles created (Redshift Spectrum role)

---

## Daily Breakdown

### Day 1: Redshift Cluster Provisioning
- Create data Terraform module
- Configure Redshift cluster (dc2.large, 2 nodes for dev)
- Set up Redshift subnet group in private subnets
- Configure Redshift parameter group
- Store master credentials in Secrets Manager
- Attach IAM role for Spectrum

### Day 2: Database Schema Configuration
- Connect to Redshift via SQL client
- Create database schemas:
  - `raw_schema` (external tables via Spectrum)
  - `staging_schema` (dbt staging models)
  - `analytics_schema` (dbt marts)
  - `audit_schema` (metadata and logging)
- Create Glue Data Catalog database
- Create external schema pointing to Glue
- Test Redshift Spectrum queries on S3 data

### Day 3: dbt Connection & Validation
- Update dbt profiles.yml with Redshift connection
- Test dbt connection: `dbt debug --target dev`
- Create sample external table in Glue
- Query external table from Redshift
- Create first dbt model using Spectrum
- Sprint demo and retrospective

---

## Acceptance Criteria

By end of Sprint 4:
- ✅ Redshift cluster accessible from VPC
- ✅ Database schemas created successfully
- ✅ External schema queries S3 data via Spectrum
- ✅ dbt can connect to Redshift
- ✅ Credentials stored in Secrets Manager (not hardcoded)

---

## Key Deliverables

1. **Redshift Cluster**:
   - Type: dc2.large
   - Nodes: 2 (dev environment)
   - Location: Private subnets
   - Encrypted: Yes

2. **Database Schemas**:
   - `raw_schema` - External tables (Spectrum)
   - `staging_schema` - dbt staging layer
   - `analytics_schema` - dbt marts layer
   - `audit_schema` - Audit/metadata

3. **Glue Integration**:
   - Glue Data Catalog database
   - External schema in Redshift
   - Sample external table definitions

4. **dbt Connection**:
   - Updated profiles.yml
   - Successful `dbt debug` test
   - First model querying Spectrum table

---

## Estimated Story Points

**Total**: 21 points

- Redshift provisioning: 8 points
- Schema configuration: 5 points
- Spectrum setup: 5 points
- dbt connection: 3 points

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ S3 Buckets                                          │
│  ├─ raw-data/                                       │
│  │   └─ sample_data.parquet                        │
│  ├─ dbt-artifacts/                                  │
│  └─ mwaa/                                           │
└──────────────────┬──────────────────────────────────┘
                   │
                   │ Redshift Spectrum
                   │ (queries S3 directly)
                   ↓
┌─────────────────────────────────────────────────────┐
│ Redshift Cluster (Private Subnet)                   │
│                                                     │
│  Schemas:                                           │
│  ├─ raw_schema (External - points to Glue)         │
│  ├─ staging_schema (dbt staging models)            │
│  ├─ analytics_schema (dbt marts)                   │
│  └─ audit_schema (metadata)                        │
│                                                     │
│  IAM Role: redshift-spectrum-role                  │
│  Secrets: Stored in AWS Secrets Manager            │
└─────────────────────────────────────────────────────┘
                   ↑
                   │ dbt connection
                   │ (port 5439)
                   │
┌─────────────────────────────────────────────────────┐
│ dbt (Local)                                         │
│  profiles.yml configured with Redshift target       │
└─────────────────────────────────────────────────────┘
```

---

## Costs

**Estimated monthly cost**:
- Redshift dc2.large (2 nodes): ~$360/month
- Glue Data Catalog: Free tier (first million requests)
- **Total**: ~$360/month

**Cost Optimization**:
- Pause cluster during off-hours (nights/weekends)
- Script: `scripts/redshift/pause-cluster.sh`
- Savings: ~50% ($180/month)

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Redshift costs high (~$360/month) | Pause cluster off-hours, automate with Lambda |
| Data catalog confusion (Glue vs Redshift) | Clear documentation, naming conventions |
| Connection issues from local machine | Use bastion host or VPN |
| External tables performance issues | Partition data in S3 by date |

---

## Workshop Materials

Full day-by-day workshop materials will guide you through:
- Provisioning Redshift with Terraform
- Configuring Secrets Manager
- Creating database schemas
- Setting up Glue Data Catalog
- Connecting dbt to Redshift
- Querying S3 data via Spectrum

---

## Testing Checklist

After Sprint 4:
- [ ] Redshift cluster status: available
- [ ] Can connect via SQL client (DBeaver/pgAdmin)
- [ ] All schemas created
- [ ] External schema queries S3 successfully
- [ ] dbt debug passes
- [ ] dbt compile works
- [ ] Sample external table returns data

---

## Next Sprint Preview

**Sprint 5**: dbt Core Models & External Tables
- Configure dbt-external-tables package
- Create staging models using Spectrum
- Build intermediate transformations
- Create mart models (dimensions and facts)
- Implement dbt tests
- Generate dbt documentation

---

## Resources

- [Amazon Redshift Getting Started](https://docs.aws.amazon.com/redshift/latest/gsg/getting-started.html)
- [Redshift Spectrum](https://docs.aws.amazon.com/redshift/latest/dg/c-using-spectrum.html)
- [AWS Glue Data Catalog](https://docs.aws.amazon.com/glue/latest/dg/catalog-and-crawler.html)
- [dbt Redshift Setup](https://docs.getdbt.com/reference/warehouse-setups/redshift-setup)

---

👉 **Note**: Detailed day-by-day workshop materials (day-1.md, day-2.md, day-3.md) follow the same format as Sprint 1 and 2. Create them as needed based on the SPRINT_PLANNING.md deliverables.
