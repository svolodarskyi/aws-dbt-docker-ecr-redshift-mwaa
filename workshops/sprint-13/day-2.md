# Sprint 13 - Day 2: Python Data Validation Framework

**Goal**: Custom validation framework for complex data quality checks

**Duration**: ~6 hours

**Outcome**: Python validation framework integrated with Airflow

---

## Validation Framework Components

### DataValidator Class
```python
class DataValidator:
    def __init__(self, connection):
        self.conn = connection

    def check_row_count_anomaly(self, table, threshold=0.2):
        """Detect anomalous row count changes"""
        # Compare with 7-day average
        # Alert if deviation > threshold

    def check_schema_drift(self, table, expected_schema):
        """Validate schema hasn't changed unexpectedly"""
        # Compare current vs expected columns/types

    def check_data_freshness(self, table, timestamp_column, max_age_hours=24):
        """Ensure data is recent"""
        # Check latest timestamp

    def check_distribution_anomaly(self, table, column):
        """Detect unusual value distributions"""
        # Statistical analysis of value frequency

    def check_cross_table_consistency(self, table1, table2, join_key):
        """Validate consistency across related tables"""
        # Reconciliation checks
```

### Integration with Airflow

```python
# In DAG: airflow/dags/data_quality_validation.py

from utils.data_validator import DataValidator

dag = DAG('data_quality_checks', schedule_interval='@daily')

def run_validation_suite():
    validator = DataValidator(get_redshift_connection())

    results = []

    # Row count anomaly detection
    results.append(validator.check_row_count_anomaly('analytics.customers_dim'))

    # Schema drift detection
    expected_schema = {...}
    results.append(validator.check_schema_drift('analytics.orders_fct', expected_schema))

    # Freshness check
    results.append(validator.check_data_freshness(
        'analytics.orders_fct',
        'order_date',
        max_age_hours=24
    ))

    # Store results in audit table
    store_validation_results(results)

    # Alert on failures
    failures = [r for r in results if not r['passed']]
    if failures:
        send_alert(failures)

PythonOperator(
    task_id='run_validations',
    python_callable=run_validation_suite,
    dag=dag
)
```

---

## Audit Schema

### audit.data_quality_checks Table
```sql
CREATE TABLE audit.data_quality_checks (
    check_id BIGINT IDENTITY(1,1),
    check_name VARCHAR(255),
    table_name VARCHAR(255),
    check_type VARCHAR(50),
    passed BOOLEAN,
    check_value DECIMAL(18,4),
    threshold_value DECIMAL(18,4),
    error_message VARCHAR(500),
    checked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (check_id)
);
```

### Validation Results Stored
✅ All checks logged with timestamp
✅ Pass/fail status tracked
✅ Historical trends available
✅ Alert triggers on failures

---

## Advanced Validations

### 1. Statistical Anomaly Detection
- Mean/median comparison
- Standard deviation analysis
- Outlier detection
- Trend analysis

### 2. Business Rule Validation
- Revenue calculation checks
- Date sequence validation
- Status transition logic
- Referential integrity beyond FK

### 3. Data Completeness
- Record count expectations
- Required field population
- Time series gaps
- Missing dimension values

---

## Validation Workflow

```
dbt run → dbt test → Python Validation → Store Results → Alert if Failed
```

**All automated, all monitored, failures trigger alerts**

---

## Success Criteria

```bash
# Validation framework operational
./scripts/validation/run-validations.sh

# Results in audit table
SELECT * FROM audit.data_quality_checks
WHERE checked_at > CURRENT_DATE
ORDER BY checked_at DESC;

# Alerts configured
# Failed validation sends SNS notification
```

---

**Status**: ✅ Day 2 Complete - Validation Framework Operational
**Next**: Day 3 - Quality Dashboard & Demo

**See [day-3.md](./day-3.md)** 🚀
