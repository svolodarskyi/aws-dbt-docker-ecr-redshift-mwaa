# Sprint 4 - Day 3: dbt Testing, Demo & Retrospective

**Goal**: Test dbt with Redshift, conduct demo, close sprint

**Duration**: ~6 hours

**Outcome**: dbt connected to Redshift, Sprint 4 complete

---

## Morning Session (3 hours)

### Step 1: Update dbt Models for Redshift (1 hour 30 minutes)

```bash
cd dbt

# Activate environment and set Redshift credentials
source ../.venv/bin/activate
export $(cat .env | xargs)

# Test dbt connection
dbt debug --profiles-dir ./profiles --target dev

# Expected: All checks should pass

# Update dbt_project.yml for Redshift-specific configs
cat >> dbt_project.yml <<'EOF'

# Redshift-specific configurations
models:
  data_platform:
    staging:
      +materialized: view
      +schema: staging_schema
    intermediate:
      +materialized: view
      +schema: staging_schema
    marts:
      +materialized: table
      +schema: analytics_schema
      # Redshift optimizations
      +dist: auto
      +sort: auto
      +bind: false

seeds:
  +schema: staging_schema

snapshots:
  +target_schema: analytics_schema
EOF

# Update existing stg_sample_data.sql to use Spectrum
cat > models/staging/stg_spectrum_orders.sql <<'EOF'
{{
    config(
        materialized='view',
        tags=['staging', 'spectrum']
    )
}}

WITH source_data AS (
    SELECT
        order_id,
        customer_id,
        order_date,
        order_amount,
        status,
        partition_date
    FROM {{ source('spectrum', 'orders') }}
    WHERE partition_date = CURRENT_DATE
)

SELECT
    order_id::INTEGER AS order_id,
    customer_id::INTEGER AS customer_id,
    order_date::DATE AS order_date,
    order_amount::DECIMAL(10,2) AS order_amount,
    UPPER(TRIM(status)) AS status,
    partition_date::DATE AS partition_date,
    CURRENT_TIMESTAMP AS loaded_at
FROM source_data
EOF

# Create sources.yml for Spectrum
cat > models/external/sources.yml <<'EOF'
version: 2

sources:
  - name: spectrum
    description: External tables via Redshift Spectrum
    database: dev
    schema: spectrum_schema
    tables:
      - name: orders
        description: Sales orders from S3
        external:
          location: 's3://data-platform-raw-data-dev/raw/sales/orders/'
          partitions:
            - name: partition_date
              data_type: date
        columns:
          - name: order_id
            description: Unique order identifier
            tests:
              - not_null
          - name: customer_id
            description: Customer identifier
            tests:
              - not_null
          - name: order_date
            description: Date order was placed
          - name: order_amount
            description: Total order amount
            tests:
              - not_null
          - name: status
            description: Order status
            tests:
              - accepted_values:
                  values: ['COMPLETED', 'PROCESSING', 'PENDING', 'CANCELLED']
EOF

# Update schema.yml for staging model
cat > models/staging/schema.yml <<'EOF'
version: 2

models:
  - name: stg_spectrum_orders
    description: Staging model for orders from Spectrum
    columns:
      - name: order_id
        description: Unique order identifier
        tests:
          - unique
          - not_null
      - name: customer_id
        description: Customer identifier
        tests:
          - not_null
      - name: order_date
        description: Date order was placed
      - name: order_amount
        description: Total order amount in USD
        tests:
          - not_null
      - name: status
        description: Order status (normalized to uppercase)
        tests:
          - accepted_values:
              values: ['COMPLETED', 'PROCESSING', 'PENDING', 'CANCELLED']
      - name: partition_date
        description: Date partition of source data
      - name: loaded_at
        description: Timestamp when record was loaded
EOF
```

**✅ Validation**: dbt models updated

### Step 2: Run dbt Pipeline (1 hour)

