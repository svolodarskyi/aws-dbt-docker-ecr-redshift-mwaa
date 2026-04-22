# Sprint 5 - Day 2: Intermediate and Mart Models

**Goal**: Build intermediate transformations and final mart models

**Duration**: ~6 hours

**Outcome**: Complete dbt pipeline from external tables to analytics marts

---

## Morning Session (3 hours)

### Step 1: Create Intermediate Models (1 hour 30 minutes)

```bash
cd dbt/models

# Create intermediate directory
mkdir -p intermediate

cd intermediate

# Create int_customers_deduped.sql
cat > int_customers_deduped.sql <<'EOF'
{{
    config(
        materialized='view',
        tags=['intermediate', 'customers']
    )
}}

WITH source AS (
    SELECT * FROM {{ ref('stg_sales__customers') }}
),

deduped AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY source_partition_date DESC, dbt_loaded_at DESC
        ) AS row_num
    FROM source
)

SELECT
    customer_id,
    customer_name,
    email,
    customer_created_date,
    country,
    source_partition_date,
    dbt_loaded_at
FROM deduped
WHERE row_num = 1
EOF

# Create int_orders_enriched.sql
cat > int_orders_enriched.sql <<'EOF'
{{
    config(
        materialized='view',
        tags=['intermediate', 'orders']
    )
}}

WITH orders AS (
    SELECT * FROM {{ ref('stg_sales__orders') }}
),

customers AS (
    SELECT * FROM {{ ref('int_customers_deduped') }}
),

enriched AS (
    SELECT
        o.order_id,
        o.customer_id,
        c.customer_name,
        c.email,
        c.country,
        o.order_date,
        o.order_amount,
        o.status,
        -- Calculated fields
        CASE
            WHEN o.order_amount < 100 THEN 'Small'
            WHEN o.order_amount < 500 THEN 'Medium'
            WHEN o.order_amount < 1000 THEN 'Large'
            ELSE 'Very Large'
        END AS order_size_category,
        DATE_PART('year', o.order_date) AS order_year,
        DATE_PART('month', o.order_date) AS order_month,
        DATE_PART('quarter', o.order_date) AS order_quarter,
        o.source_partition_date,
        o.dbt_loaded_at
    FROM orders o
    LEFT JOIN customers c ON o.customer_id = c.customer_id
)

SELECT * FROM enriched
EOF

# Create schema.yml for intermediate models
cat > schema.yml <<'EOF'
version: 2

models:
  - name: int_customers_deduped
    description: Deduplicated customers (most recent record per customer_id)
    columns:
      - name: customer_id
        description: Unique customer identifier
        tests:
          - unique
          - not_null

  - name: int_orders_enriched
    description: Orders enriched with customer data and calculated fields
    columns:
      - name: order_id
        tests:
          - unique
          - not_null
      - name: customer_id
        tests:
          - not_null
          - relationships:
              to: ref('int_customers_deduped')
              field: customer_id
      - name: order_size_category
        tests:
          - accepted_values:
              values: ['Small', 'Medium', 'Large', 'Very Large']
EOF
```

### Step 2: Create Mart Models - Dimensions (1 hour 30 minutes)

```bash
cd ../marts

# Create core directory for main marts
mkdir -p core

cd core

# Create customers_dim.sql
cat > customers_dim.sql <<'EOF'
{{
    config(
        materialized='table',
        tags=['marts', 'dimensions'],
        dist='customer_id',
        sort='customer_id'
    )
}}

WITH customers AS (
    SELECT * FROM {{ ref('int_customers_deduped') }}
),

customer_metrics AS (
    SELECT
        customer_id,
        COUNT(DISTINCT order_id) AS lifetime_orders,
        SUM(order_amount) AS lifetime_value,
        MIN(order_date) AS first_order_date,
        MAX(order_date) AS last_order_date,
        MAX(order_date) < CURRENT_DATE - INTERVAL '90 days' AS is_churned
    FROM {{ ref('int_orders_enriched') }}
    WHERE status = 'COMPLETED'
    GROUP BY customer_id
),

final AS (
    SELECT
        c.customer_id,
        c.customer_name,
        c.email,
        c.customer_created_date,
        c.country,
        COALESCE(m.lifetime_orders, 0) AS lifetime_orders,
        COALESCE(m.lifetime_value, 0) AS lifetime_value,
        m.first_order_date,
        m.last_order_date,
        DATEDIFF(day, m.first_order_date, m.last_order_date) AS customer_tenure_days,
        CASE
            WHEN m.lifetime_orders = 0 THEN 'Never Purchased'
            WHEN m.lifetime_orders = 1 THEN 'One-Time'
            WHEN m.lifetime_orders <= 5 THEN 'Occasional'
            ELSE 'Frequent'
        END AS customer_segment,
        COALESCE(m.is_churned, false) AS is_churned,
        c.source_partition_date,
        CURRENT_TIMESTAMP AS dbt_updated_at
    FROM customers c
    LEFT JOIN customer_metrics m ON c.customer_id = m.customer_id
)

SELECT * FROM final
EOF

# Create date_dim.sql (useful for time-based analytics)
cat > date_dim.sql <<'EOF'
{{
    config(
        materialized='table',
        tags=['marts', 'dimensions'],
        dist='date_day',
        sort='date_day'
    )
}}

{{ dbt_utils.date_spine(
    datepart="day",
    start_date="cast('2020-01-01' as date)",
    end_date="cast(dateadd(year, 2, current_date) as date)"
   )
}}
EOF
```

---

## Afternoon Session (3 hours)

