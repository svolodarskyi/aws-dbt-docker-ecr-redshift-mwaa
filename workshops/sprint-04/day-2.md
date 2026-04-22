# Sprint 4 - Day 2: Database Schemas & Spectrum Setup

**Goal**: Create database schemas and configure Redshift Spectrum

**Duration**: ~6 hours

**Outcome**: Schemas created, Spectrum querying S3 data

---

## Morning Session (3 hours)

### Step 1: Connect to Redshift and Create Schemas (1 hour)

```bash
cd scripts/redshift

# Ensure cluster is running
aws redshift describe-clusters \
    --cluster-identifier data-platform-dev-redshift \
    --query 'Clusters[0].ClusterStatus' --output text

# If paused, resume it
if [ $? != "available" ]; then
    ./resume-cluster.sh
    sleep 180  # Wait 3 minutes for cluster to resume
fi

# Connect to Redshift
./connect-redshift.sh

# Or use psql directly (once connected)
```

**In Redshift SQL**:

```sql
-- Create schemas for data layers
CREATE SCHEMA IF NOT EXISTS raw_schema
    AUTHORIZATION admin;

CREATE SCHEMA IF NOT EXISTS staging_schema
    AUTHORIZATION admin;

CREATE SCHEMA IF NOT EXISTS analytics_schema
    AUTHORIZATION admin;

CREATE SCHEMA IF NOT EXISTS audit_schema
    AUTHORIZATION admin;

-- Grant permissions
GRANT ALL ON SCHEMA raw_schema TO admin;
GRANT ALL ON SCHEMA staging_schema TO admin;
GRANT ALL ON SCHEMA analytics_schema TO admin;
GRANT ALL ON SCHEMA audit_schema TO admin;

-- Verify schemas created
SELECT schema_name, schema_owner
FROM information_schema.schemata
WHERE schema_name IN ('raw_schema', 'staging_schema', 'analytics_schema', 'audit_schema')
ORDER BY schema_name;

-- Expected output:
--  schema_name      | schema_owner
-- ------------------+-------------
--  analytics_schema | admin
--  audit_schema     | admin
--  raw_schema       | admin
--  staging_schema   | admin

-- Create audit table for tracking data loads
CREATE TABLE IF NOT EXISTS audit_schema.data_load_log (
    load_id         BIGINT IDENTITY(1,1) PRIMARY KEY,
    load_timestamp  TIMESTAMP DEFAULT GETDATE(),
    source_system   VARCHAR(100),
    table_name      VARCHAR(200),
    rows_loaded     BIGINT,
    status          VARCHAR(20),
    error_message   VARCHAR(5000)
);

-- Verify table created
SELECT * FROM audit_schema.data_load_log LIMIT 5;
```

**Exit psql**: `\q`

**✅ Validation**: Schemas created successfully

### Step 2: Create Glue Data Catalog Database (1 hour)

```bash
# Create Glue database for external tables
aws glue create-database \
    --database-input '{
        "Name": "data_platform_dev",
        "Description": "Data platform external tables",
        "LocationUri": "s3://data-platform-raw-data-dev/raw/"
    }'

# Verify Glue database created
aws glue get-database --name data_platform_dev

# Create Glue table for orders data
aws glue create-table \
    --database-name data_platform_dev \
    --table-input '{
        "Name": "orders",
        "StorageDescriptor": {
            "Columns": [
                {"Name": "order_id", "Type": "int"},
                {"Name": "customer_id", "Type": "int"},
                {"Name": "order_date", "Type": "date"},
                {"Name": "order_amount", "Type": "decimal(10,2)"},
                {"Name": "status", "Type": "string"}
            ],
            "Location": "s3://data-platform-raw-data-dev/raw/sales/orders/",
            "InputFormat": "org.apache.hadoop.mapred.TextInputFormat",
            "OutputFormat": "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat",
            "SerdeInfo": {
                "SerializationLibrary": "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe",
                "Parameters": {
                    "field.delim": ",",
                    "skip.header.line.count": "1"
                }
            }
        },
        "PartitionKeys": [
            {"Name": "partition_date", "Type": "string"}
        ],
        "TableType": "EXTERNAL_TABLE"
    }'

# Create partition for existing data
PARTITION_DATE=$(date +%Y-%m-%d)

aws glue create-partition \
    --database-name data_platform_dev \
    --table-name orders \
    --partition-input "{
        \"Values\": [\"${PARTITION_DATE}\"],
        \"StorageDescriptor\": {
            \"Columns\": [
                {\"Name\": \"order_id\", \"Type\": \"int\"},
                {\"Name\": \"customer_id\", \"Type\": \"int\"},
                {\"Name\": \"order_date\", \"Type\": \"date\"},
                {\"Name\": \"order_amount\", \"Type\": \"decimal(10,2)\"},
                {\"Name\": \"status\", \"Type\": \"string\"}
            ],
            \"Location\": \"s3://data-platform-raw-data-dev/raw/sales/orders/${PARTITION_DATE}/\",
            \"InputFormat\": \"org.apache.hadoop.mapred.TextInputFormat\",
            \"OutputFormat\": \"org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat\",
            \"SerdeInfo\": {
                \"SerializationLibrary\": \"org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe\",
                \"Parameters\": {
                    \"field.delim\": \",\",
                    \"skip.header.line.count\": \"1\"
                }
            }
        }
    }"

# Verify table and partition
aws glue get-table --database-name data_platform_dev --name orders
aws glue get-partitions --database-name data_platform_dev --table-name orders
```