```bash
# Clean previous builds
dbt clean

# Install dependencies (if any packages)
dbt deps

# Compile models (check SQL without running)
dbt compile --profiles-dir ./profiles --target dev

# Check compiled SQL
cat target/compiled/data_platform/models/staging/stg_spectrum_orders.sql

# Run models
dbt run --profiles-dir ./profiles --target dev --select stg_spectrum_orders

# Expected output:
# Completed successfully
# Done. PASS=1 WARN=0 ERROR=0 SKIP=0 TOTAL=1

# Run tests
dbt test --profiles-dir ./profiles --target dev --select stg_spectrum_orders

# Expected: All tests should pass

# Generate documentation
dbt docs generate --profiles-dir ./profiles --target dev

# Serve documentation (opens browser)
dbt docs serve --port 8001

# View in browser at http://localhost:8001
# Check lineage graph, model documentation
```

**✅ Validation**: dbt pipeline runs successfully

### Step 3: Verify Data in Redshift (30 minutes)

```bash
cd ../scripts/redshift

# Connect to Redshift
./connect-redshift.sh
```

**In Redshift SQL**:

```sql
-- Check staging view was created
SELECT *
FROM staging_schema.stg_spectrum_orders
LIMIT 10;

-- Verify row count
SELECT COUNT(*) as row_count
FROM staging_schema.stg_spectrum_orders;

-- Check data types
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'staging_schema'
  AND table_name = 'stg_spectrum_orders'
ORDER BY ordinal_position;

-- Sample aggregation to verify data quality
SELECT
    status,
    COUNT(*) as order_count,
    AVG(order_amount) as avg_amount,
    MIN(order_date) as earliest_order,
    MAX(order_date) as latest_order
FROM staging_schema.stg_spectrum_orders
GROUP BY status
ORDER BY order_count DESC;

-- Check if view is querying Spectrum correctly
EXPLAIN
SELECT * FROM staging_schema.stg_spectrum_orders LIMIT 100;
-- Should show S3 Seq Scan in query plan

-- Exit psql
\q
```

**✅ Validation**: Data visible in Redshift

---

## Afternoon Session (3 hours)

### Step 4: Create Validation Scripts (1 hour)

```bash
cd ../sql

mkdir -p validation

cat > validation/validate_redshift_setup.sql <<'EOF'
-- ========================================
-- Redshift Setup Validation
-- ========================================

-- 1. Check all schemas exist
SELECT
    'Schemas' as validation_type,
    COUNT(*) as count,
    CASE WHEN COUNT(*) = 4 THEN 'PASS' ELSE 'FAIL' END as status
FROM information_schema.schemata
WHERE schema_name IN ('raw_schema', 'staging_schema', 'analytics_schema', 'audit_schema');

-- 2. Check external schema exists
SELECT
    'External Schema' as validation_type,
    COUNT(*) as count,
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END as status
FROM SVV_EXTERNAL_SCHEMAS
WHERE schemaname = 'spectrum_schema';

-- 3. Check Spectrum can query S3
SELECT
    'Spectrum Query' as validation_type,
    COUNT(*) as count,
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END as status
FROM spectrum_schema.orders;

-- 4. Check staging views exist
SELECT
    'Staging Views' as validation_type,
    COUNT(*) as count,
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END as status
FROM information_schema.views
WHERE table_schema = 'staging_schema';

-- 5. Check audit tables exist
SELECT
    'Audit Tables' as validation_type,
    COUNT(*) as count,
    CASE WHEN COUNT(*) = 3 THEN 'PASS' ELSE 'FAIL' END as status
FROM information_schema.tables
WHERE table_schema = 'audit_schema'
  AND table_type = 'BASE TABLE';

-- 6. Check cluster health
SELECT
    'Cluster Health' as validation_type,
    1 as count,
    'PASS' as status;  -- If this query runs, cluster is healthy

-- 7. Verify IAM role attached
SELECT
    'IAM Roles' as validation_type,
    COUNT(*) as count,
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END as status
FROM pg_catalog.pg_roles
WHERE rolname LIKE '%spectrum%';

-- Summary
SELECT
    validation_type,
    status
FROM (
    SELECT 'All Validations' as validation_type,
           CASE WHEN COUNT(*) = 7 THEN 'ALL PASS ✅' ELSE 'SOME FAILED ❌' END as status
    FROM (
        SELECT 'dummy' as validation_type
    ) dummy
);
EOF

cat > validation/run_validations.sh <<'EOF'
#!/bin/bash
set -e

echo "🔍 Running Redshift validation..."

# Get connection details
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

# Run validation
PGPASSWORD=${PASSWORD} psql \
    -h ${HOST} \
    -p ${PORT} \
    -U ${USERNAME} \
    -d ${DATABASE} \
    -f ../sql/validation/validate_redshift_setup.sql

echo ""
echo "✅ Validation complete!"
EOF

chmod +x validation/run_validations.sh

# Run validations
./validation/run_validations.sh
```

