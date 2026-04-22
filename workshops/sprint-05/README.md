# Sprint 5 Workshop: dbt Core Models & External Tables

**Duration**: Days 13-15 (3 days)

**Goal**: Build dbt transformation pipeline with external tables

---

## Overview

In Sprint 5, you'll:
- Configure dbt-external-tables package for Glue integration
- Create external tables pointing to S3 data
- Build staging models with data cleaning and type casting
- Create intermediate models for deduplication
- Build mart models (dimensions and facts)
- Implement comprehensive dbt tests
- Generate and review dbt documentation

---

## Prerequisites

Before starting Sprint 5, ensure:
- ✅ Sprint 4 completed successfully
- ✅ Redshift cluster operational
- ✅ S3 buckets with sample data
- ✅ dbt installed and configured
- ✅ Glue Data Catalog database created
- ✅ `dbt debug --target dev` passes

---

## Daily Breakdown

### Day 1: External Tables Setup
**Duration**: 6 hours

**Morning Session**:
- Configure dbt packages.yml with dbt-external-tables
- Run `dbt deps` to install packages
- Create `models/external/sources.yml` defining S3 sources
- Configure Glue catalog settings
- Create external table definitions
- Generate external tables: `dbt run-operation stage_external_sources`

**Afternoon Session**:
- Verify external tables in Redshift
- Query external tables to validate data
- Document external table schema
- Add tests to external sources
- Troubleshoot any Glue/Spectrum issues

**Deliverables**:
- dbt-external-tables package installed
- External sources defined in sources.yml
- External tables created in Glue
- Queries returning data from S3

---

### Day 2: Staging and Intermediate Models
**Duration**: 6 hours

**Morning Session**:
- Create staging models (stg_sales__orders, stg_sales__customers)
- Implement data type casting and basic transformations
- Add column aliases and standardization
- Configure materialization strategies (view vs table)
- Add staging model tests (not_null, unique)

**Afternoon Session**:
- Create intermediate models (int_customers_deduped)
- Implement deduplication logic
- Add data quality checks
- Test intermediate transformations
- Document intermediate layer purpose

**Deliverables**:
- 2+ staging models created
- 1+ intermediate models created
- Schema.yml documentation
- Tests passing

---

### Day 3: Mart Models, Tests & Demo
**Duration**: 6 hours

**Morning Session**:
- Create dimension tables (customers_dim)
- Create fact tables (orders_fct)
- Implement business logic and aggregations
- Add relationship tests (foreign keys)
- Configure incremental models (if applicable)

**Afternoon Session**:
- Run full dbt pipeline: `dbt run --target dev`
- Run all tests: `dbt test --target dev`
- Generate documentation: `dbt docs generate && dbt docs serve`
- Review data lineage graph
- Prepare sprint demo
- Conduct retrospective

**Deliverables**:
- Dimension and fact tables created
- All dbt tests passing (100%)
- dbt docs generated and reviewed
- Sprint demo delivered

---

## Acceptance Criteria

By end of Sprint 5:
- ✅ External tables created via dbt
- ✅ Staging models materialize successfully
- ✅ All dbt tests pass (100%)
- ✅ Data lineage documented
- ✅ dbt docs accessible and comprehensive

---

## Data Model Structure

```
models/
├── external/
│   ├── sources.yml           # S3 external sources
│   └── ext_sales_data.sql    # External table definitions
│
├── staging/
│   ├── schema.yml            # Staging documentation & tests
│   ├── stg_sales__orders.sql
│   ├── stg_sales__customers.sql
│   └── stg_sales__products.sql
│
├── intermediate/
│   ├── schema.yml
│   ├── int_customers_deduped.sql
│   └── int_orders_enriched.sql
│
└── marts/
    ├── core/
    │   ├── schema.yml
    │   ├── customers_dim.sql
    │   ├── products_dim.sql
    │   ├── orders_fct.sql
    │   └── order_items_fct.sql
    └── marketing/
        └── (future marts)
```

---

## Sample Data Pipeline

**End-to-End Flow**:
```
S3 (raw_data bucket)
  /landing/sales/orders.csv
         ↓
  Glue Data Catalog
    external_sales_orders
         ↓
  Redshift External Schema
    raw_schema.ext_sales_orders
         ↓
  dbt Staging Model
    staging_schema.stg_sales__orders
         ↓
  dbt Intermediate Model
    staging_schema.int_orders_enriched
         ↓
  dbt Mart Model
    analytics_schema.orders_fct
```

---

## dbt Tests Implementation

### Source Tests (sources.yml)
```yaml
sources:
  - name: raw_sales
    tables:
      - name: ext_sales_orders
        columns:
          - name: order_id
            tests:
              - not_null
              - unique
```

### Staging Tests (staging/schema.yml)
```yaml
models:
  - name: stg_sales__orders
    columns:
      - name: order_id
        tests:
          - unique
          - not_null
      - name: customer_id
        tests:
          - not_null
          - relationships:
              to: ref('stg_sales__customers')
              field: customer_id
```