**✅ Validation**: Glue table and partition created

### Step 3: Create External Schema in Redshift (1 hour)

```bash
# Connect to Redshift
./connect-redshift.sh
```

**In Redshift SQL**:

```sql
-- Create external schema pointing to Glue catalog
CREATE EXTERNAL SCHEMA spectrum_schema
FROM DATA CATALOG
DATABASE 'data_platform_dev'
IAM_ROLE 'arn:aws:iam::ACCOUNT_ID:role/data-platform-dev-redshift-spectrum-role'
CREATE EXTERNAL DATABASE IF NOT EXISTS;

-- Note: Replace ACCOUNT_ID with your AWS account ID
-- Get it from: aws sts get-caller-identity --query Account --output text

-- Verify external schema created
SELECT schema_name, schema_owner, schema_type
FROM SVV_EXTERNAL_SCHEMAS;

-- Expected output should show spectrum_schema

-- Query external table via Spectrum
SELECT *
FROM spectrum_schema.orders
LIMIT 10;

-- Count rows in external table
SELECT COUNT(*)
FROM spectrum_schema.orders;

-- Analyze external table structure
SELECT *
FROM SVV_EXTERNAL_COLUMNS
WHERE schemaname = 'spectrum_schema'
  AND tablename = 'orders';
```

**✅ Validation**: Can query S3 data via Spectrum

---

## Afternoon Session (3 hours)

### Step 4: Create SQL Scripts for Schema Setup (1 hour)