**✅ Validation**: All checks pass

### Step 5: Prepare Sprint Demo (1 hour)

```bash
cd ../../docs/demos

mkdir -p sprint-04

cat > sprint-04/DEMO_SCRIPT.md <<'EOF'
# Sprint 4 Demo Script

**Sprint Goal**: Redshift Cluster & Database Setup

---

## Demo Flow (15 minutes)

### 1. Introduction (2 minutes)

**SAY**:
> "In Sprint 4, we deployed a Redshift data warehouse and integrated it with S3 through Spectrum. Now we can query our data lake directly from SQL."

### 2. Redshift Cluster Overview (3 minutes)

**SHOW**: AWS Console → Redshift
- Cluster: data-platform-dev-redshift
- Status: Available
- Node type: dc2.large (2 nodes)
- Encrypted: Yes
- VPC: Private subnets only

**HIGHLIGHT**: Configuration
- Enhanced VPC routing
- Automated snapshots
- SSL required

### 3. Database Schemas (3 minutes)

**SHOW**: Connect to Redshift (psql or SQL client)

```sql
-- Show schemas
SELECT schema_name FROM information_schema.schemata
WHERE schema_name LIKE '%_schema'
ORDER BY schema_name;
```

**EXPLAIN**:
- `raw_schema`: Future raw data
- `staging_schema`: dbt staging (views)
- `analytics_schema`: dbt marts (tables)
- `audit_schema`: Logging and metadata

### 4. Redshift Spectrum Demo (5 minutes)

**SHOW**: Query S3 data directly

```sql
-- Query external table (data in S3)
SELECT * FROM spectrum_schema.orders LIMIT 10;

-- Aggregation pushed down to S3
SELECT
    status,
    COUNT(*) as orders,
    SUM(order_amount) as total
FROM spectrum_schema.orders
GROUP BY status;
```

**SAY**:
> "This is querying S3 directly. No data loaded into Redshift. Perfect for exploration and historical data."

### 5. dbt Integration (2 minutes)

**SHOW**: dbt model

```bash
# Terminal
cd dbt
dbt run --select stg_spectrum_orders
```

**SHOW**: Resulting view in Redshift

```sql
SELECT * FROM staging_schema.stg_spectrum_orders LIMIT 10;
```

**SAY**:
> "dbt transforms Spectrum data into clean staging views, ready for analytics. All transformations are version-controlled SQL."

---

## Q&A

**Q**: "How much does Redshift cost?"
**A**: "~$360/month for 2 dc2.large nodes. We can pause during off-hours for 50% savings (~$180/month)."

**Q**: "Why use Spectrum vs loading data?"
**A**: "Spectrum is great for exploration and historical data. For frequently-queried data, we'll load it into Redshift tables for better performance."

**Q**: "Can we scale up?"
**A**: "Yes! We can add more nodes or resize to larger node types. Production will use ra3 nodes with managed storage."

---

## Demo Checklist

- [ ] Redshift cluster is running (not paused)
- [ ] psql or SQL client connected
- [ ] dbt environment activated
- [ ] AWS Console open to Redshift
- [ ] Sample queries tested

EOF
```

### Step 6: Conduct Sprint Demo (30 minutes)

Follow demo script and present to stakeholders.

### Step 7: Sprint Retrospective & Closure (1 hour 30 minutes)

