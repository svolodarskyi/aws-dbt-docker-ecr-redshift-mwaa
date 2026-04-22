# Sprint 5 - Day 1: dbt External Tables Setup

**Goal**: Configure dbt-external-tables package and create external tables

**Duration**: ~6 hours

**Outcome**: External tables created via dbt, querying S3 data

---

## Morning Session (3 hours)

### Step 1: Configure dbt-external-tables Package (30 minutes)

```bash
cd dbt

# Create packages.yml if not exists
cat > packages.yml <<'EOF'
packages:
  - package: dbt-labs/dbt_external_tables
    version: 0.8.7
  - package: dbt-labs/dbt_utils
    version: 1.1.1
EOF

# Install packages
dbt deps

# Verify packages installed
ls dbt_packages/

# Expected: dbt_external_tables, dbt_utils
```

### Step 2: Define External Sources (1 hour)

```bash
# Create external models directory
mkdir -p models/external

# Create sources.yml for external tables
cat > models/external/sources.yml <<'EOF'
version: 2

sources:
  - name: raw_sales
    description: Raw sales data from S3
    meta:
      external_location: "s3://data-platform-raw-data-dev/raw/sales/{name}/"
      external_table_type: spectrum

    tables:
      - name: orders
        description: Sales orders
        external:
          location: "s3://data-platform-raw-data-dev/raw/sales/orders/"
          row_format: >
            serde 'org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe'
            with serdeproperties (
              'field.delim'=',',
              'skip.header.line.count'='1'
            )
          table_properties: "('has_encrypted_data'='false')"
          partitions:
            - name: partition_date
              data_type: date
              vals_macro: dbt_external_tables.key_value_pairs
              vals_ref: s3://data-platform-raw-data-dev/raw/sales/orders/
        columns:
          - name: order_id
            data_type: int
            description: Unique order ID
          - name: customer_id
            data_type: int
          - name: order_date
            data_type: date
          - name: order_amount
            data_type: decimal(10,2)
          - name: status
            data_type: varchar(50)

  - name: raw_customers
    description: Customer data from S3
    meta:
      external_location: "s3://data-platform-raw-data-dev/raw/customers/"

    tables:
      - name: customers
        external:
          location: "s3://data-platform-raw-data-dev/raw/customers/"
          row_format: >
            serde 'org.openx.data.jsonserde.JsonSerDe'
          table_properties: "('has_encrypted_data'='false')"
          partitions:
            - name: partition_date
              data_type: date
        columns:
          - name: customer_id
            data_type: int
          - name: customer_name
            data_type: varchar(200)
          - name: email
            data_type: varchar(200)
          - name: created_date
            data_type: date
          - name: country
            data_type: varchar(50)
EOF

# Update dbt_project.yml
cat >> dbt_project.yml <<'EOF'

# External tables configuration
sources:
  data_platform:
    external:
      enabled: true
EOF
```

### Step 3: Generate External Tables (1 hour 30 minutes)

```bash
# Activate environment
source ../.venv/bin/activate
export $(cat .env | xargs)

# Stage external sources (creates tables in Glue/Spectrum)
dbt run-operation stage_external_sources

# Verify tables created in Glue
aws glue get-tables --database-name data_platform_dev

# Connect to Redshift and verify
cd ../scripts/redshift
./connect-redshift.sh
```

**In Redshift**:
```sql
-- Verify external tables exist
SELECT schemaname, tablename, location
FROM svv_external_tables
WHERE schemaname = 'spectrum_schema';

-- Query external table
SELECT * FROM spectrum_schema.orders LIMIT 10;

-- Query JSON data
SELECT * FROM spectrum_schema.customers LIMIT 10;

\q
```

---

## Afternoon Session (3 hours)

### Step 4: Create Staging Models from External Tables (1 hour 30 minutes)

