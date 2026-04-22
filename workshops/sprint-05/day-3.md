# Sprint 5 - Day 3: Testing, Documentation & Demo

**Goal**: Comprehensive testing, complete documentation, sprint demo

**Duration**: ~6 hours

**Outcome**: dbt pipeline fully tested and documented, Sprint 5 complete

---

## Morning Session (3 hours)

### Step 1: Add Advanced dbt Tests (1 hour 30 minutes)

```bash
cd dbt

# Create custom test macros
mkdir -p tests/generic

cat > tests/generic/test_row_count_threshold.sql <<'EOF'
{% test row_count_threshold(model, min_rows=1) %}

SELECT COUNT(*) as row_count
FROM {{ model }}
HAVING COUNT(*) < {{ min_rows }}

{% endtest %}
EOF

cat > tests/generic/test_percent_null.sql <<'EOF'
{% test percent_null(model, column_name, max_percent=0.1) %}

WITH validation AS (
    SELECT
        SUM(CASE WHEN {{ column_name }} IS NULL THEN 1 ELSE 0 END) AS null_count,
        COUNT(*) AS total_count
    FROM {{ model }}
)

SELECT *
FROM validation
WHERE (null_count::FLOAT / total_count) > {{ max_percent }}

{% endtest %}
EOF

# Add tests to schema.yml
cat >> models/marts/core/schema.yml <<'EOF'

  # Additional tests
  - name: customers_dim
    tests:
      - dbt_utils.row_count_threshold:
          min_rows: 1
    columns:
      - name: email
        tests:
          - percent_null:
              max_percent: 0.05  # Max 5% null emails

  - name: orders_fct
    tests:
      - dbt_utils.row_count_threshold:
          min_rows: 1
      - dbt_utils.unique_combination_of_columns:
          combination_of_columns:
            - order_id
            - customer_id
    columns:
      - name: order_date
        tests:
          - dbt_utils.expression_is_true:
              expression: ">= '2020-01-01'"
EOF

# Run all tests
dbt test

# Run tests with store_failures
dbt test --store-failures

# View test results in audit schema
```

### Step 2: Create Data Quality Reports (1 hour)

```bash
# Create custom analysis queries
mkdir -p analyses

cat > analyses/data_quality_summary.sql <<'EOF'
-- Data Quality Summary Report

WITH test_results AS (
    SELECT
        'dbt Tests' AS check_type,
        COUNT(*) AS total_checks,
        SUM(CASE WHEN status = 'pass' THEN 1 ELSE 0 END) AS passed,
        SUM(CASE WHEN status = 'fail' THEN 1 ELSE 0 END) AS failed
    FROM {{ ref('dbt_test_results') }}
    WHERE executed_at >= CURRENT_DATE
),

row_counts AS (
    SELECT
        'Row Counts' AS check_type,
        3 AS total_checks,  -- Number of mart tables
        CASE WHEN
            (SELECT COUNT(*) FROM {{ ref('customers_dim') }}) > 0 AND
            (SELECT COUNT(*) FROM {{ ref('orders_fct') }}) > 0
        THEN 2 ELSE 0 END AS passed,
        0 AS failed
)

SELECT * FROM test_results
UNION ALL
SELECT * FROM row_counts
EOF

cat > analyses/model_execution_times.sql <<'EOF'
-- Model Execution Performance

SELECT
    model_name,
    status,
    execution_time_seconds,
    rows_affected,
    materialization
FROM {{ ref('dbt_run_results') }}
WHERE executed_at >= CURRENT_DATE - 7
ORDER BY execution_time_seconds DESC
LIMIT 20
EOF

# Compile analyses
dbt compile --select analyses
```

### Step 3: Generate Complete Documentation (30 minutes)

```bash
# Update model descriptions
cat > models/marts/core/_marts_core.yml <<'EOF'
version: 2

models:
  - name: customers_dim
    description: |
      # Customer Dimension

      This table contains one record per customer with aggregated lifetime metrics.

      ## Business Rules
      - Customers are deduped based on most recent partition_date
      - Lifetime metrics calculated from COMPLETED orders only
      - Customers considered churned if no orders in 90+ days

      ## Refresh Schedule
      - Materialized as table
      - Refreshed daily via dbt run

      ## Usage
      Join to orders_fct on customer_id for customer-level analytics

  - name: orders_fct
    description: |
      # Orders Fact Table

      One record per order with enriched customer and date attributes.

      ## Business Rules
      - Includes all order statuses
      - Running totals calculated per customer
      - Order sequence tracked per customer

      ## Refresh Schedule
      - Materialized as table
      - Refreshed daily
EOF

# Generate docs with overview
cat > models/overview.md <<'EOF'
{% docs __overview__ %}
# Data Platform dbt Project

## Project Structure

```
models/
├── external/       # External table definitions (Spectrum)
├── staging/        # Source cleaning & normalization
├── intermediate/   # Business logic & transformations
└── marts/          # Final analytics tables
    └── core/       # Core business entities