### Step 3: Create Mart Models - Facts (1 hour 30 minutes)

```bash
# Create orders_fct.sql
cat > orders_fct.sql <<'EOF'
{{
    config(
        materialized='table',
        tags=['marts', 'facts'],
        dist='customer_id',
        sort=['order_date', 'order_id']
    )
}}

WITH orders AS (
    SELECT * FROM {{ ref('int_orders_enriched') }}
),

final AS (
    SELECT
        order_id,
        customer_id,
        order_date,
        order_amount,
        status,
        order_size_category,
        order_year,
        order_month,
        order_quarter,
        country,
        -- Running totals per customer
        SUM(order_amount) OVER (
            PARTITION BY customer_id
            ORDER BY order_date, order_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS customer_running_total,
        -- Order sequence per customer
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY order_date, order_id
        ) AS customer_order_sequence,
        source_partition_date,
        CURRENT_TIMESTAMP AS dbt_updated_at
    FROM orders
)

SELECT * FROM final
EOF

# Create schema.yml for mart models
cat > schema.yml <<'EOF'
version: 2

models:
  - name: customers_dim
    description: Customer dimension table with lifetime metrics
    columns:
      - name: customer_id
        description: Primary key
        tests:
          - unique
          - not_null
      - name: lifetime_value
        description: Total value of all completed orders
        tests:
          - dbt_utils.expression_is_true:
              expression: ">= 0"
      - name: customer_segment
        tests:
          - accepted_values:
              values: ['Never Purchased', 'One-Time', 'Occasional', 'Frequent']

  - name: date_dim
    description: Date dimension for time-based analytics
    columns:
      - name: date_day
        description: Date value
        tests:
          - unique
          - not_null

  - name: orders_fct
    description: Orders fact table with enriched data
    columns:
      - name: order_id
        description: Primary key
        tests:
          - unique
          - not_null
      - name: customer_id
        description: Foreign key to customers_dim
        tests:
          - not_null
          - relationships:
              to: ref('customers_dim')
              field: customer_id
      - name: order_amount
        tests:
          - not_null
          - dbt_utils.expression_is_true:
              expression: "> 0"
EOF
```

### Step 4: Run Full dbt Pipeline (1 hour)

```bash
cd ../../..

# Run all models
dbt run

# Expected output:
# - 2 staging models (views)
# - 2 intermediate models (views)
# - 3 mart models (tables)

# Run all tests
dbt test

# Check results
dbt show --select customers_dim --limit 10

# Verify in Redshift
cd ../scripts/redshift
./connect-redshift.sh
```

**In Redshift**:
```sql
-- Check all models created
SELECT
    schemaname,
    tablename,
    type
FROM (
    SELECT schemaname, tablename, 'table' as type FROM pg_tables
    UNION ALL
    SELECT schemaname, viewname as tablename, 'view' as type FROM pg_views
) x
WHERE schemaname IN ('staging_schema', 'analytics_schema')
ORDER BY schemaname, tablename;

-- Query customer dimension
SELECT * FROM analytics_schema.customers_dim
ORDER BY lifetime_value DESC
LIMIT 10;

-- Query orders fact
SELECT * FROM analytics_schema.orders_fct
ORDER BY order_date DESC
LIMIT 20;

-- Sample analytics query
SELECT
    c.customer_segment,
    COUNT(DISTINCT c.customer_id) AS customer_count,
    SUM(o.order_amount) AS total_revenue,
    AVG(o.order_amount) AS avg_order_value
FROM analytics_schema.customers_dim c
LEFT JOIN analytics_schema.orders_fct o ON c.customer_id = o.customer_id
GROUP BY c.customer_segment
ORDER BY total_revenue DESC;

\q
```

### Step 5: Optimize and Document (30 minutes)

```bash
cd ../../dbt

# Analyze tables for query optimization
cat > macros/analyze_tables.sql <<'EOF'
{% macro analyze_tables() %}
    {% set tables = dbt_utils.get_relations_by_pattern(
        schema_pattern='analytics_schema',
        table_pattern='%'
    ) %}

    {% for table in tables %}
        ANALYZE {{ table }};
    {% endfor %}
{% endmacro %}
EOF

# Run analyze
dbt run-operation analyze_tables

# Generate fresh documentation
dbt docs generate

# Serve docs
dbt docs serve --port 8001
```

---

## End of Day 2 Checklist

- [x] Intermediate models created (deduplication, enrichment)
- [x] Dimension tables created (customers_dim, date_dim)
- [x] Fact tables created (orders_fct)
- [x] All models materialized successfully
- [x] All tests passing
- [x] Tables analyzed and optimized
- [x] dbt documentation updated

---

## 📝 Daily Standup Notes

**Completed Today**:
- Built intermediate layer (dedupe, enrichment)
- Created dimension tables with business metrics
- Created fact tables with running calculations
- All dbt tests passing (20+ tests)
- Updated documentation

**Blockers**:
- None

**Tomorrow's Plan**:
- Add advanced dbt tests
- Generate final documentation
- Performance testing
- Sprint demo preparation
- Retrospective

---

## 🎯 Success Metric

```bash
# All models run
dbt run
# Expected: 7 models (2 staging, 2 intermediate, 3 marts)

# All tests pass
dbt test
# Expected: 20+ tests pass

# Data in mart tables
SELECT COUNT(*) FROM analytics_schema.customers_dim;
SELECT COUNT(*) FROM analytics_schema.orders_fct;
# Both should return counts
```

---

## ⏭️ Next: Day 3

Tomorrow: Testing, documentation, demo

**See [day-3.md](./day-3.md)** 🚀