```bash
cd ../../dbt/models/staging

# Create stg_sales__orders.sql
cat > stg_sales__orders.sql <<'EOF'
{{
    config(
        materialized='view',
        tags=['staging', 'sales']
    )
}}

WITH source AS (
    SELECT * FROM {{ source('raw_sales', 'orders') }}
    WHERE partition_date >= CURRENT_DATE - INTERVAL '30 days'
),

cleaned AS (
    SELECT
        order_id::INTEGER AS order_id,
        customer_id::INTEGER AS customer_id,
        order_date::DATE AS order_date,
        order_amount::DECIMAL(10,2) AS order_amount,
        UPPER(TRIM(status)) AS status,
        partition_date::DATE AS source_partition_date,
        CURRENT_TIMESTAMP AS dbt_loaded_at
    FROM source
)

SELECT * FROM cleaned
EOF

# Create stg_sales__customers.sql
cat > stg_sales__customers.sql <<'EOF'
{{
    config(
        materialized='view',
        tags=['staging', 'customers']
    )
}}

WITH source AS (
    SELECT * FROM {{ source('raw_customers', 'customers') }}
    WHERE partition_date >= CURRENT_DATE - INTERVAL '90 days'
),

cleaned AS (
    SELECT
        customer_id::INTEGER AS customer_id,
        TRIM(customer_name) AS customer_name,
        LOWER(TRIM(email)) AS email,
        created_date::DATE AS customer_created_date,
        UPPER(TRIM(country)) AS country,
        partition_date::DATE AS source_partition_date,
        CURRENT_TIMESTAMP AS dbt_loaded_at
    FROM source
)

SELECT * FROM cleaned
EOF

# Create schema.yml for staging models
cat > schema.yml <<'EOF'
version: 2

models:
  - name: stg_sales__orders
    description: Staging model for sales orders
    columns:
      - name: order_id
        description: Unique order identifier
        tests:
          - unique
          - not_null
      - name: customer_id
        description: Customer who placed the order
        tests:
          - not_null
      - name: order_date
        description: Date order was placed
        tests:
          - not_null
      - name: order_amount
        description: Total order amount
        tests:
          - not_null
          - dbt_utils.accepted_range:
              min_value: 0
              inclusive: true
      - name: status
        description: Order status
        tests:
          - accepted_values:
              values: ['COMPLETED', 'PROCESSING', 'PENDING', 'CANCELLED']

  - name: stg_sales__customers
    description: Staging model for customer data
    columns:
      - name: customer_id
        description: Unique customer identifier
        tests:
          - unique
          - not_null
      - name: customer_name
        description: Customer name
        tests:
          - not_null
      - name: email
        description: Customer email (normalized to lowercase)
        tests:
          - not_null
          - dbt_utils.unique_combination_of_columns:
              combination_of_columns:
                - email
      - name: country
        description: Customer country
EOF
```

### Step 5: Run and Test Staging Models (1 hour)

```bash
cd ../..

# Run staging models
dbt run --select staging

# Expected: 2 models (stg_sales__orders, stg_sales__customers)

# Run tests
dbt test --select staging

# View compiled SQL
cat target/compiled/data_platform/models/staging/stg_sales__orders.sql

# Verify in Redshift
cd ../scripts/redshift
./connect-redshift.sh
```

**In Redshift**:
```sql
-- Verify staging views created
SELECT table_name, table_type
FROM information_schema.tables
WHERE table_schema = 'staging_schema'
  AND table_name LIKE 'stg_%';

-- Query staging data
SELECT * FROM staging_schema.stg_sales__orders LIMIT 10;

-- Check row counts
SELECT
    'orders' as source,
    COUNT(*) as row_count
FROM staging_schema.stg_sales__orders
UNION ALL
SELECT
    'customers' as source,
    COUNT(*) as row_count
FROM staging_schema.stg_sales__customers;

\q
```

### Step 6: Document External Tables (30 minutes)

```bash
cd ../../dbt

# Generate dbt docs
dbt docs generate

# Serve docs
dbt docs serve --port 8001

# Open http://localhost:8001
# Review:
# - Data lineage graph (S3 → external tables → staging models)
# - Source freshness
# - Column-level documentation
```

---

## End of Day 1 Checklist

- [x] dbt-external-tables package installed
- [x] External sources defined in sources.yml
- [x] External tables generated in Glue/Spectrum
- [x] Staging models created (stg_sales__orders, stg_sales__customers)
- [x] dbt tests defined for staging models
- [x] All tests passing
- [x] dbt documentation generated

---

## 📝 Daily Standup Notes

**Completed Today**:
- Configured dbt-external-tables package
- Created external table definitions for orders and customers
- Generated external tables in AWS Glue
- Built staging models with data cleaning
- Implemented column-level tests

**Blockers**:
- None

**Tomorrow's Plan**:
- Create intermediate models for deduplication
- Build dimension and fact tables
- Add relationship tests
- Optimize materialization strategies

---

## 🎯 Success Metric

```bash
# All staging models run
dbt run --select staging
# Expected: 2 models pass

# All tests pass
dbt test --select staging
# Expected: 8+ tests pass

# Can query in Redshift
SELECT COUNT(*) FROM staging_schema.stg_sales__orders;
# Should return row count
```

---

## ⏭️ Next: Day 2

Tomorrow: Create intermediate and mart models

**See [day-2.md](./day-2.md)** 🚀