```bash
cd ../sql

mkdir -p ddl

# Create schema setup script
cat > ddl/01_create_schemas.sql <<'EOF'
-- ========================================
-- Create Database Schemas
-- ========================================

-- Raw schema: External tables (Spectrum)
CREATE SCHEMA IF NOT EXISTS raw_schema;

-- Staging schema: First transformation layer (dbt staging models)
CREATE SCHEMA IF NOT EXISTS staging_schema;

-- Analytics schema: Final data marts (dbt marts)
CREATE SCHEMA IF NOT EXISTS analytics_schema;

-- Audit schema: Metadata and logging
CREATE SCHEMA IF NOT EXISTS audit_schema;

-- Grant permissions to admin
GRANT ALL ON SCHEMA raw_schema TO admin;
GRANT ALL ON SCHEMA staging_schema TO admin;
GRANT ALL ON SCHEMA analytics_schema TO admin;
GRANT ALL ON SCHEMA audit_schema TO admin;

-- Verify
SELECT schema_name, schema_owner
FROM information_schema.schemata
WHERE schema_name IN ('raw_schema', 'staging_schema', 'analytics_schema', 'audit_schema')
ORDER BY schema_name;
EOF

cat > ddl/02_create_external_schema.sql <<'EOF'
-- ========================================
-- Create External Schema (Spectrum)
-- ========================================

-- Note: Replace ACCOUNT_ID with your AWS account ID

CREATE EXTERNAL SCHEMA IF NOT EXISTS spectrum_schema
FROM DATA CATALOG
DATABASE 'data_platform_dev'
IAM_ROLE 'arn:aws:iam::ACCOUNT_ID:role/data-platform-dev-redshift-spectrum-role'
CREATE EXTERNAL DATABASE IF NOT EXISTS;

-- Verify
SELECT schema_name, schema_owner, schema_type
FROM SVV_EXTERNAL_SCHEMAS;
EOF

cat > ddl/03_create_audit_tables.sql <<'EOF'
-- ========================================
-- Create Audit Tables
-- ========================================

-- Data load logging
CREATE TABLE IF NOT EXISTS audit_schema.data_load_log (
    load_id         BIGINT IDENTITY(1,1) PRIMARY KEY,
    load_timestamp  TIMESTAMP DEFAULT GETDATE(),
    source_system   VARCHAR(100),
    table_name      VARCHAR(200),
    rows_loaded     BIGINT,
    file_path       VARCHAR(500),
    status          VARCHAR(20),  -- SUCCESS, FAILED, RUNNING
    error_message   VARCHAR(5000),
    load_duration_seconds INTEGER
)
DISTKEY(load_id)
SORTKEY(load_timestamp);

-- dbt run logging
CREATE TABLE IF NOT EXISTS audit_schema.dbt_run_log (
    run_id          VARCHAR(100) PRIMARY KEY,
    run_timestamp   TIMESTAMP DEFAULT GETDATE(),
    command         VARCHAR(50),   -- run, test, docs generate
    target          VARCHAR(20),   -- dev, prod
    status          VARCHAR(20),
    models_run      INTEGER,
    tests_failed    INTEGER,
    execution_time_seconds INTEGER
)
DISTKEY(run_id)
SORTKEY(run_timestamp);

-- Data quality issues
CREATE TABLE IF NOT EXISTS audit_schema.data_quality_issues (
    issue_id        BIGINT IDENTITY(1,1) PRIMARY KEY,
    detected_at     TIMESTAMP DEFAULT GETDATE(),
    table_name      VARCHAR(200),
    column_name     VARCHAR(200),
    issue_type      VARCHAR(100),  -- null_value, duplicate, out_of_range
    issue_count     BIGINT,
    severity        VARCHAR(20),   -- CRITICAL, HIGH, MEDIUM, LOW
    resolved        BOOLEAN DEFAULT FALSE
)
DISTKEY(issue_id)
SORTKEY(detected_at);

-- Verify
SELECT tablename, "column", type
FROM pg_table_def
WHERE schemaname = 'audit_schema'
ORDER BY tablename, "column";
EOF

# Create helper script to run all DDL
cat > ddl/run_all_ddl.sh <<'EOF'
#!/bin/bash
set -e

echo "🗄️  Running DDL scripts..."

# Get Redshift connection info
cd ../../terraform/environments/dev
ENDPOINT=$(terraform output -json redshift | jq -r '.cluster_endpoint')
HOST=$(echo $ENDPOINT | cut -d':' -f1)
PORT=$(echo $ENDPOINT | cut -d':' -f2)
DATABASE=$(terraform output -json redshift | jq -r '.database_name')

# Get credentials
CREDS=$(aws secretsmanager get-secret-value \
    --secret-id data-platform/dev/redshift/master \
    --query SecretString --output text)
USERNAME=$(echo $CREDS | jq -r '.username')
PASSWORD=$(echo $CREDS | jq -r '.password')

# Run each DDL script
for script in ../sql/ddl/*.sql; do
    echo "Running: $(basename $script)"
    PGPASSWORD=${PASSWORD} psql \
        -h ${HOST} \
        -p ${PORT} \
        -U ${USERNAME} \
        -d ${DATABASE} \
        -f ${script}
    echo "✅ Completed: $(basename $script)"
    echo ""
done

echo "✅ All DDL scripts completed!"
EOF

chmod +x ddl/run_all_ddl.sh
```

**✅ Validation**: DDL scripts created

### Step 5: Test Spectrum Performance (1 hour)

**In Redshift SQL**:

```sql
-- Query 1: Simple SELECT (should scan S3)
SELECT *
FROM spectrum_schema.orders
WHERE partition_date = '2024-01-15'
LIMIT 100;

-- Query 2: Aggregation (pushdown to S3)
SELECT
    status,
    COUNT(*) as order_count,
    SUM(order_amount) as total_amount,
    AVG(order_amount) as avg_amount
FROM spectrum_schema.orders
WHERE partition_date = '2024-01-15'
GROUP BY status
ORDER BY total_amount DESC;

-- Query 3: Check query performance
SELECT
    query,
    TRIM(querytxt) as query_text,
    starttime,
    endtime,
    DATEDIFF(seconds, starttime, endtime) as duration_seconds
FROM STL_QUERY
WHERE querytxt LIKE '%spectrum_schema.orders%'
  AND userid > 1
ORDER BY starttime DESC
LIMIT 10;

-- Query 4: Check Spectrum bytes scanned
SELECT
    query,
    segment,
    node,
    s3_scanned_rows,
    s3_scanned_bytes / (1024*1024) as s3_scanned_mb
FROM SVL_S3QUERY
ORDER BY query DESC
LIMIT 10;

-- Create a regular Redshift table from Spectrum query (for comparison)
CREATE TABLE staging_schema.orders_stage AS
SELECT
    order_id,
    customer_id,
    order_date,
    order_amount,
    status
FROM spectrum_schema.orders
WHERE partition_date = '2024-01-15';

-- Add dist/sort keys for optimal performance
ALTER TABLE staging_schema.orders_stage
    ADD PRIMARY KEY (order_id);

ANALYZE staging_schema.orders_stage;

-- Compare query performance: Spectrum vs Redshift table
-- Spectrum query
SELECT COUNT(*) FROM spectrum_schema.orders WHERE order_amount > 1000;

-- Redshift table query (should be faster)
SELECT COUNT(*) FROM staging_schema.orders_stage WHERE order_amount > 1000;
```