```

## Data Flow

1. **External Layer**: Query S3 via Redshift Spectrum
2. **Staging Layer**: Clean, cast, standardize data
3. **Intermediate Layer**: Dedupe, enrich, calculate
4. **Marts Layer**: Final dimension & fact tables

## Naming Conventions

- Staging: `stg_{source}__{entity}`
- Intermediate: `int_{entity}_{verb}`
- Marts: `{entity}_dim` or `{entity}_fct`

## Running the Project

```bash
# Full refresh
dbt run

# Run specific model
dbt run --select customers_dim

# Run with tests
dbt build
```
{% enddocs %}
EOF

# Generate docs
dbt docs generate

# Create docs site export
dbt docs generate --target prod --target-path docs-site
```

---

## Afternoon Session (3 hours)

### Step 4: Performance Testing (1 hour)

```bash
# Connect to Redshift
cd ../scripts/redshift
./connect-redshift.sh
```

**In Redshift**:
```sql
-- Test query performance on marts
EXPLAIN
SELECT
    c.customer_segment,
    COUNT(DISTINCT o.order_id) AS order_count,
    SUM(o.order_amount) AS total_revenue
FROM analytics_schema.customers_dim c
JOIN analytics_schema.orders_fct o ON c.customer_id = o.customer_id
WHERE o.order_date >= CURRENT_DATE - 90
GROUP BY c.customer_segment;

-- Check table statistics
SELECT
    "table",
    size,
    tbl_rows,
    sortkey1,
    unsorted
FROM svv_table_info
WHERE schema = 'analytics_schema'
ORDER BY size DESC;

-- Vacuum and analyze if needed
VACUUM analytics_schema.customers_dim;
VACUUM analytics_schema.orders_fct;
ANALYZE analytics_schema.customers_dim;
ANALYZE analytics_schema.orders_fct;

-- Benchmark query times
SELECT
    query,
    TRIM(querytxt) AS sql_text,
    starttime,
    endtime,
    DATEDIFF(seconds, starttime, endtime) AS duration_seconds
FROM STL_QUERY
WHERE querytxt LIKE '%analytics_schema%'
  AND userid > 1
ORDER BY starttime DESC
LIMIT 10;

\q
```

### Step 5: Prepare Sprint Demo (1 hour)

```bash
cd ../../docs/demos

mkdir -p sprint-05

cat > sprint-05/DEMO_SCRIPT.md <<'EOF'
# Sprint 5 Demo: dbt Models & Data Transformation

## Demo Flow (15 min)

### 1. dbt Project Overview (3 min)

**SHOW**: dbt docs (http://localhost:8001)

- Data lineage graph (external → staging → intermediate → marts)
- 7 models total
- 20+ tests passing

**HIGHLIGHT**:
- External tables query S3 directly
- Staging views clean/normalize
- Marts are materialized tables for performance

### 2. External Tables (2 min)

**SAY**: "We configured dbt-external-tables to create Glue tables"

**SHOW**: Terminal
```bash
dbt run-operation stage_external_sources
```

**SHOW**: Redshift query
```sql
SELECT * FROM spectrum_schema.orders LIMIT 5;
```

### 3. Staging Models (2 min)

**SHOW**: stg_sales__orders.sql code
**HIGHLIGHT**:
- Type casting
- Data cleaning (UPPER, TRIM)
- Column renaming

**SHOW**: Staging data
```sql
SELECT * FROM staging_schema.stg_sales__orders LIMIT 5;
```

### 4. Marts - Analytics Ready (5 min)

**SHOW**: customers_dim table
```sql
SELECT
    customer_segment,
    COUNT(*) as customers,
    AVG(lifetime_value) as avg_ltv
FROM analytics_schema.customers_dim
GROUP BY customer_segment;
```

**RUN**: Business analytics query
```sql
SELECT
    c.customer_segment,
    c.country,
    COUNT(o.order_id) as orders,
    SUM(o.order_amount) as revenue