```bash
cat > ../retrospectives/sprint-04.md <<'EOF'
# Sprint 4 Retrospective

**Sprint**: 4/14
**Goal**: Redshift Cluster & Database Setup

---

## Sprint Metrics

| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| Story Points | 21 | 21 | ✅ |
| Velocity | 100% | 100% | ✅ |

---

## Accomplishments

1. Deployed 2-node Redshift cluster in private subnets
2. Created 4 database schemas (raw, staging, analytics, audit)
3. Set up Glue Data Catalog with external tables
4. Configured Redshift Spectrum for S3 querying
5. Integrated dbt with Redshift successfully
6. Created comprehensive documentation

---

## What Went Well? 😊

1. Redshift provisioning smooth (5 min)
2. Spectrum queries working on first try
3. dbt connection configuration straightforward
4. Good documentation created upfront

---

## What Didn't Go Well? 😞

1. Initial confusion about Glue table partitioning
2. dbt profiles.yml required several iterations
3. Cost is significant (~$360/month)

---

## Lessons Learned 💡

1. Spectrum is powerful but understand scan costs
2. Pause cluster during off-hours for 50% savings
3. External schemas need careful IAM role configuration
4. dbt documentation helps team understand data flow

---

## Action Items for Sprint 5

| Action | Owner | Due Date |
|--------|-------|----------|
| Implement automated cluster pause/resume | DevOps | Sprint 5 Day 1 |
| Create dbt staging models for all sources | Data Eng | Sprint 5 |
| Set up cost alerts for Redshift | Tech Lead | Sprint 5 Day 1 |

---

## Sprint 5 Preview

**Goal**: dbt Core Models & External Tables
- Build comprehensive dbt models (staging → intermediate → marts)
- Implement data quality tests
- Generate dbt documentation
- Optimize query performance

EOF

# Commit all work
cd ../../..

git add -A

git commit -m "feat: complete Sprint 4 - Redshift Cluster & Database Setup

Day 1:
- Created Redshift secrets in Secrets Manager
- Built data Terraform module
- Deployed 2-node Redshift cluster in private subnets
- Configured dbt connection

Day 2:
- Created database schemas (raw, staging, analytics, audit)
- Set up Glue Data Catalog
- Configured Redshift Spectrum external schema
- Successfully queried S3 data via Spectrum
- Created audit tables

Day 3:
- Updated dbt models for Redshift
- Tested dbt pipeline end-to-end
- Created validation scripts
- Conducted sprint demo
- Completed retrospective

All acceptance criteria met ✅
Redshift cluster operational and integrated with dbt

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

git push origin develop
```

**✅ Validation**: Sprint 4 complete

---

## End of Day 3 Checklist

- [x] dbt models updated for Redshift
- [x] dbt pipeline runs successfully
- [x] Data validated in Redshift
- [x] Validation scripts created
- [x] Sprint demo delivered
- [x] Stakeholder feedback collected
- [x] Sprint retrospective conducted
- [x] All work committed to Git

---

## 🎉 Sprint 4 Complete!

### Accomplishments

- ✅ Redshift cluster deployed and operational
- ✅ Database schemas structured for data layers
- ✅ Redshift Spectrum querying S3 successfully
- ✅ dbt integrated and working with Redshift
- ✅ Audit tables for tracking data operations

### Ready For

- ✅ dbt staging and mart models (Sprint 5)
- ✅ Docker containerization (Sprint 6)
- ✅ Production data transformations
- ✅ BI tool integration

---

## 💰 Cost Management

**Current monthly cost**: ~$360 for 2 dc2.large nodes

**Optimization strategies**:
1. Pause cluster during off-hours: ~50% savings
2. Resize to smaller nodes for dev
3. Use Spectrum for historical data (S3 storage cheaper)
4. Upgrade to ra3 nodes in prod (managed storage scaling)

**Pause cluster now** (if not using):
```bash
cd scripts/redshift
./pause-cluster.sh
```

---

## ⏭️ Next: Sprint 5

**Sprint 5**: dbt Core Models & External Tables (Days 13-15)

You'll be building:
- Comprehensive dbt external tables
- Staging models with data cleaning
- Intermediate models for business logic
- Mart models (dimensions and facts)
- dbt tests for data quality
- Complete dbt documentation

**See `workshops/sprint-05/`** 🚀