**✅ Validation**: Queries return data successfully

### Step 6: Document Database Architecture (1 hour)

```bash
cd ../../docs

cat > REDSHIFT_ARCHITECTURE.md <<'EOF'
# Redshift Database Architecture

## Cluster Configuration

**Cluster**: data-platform-dev-redshift
- **Node Type**: dc2.large
- **Nodes**: 2
- **Total Storage**: 320 GB (160 GB per node)
- **Total vCPU**: 4 (2 per node)
- **Total RAM**: 30.5 GB (15.25 GB per node)

## Schema Layers

### 1. External Schema (`spectrum_schema`)

**Purpose**: Query S3 data without loading

**Tables**:
- Defined in AWS Glue Data Catalog
- Data stored in S3 (`s3://data-platform-raw-data-dev/raw/`)
- Partitioned by date

**Access Pattern**:
```sql
SELECT * FROM spectrum_schema.orders WHERE partition_date = '2024-01-15';
```

**Use Cases**:
- Ad-hoc queries on raw data
- Data exploration
- Infrequent access to historical data

### 2. Raw Schema (`raw_schema`)

**Purpose**: Placeholder for raw data views (currently unused)

**Future Use**:
- Materialized views of Spectrum queries
- Temporary staging of raw data

### 3. Staging Schema (`staging_schema`)

**Purpose**: First transformation layer (dbt staging models)

**Characteristics**:
- Lightweight transformations (type casting, renaming)
- Mostly views (no data duplication)
- Column-level tests (not_null, unique)

**Naming Convention**: `stg_{source}__{entity}`
- Example: `stg_sales__orders`

### 4. Analytics Schema (`analytics_schema`)

**Purpose**: Final data marts (dbt marts)

**Characteristics**:
- Business logic applied
- Materialized as tables for performance
- Dist/Sort keys optimized
- Comprehensive testing

**Naming Convention**:
- Dimensions: `{entity}_dim` (e.g., `customers_dim`)
- Facts: `{entity}_fct` (e.g., `orders_fct`)

### 5. Audit Schema (`audit_schema`)

**Purpose**: Metadata and operational logging

**Tables**:
- `data_load_log`: Track data ingestion
- `dbt_run_log`: Track dbt executions
- `data_quality_issues`: Track test failures

## Data Flow

```
S3 (raw files)
    ↓ (Glue Catalog)
spectrum_schema (external tables)
    ↓ (dbt sources)
staging_schema (views)
    ↓ (dbt transformations)
analytics_schema (tables)
    ↓
BI Tools / Analytics
```

## Performance Optimization

### Distribution Keys (DISTKEY)

**Strategy**: Distribute large tables by join keys

```sql
CREATE TABLE orders_fct (
    order_id INT PRIMARY KEY,
    customer_id INT,
    ...
)
DISTKEY(customer_id);  -- Distribute by frequent join key
```

### Sort Keys (SORTKEY)

**Strategy**: Sort by filter columns (especially dates)

```sql
CREATE TABLE orders_fct (
    ...
    order_date DATE,
    ...
)
SORTKEY(order_date);  -- Queries often filter by date
```

### Compression

**Auto-optimization**: Redshift automatically chooses compression

```sql
-- Check compression encodings
SELECT
    "column",
    type,
    encoding
FROM pg_table_def
WHERE tablename = 'orders_fct';
```

## Security

### Network

- ✅ Cluster in private subnets
- ✅ No public access
- ✅ Enhanced VPC routing enabled
- ✅ SSL/TLS required

### Encryption

- ✅ At rest: AES-256
- ✅ In transit: TLS 1.2+
- ✅ Automated snapshots encrypted

### Access Control

- ✅ Master credentials in Secrets Manager
- ✅ IAM role for Spectrum (least privilege)
- ✅ Schema-level permissions

## Monitoring

### Key Metrics

1. **Cluster Performance**
   - CPU utilization
   - Disk space usage
   - Query throughput