### Custom Tests
- Row count thresholds
- Freshness checks
- Referential integrity
- Business rule validation

---

## Materialization Strategies

| Model Type | Materialization | Reason |
|------------|----------------|--------|
| External | External | Source data in S3 |
| Staging | View | Lightweight, no duplication |
| Intermediate | View | Ephemeral transformations |
| Marts (small) | Table | Fast query performance |
| Marts (large) | Incremental | Efficient updates |

---

## Performance Optimization

### Best Practices
1. **Use Views for Staging**: No data duplication
2. **Tables for Marts**: Pre-computed for analytics
3. **Sort/Dist Keys**: Add to Redshift tables
4. **Incremental Models**: For large fact tables
5. **Partition External Tables**: By date in S3

### Example Sort/Dist Key Configuration
```sql
{{
  config(
    materialized='table',
    sort='order_date',
    dist='customer_id'
  )
}}
```

---

## Estimated Story Points

**Total**: 21 points

- External tables setup: 8 points
- Staging models: 5 points
- Intermediate models: 3 points
- Mart models: 5 points

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Data type mismatches (S3 vs Redshift) | Explicit casting in staging models |
| Large S3 files cause OOM | Partition data by date, limit external table scope |
| External table performance issues | Use Redshift tables for frequently queried data |
| Test failures on edge cases | Start with basic tests, expand iteratively |

---

## Key SQL Transformations

### Staging: Type Casting
```sql
SELECT
    order_id::INTEGER,
    customer_id::INTEGER,
    order_date::DATE,
    order_amount::DECIMAL(10,2),
    UPPER(TRIM(status)) AS status,
    CURRENT_TIMESTAMP AS loaded_at
FROM {{ source('raw_sales', 'ext_sales_orders') }}
```

### Intermediate: Deduplication
```sql
WITH ranked_customers AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY updated_at DESC
        ) AS row_num
    FROM {{ ref('stg_sales__customers') }}
)
SELECT *
FROM ranked_customers
WHERE row_num = 1
```

### Mart: Aggregation
```sql
SELECT
    o.order_id,
    o.customer_id,
    c.customer_name,
    o.order_date,
    SUM(oi.quantity * oi.unit_price) AS total_amount,
    COUNT(oi.item_id) AS item_count
FROM {{ ref('stg_sales__orders') }} o
JOIN {{ ref('stg_sales__order_items') }} oi ON o.order_id = oi.order_id
JOIN {{ ref('customers_dim') }} c ON o.customer_id = c.customer_id
GROUP BY 1, 2, 3, 4
```

---

## Testing Strategy

### Levels of Testing
1. **Source Tests**: Data quality at ingestion
2. **Staging Tests**: Column-level validation
3. **Intermediate Tests**: Transformation logic
4. **Mart Tests**: Business rule compliance
5. **Integration Tests**: End-to-end data flow

### Test Coverage Goals
- **Staging**: 100% of PK/FK columns
- **Intermediate**: Critical transformation logic
- **Marts**: All dimensions and facts
- **Overall**: >80% column coverage

---

## Documentation Requirements

### What to Document
- [ ] Model purpose and business logic
- [ ] Column descriptions
- [ ] Data lineage (upstream dependencies)
- [ ] Refresh frequency
- [ ] Known limitations
- [ ] Example queries

### dbt docs Features
- Lineage graph (DAG visualization)
- Column-level documentation
- Test results
- Compiled SQL
- Source freshness

---

## Common Issues & Solutions

### Issue: dbt-external-tables not found
**Solution**:
```bash
# Add to packages.yml
packages:
  - package: dbt-labs/dbt_external_tables
    version: 0.8.7

# Install
dbt deps
```

### Issue: External table returns no data
**Solution**:
- Check S3 path in sources.yml
- Verify IAM role attached to Redshift
- Test Spectrum query directly in Redshift
- Check Glue Data Catalog

### Issue: Tests failing
**Solution**:
- Run individual model: `dbt run --select model_name`
- Check compiled SQL: `target/compiled/.../model_name.sql`
- Test in Redshift directly
- Review data quality in source

---

## Next Sprint Preview

**Sprint 6**: Docker Containerization for dbt
- Create optimized Dockerfile
- Multi-stage builds
- Push to Amazon ECR
- Container security scanning
- **Milestone Release 1**: Container ready for orchestration

---

## Resources

- [dbt Documentation](https://docs.getdbt.com/)
- [dbt-external-tables Package](https://github.com/dbt-labs/dbt-external-tables)
- [Redshift Spectrum](https://docs.aws.amazon.com/redshift/latest/dg/c-using-spectrum.html)
- [dbt Best Practices](https://docs.getdbt.com/guides/best-practices)

---

👉 **Workshop materials**: Detailed day-by-day guides (day-1.md, day-2.md, day-3.md) follow the same format as Sprint 1 and 2. Create them based on the deliverables above.