FROM analytics_schema.customers_dim c
JOIN analytics_schema.orders_fct o ON c.customer_id = o.customer_id
WHERE o.order_date >= CURRENT_DATE - 30
GROUP BY 1, 2
ORDER BY revenue DESC;
```

### 5. Data Quality Tests (3 min)

**SHOW**: Run tests
```bash
dbt test
```

**EXPLAIN**: Tests validate:
- Unique keys
- Not null values
- Referential integrity
- Business rules
- Data freshness

**SHOW**: Test results
- 20+ tests passing
- Schema validation working

## Q&A

**Q**: "How often does this run?"
**A**: "Currently manual. In Sprint 8, we'll automate with Airflow - daily refreshes."

**Q**: "Can we add more data sources?"
**A**: "Yes! Add external tables in sources.yml, create staging models, tests."

**Q**: "Performance?"
**A**: "Marts are tables with dist/sort keys. Queries are fast. External tables slower but save storage."
EOF

cat > sprint-05/FEEDBACK.md <<'EOF'
# Sprint 5 Demo Feedback

**Date**: [Today's Date]
**Attendees**:

## Feedback

-

## Stakeholder Approval

- [ ] Approved
EOF
```

### Step 6: Sprint Demo & Retrospective (1 hour)

```bash
# Conduct demo (30 min)
# - Present following DEMO_SCRIPT.md
# - Show dbt docs live
# - Run sample queries

# Sprint retrospective
cat > ../../retrospectives/sprint-05.md <<'EOF'
# Sprint 5 Retrospective

**Sprint**: 5/14
**Goal**: dbt Core Models & External Tables

## Metrics

| Metric | Target | Actual |
|--------|--------|--------|
| Story Points | 21 | 21 |
| Models Created | 7 | 7 |
| Tests Passing | 15+ | 20+ |

## Accomplishments

✅ External tables via dbt-external-tables
✅ Complete staging layer (views)
✅ Intermediate transformations
✅ Dimension & fact tables
✅ Comprehensive testing
✅ Full documentation

## What Went Well

1. dbt-external-tables package smooth
2. Test framework comprehensive
3. Documentation auto-generated
4. Lineage graph helps understanding

## What Didn't Go Well

1. Initial Spectrum partition configuration tricky
2. Some tests needed iteration
3. Performance tuning needed for large tables

## Lessons Learned

1. Start with simple models, add complexity
2. Write tests early
3. Document as you go
4. Use dbt utils for common patterns

## Action Items for Sprint 6

- Containerize dbt project with Docker
- Optimize Dockerfile size
- Push to ECR
- Scan for vulnerabilities
EOF

# Commit sprint work
cd ../../..

git add -A
git commit -m "feat: complete Sprint 5 - dbt Core Models & External Tables

Day 1:
- Configured dbt-external-tables package
- Created external table definitions
- Built staging models from Spectrum

Day 2:
- Created intermediate models (dedupe, enrichment)
- Built dimension tables (customers_dim, date_dim)
- Created fact table (orders_fct)

Day 3:
- Added 20+ dbt tests (all passing)
- Created data quality reports
- Generated comprehensive documentation
- Conducted sprint demo

All acceptance criteria met ✅
Complete dbt transformation pipeline operational

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

git push origin develop
```

---

## End of Day 3 Checklist

- [x] Advanced dbt tests created
- [x] Custom test macros added
- [x] Data quality reports generated
- [x] Complete documentation with lineage
- [x] Performance testing completed
- [x] Sprint demo delivered
- [x] Retrospective completed
- [x] All work committed

---

## 🎉 Sprint 5 Complete!

### Deliverables

✅ 7 dbt models (external, staging, intermediate, marts)
✅ 20+ data quality tests
✅ Complete documentation with DAG
✅ Performance optimized with dist/sort keys

### Data Flow Established

```
S3 (Parquet/CSV/JSON)
    ↓
External Tables (Spectrum)
    ↓
Staging Models (Views)
    ↓
Intermediate Models (Views)
    ↓
Mart Tables (Materialized)
    ↓
BI Tools / Analytics
```

---

## ⏭️ Next: Sprint 6

**Sprint 6**: Docker Containerization for dbt

**You'll build**:
- Optimized Dockerfile (<500MB)
- Multi-stage build
- ECR repository
- CI/CD for Docker builds
- **Milestone Release 1**

**See `workshops/sprint-06/`** 🚀