2. **Query Performance**
   - Query execution time
   - Queue wait time
   - Spectrum bytes scanned

3. **Data Loading**
   - Rows loaded per hour
   - Failed loads
   - Data freshness

### Queries

```sql
-- Top 10 longest queries today
SELECT
    query,
    TRIM(querytxt) as sql,
    starttime,
    DATEDIFF(seconds, starttime, endtime) as duration
FROM STL_QUERY
WHERE starttime >= CURRENT_DATE
  AND userid > 1
ORDER BY duration DESC
LIMIT 10;

-- Disk space usage by table
SELECT
    name as table_name,
    SUM(rows) as row_count,
    SUM(size) * 1 / 1024.0 as size_gb
FROM STV_TBL_PERM
GROUP BY name
ORDER BY size_gb DESC
LIMIT 20;

-- Current running queries
SELECT
    pid,
    user_name,
    starttime,
    DATEDIFF(seconds, starttime, GETDATE()) as running_seconds,
    TRIM(query) as sql
FROM STV_RECENTS
WHERE status = 'Running'
ORDER BY starttime;
```

## Cost Optimization

### Pause/Resume

**Automated schedule** (recommended):
- Weeknights: 8 PM - 8 AM (12 hours)
- Weekends: Full pause
- **Savings**: ~50% (~$180/month)

**Scripts**:
```bash
scripts/redshift/pause-cluster.sh
scripts/redshift/resume-cluster.sh
```

### Spectrum vs Tables

| Aspect | Spectrum | Redshift Tables |
|--------|----------|-----------------|
| Cost | S3 storage + scan charges | Cluster compute |
| Performance | Slower (S3 I/O) | Faster (local disk) |
| Best For | Infrequent access, large historical data | Frequent queries, recent data |

**Recommendation**: Use Spectrum for exploration, Redshift tables for production queries

## Backup & Recovery

### Automated Snapshots

- Retention: 7 days
- Frequency: Every 8 hours
- Stored in S3 (encrypted)

### Manual Snapshots

```bash
# Create manual snapshot
aws redshift create-cluster-snapshot \
    --cluster-identifier data-platform-dev-redshift \
    --snapshot-identifier manual-snapshot-$(date +%Y%m%d)
```

### Restore

```bash
# Restore from snapshot
aws redshift restore-from-cluster-snapshot \
    --cluster-identifier data-platform-dev-redshift-restored \
    --snapshot-identifier snapshot-id
```

## Best Practices

1. ✅ **Use Spectrum for exploration**, load to tables for production
2. ✅ **Partition external tables** by date in S3
3. ✅ **Vacuum and analyze** tables regularly
4. ✅ **Monitor WLM queues** for query performance
5. ✅ **Use dbt for all transformations** (version controlled)
6. ✅ **Pause cluster during off-hours** to save costs
7. ✅ **Set up automated snapshots** before prod
8. ✅ **Test restore procedures** quarterly

EOF
```

**✅ Validation**: Architecture documented

---

## End of Day 2 Checklist

- [x] Database schemas created (raw, staging, analytics, audit)
- [x] Glue Data Catalog database created
- [x] Glue table and partition for orders data
- [x] External schema configured in Redshift
- [x] Successfully queried S3 data via Spectrum
- [x] DDL scripts created and organized
- [x] Audit tables created
- [x] Performance testing completed
- [x] Database architecture documented

---

## 📝 Daily Standup Notes

**Completed Today**:
- Created 4 database schemas in Redshift
- Set up Glue Data Catalog with external tables
- Configured Redshift Spectrum
- Successfully queried S3 data from Redshift
- Created comprehensive DDL scripts

**Blockers**:
- None

**Tomorrow's Plan**:
- Update dbt project with Redshift target
- Test dbt models against Redshift
- Create validation queries
- Prepare sprint demo
- Conduct retrospective

---

## 🎯 Success Metric

**You're successful if**:

```sql
-- Can query Spectrum
SELECT COUNT(*) FROM spectrum_schema.orders;
-- Should return row count

-- Schemas exist
SELECT schema_name FROM information_schema.schemata
WHERE schema_name LIKE '%_schema';
-- Should show 4 schemas

-- Audit tables exist
SELECT tablename FROM pg_tables
WHERE schemaname = 'audit_schema';
-- Should show 3 tables
```

---

## ⏭️ Next: Day 3

Tomorrow you'll:
- Update dbt models for Redshift
- Test full dbt pipeline
- Create validation and testing queries
- Conduct sprint demo
- Sprint retrospective

**See [day-3.md](./day-3.md)** 🚀
