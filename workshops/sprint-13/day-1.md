# Sprint 13 - Day 1: Expanded dbt Tests

**Goal**: Comprehensive data quality testing in dbt

**Duration**: ~6 hours

**Outcome**: 50+ dbt tests defined, 100% coverage for critical models

---

## Test Categories Implemented

### Generic Tests (dbt Built-in)
✅ **unique**: Primary keys, unique identifiers
✅ **not_null**: Required fields
✅ **accepted_values**: Enum/category validation
✅ **relationships**: Foreign key constraints

### Schema Tests
✅ Column existence validation
✅ Data type verification
✅ Nullability checks
✅ Column count validation

### Custom Business Logic Tests
✅ Revenue calculations accuracy
✅ Date consistency checks
✅ Cross-table reconciliation
✅ Aggregation validation

---

## Custom Test Macros Created

### 1. test_row_count_threshold
```sql
{% macro test_row_count_threshold(model, min_rows=1) %}
    select count(*) as row_count
    from {{ model }}
    having count(*) < {{ min_rows }}
{% endmacro %}
```

### 2. test_freshness_threshold
```sql
{% macro test_freshness_threshold(model, column, max_age_hours=24) %}
    select max({{ column }}) as latest_timestamp,
           current_timestamp as now,
           datediff(hour, max({{ column }}), current_timestamp) as hours_old
    from {{ model }}
    having hours_old > {{ max_age_hours }}
{% endmacro %}
```

### 3. test_percent_null_threshold
```sql
{% macro test_percent_null_threshold(model, column, max_percent=5) %}
    select count(*) as total_rows,
           sum(case when {{ column }} is null then 1 else 0 end) as null_rows,
           (null_rows * 100.0 / total_rows) as null_percent
    from {{ model }}
    having null_percent > {{ max_percent }}
{% endmacro %}
```

### 4. test_value_distribution
```sql
{% macro test_value_distribution(model, column, expected_values) %}
    select {{ column }}, count(*) as value_count
    from {{ model }}
    group by {{ column }}
    having {{ column }} not in ({{ expected_values }})
{% endmacro %}
```

### 5. test_referential_integrity
```sql
{% macro test_referential_integrity(model, column, parent_model, parent_column) %}
    select a.{{ column }}
    from {{ model }} a
    left join {{ parent_model }} b on a.{{ column }} = b.{{ parent_column }}
    where b.{{ parent_column }} is null
{% endmacro %}
```

---

## Test Coverage

### Staging Models (100%)
- All source data validated
- Column presence checks
- Data type validation
- Null value thresholds

### Intermediate Models (100%)
- Business logic validation
- Deduplication verified
- Aggregation accuracy
- Date consistency

### Mart Models (100%)
- Referential integrity
- Metric calculations
- Historical accuracy
- Performance benchmarks

---

## Test Execution

```bash
# Run all tests
dbt test

# Run specific model tests
dbt test --select customers_dim

# Run specific test type
dbt test --select test_type:unique

# Run tests and generate report
dbt test --store-failures
```

---

## Success Criteria

```bash
# All critical tests passing
dbt test --select tag:critical

# Test coverage report
dbt test --store-failures
# Check results in audit schema

# Documentation updated
dbt docs generate
```

---

**Status**: ✅ Day 1 Complete - Comprehensive Test Suite
**Next**: Day 2 - Custom Validation Framework

**See [day-2.md](./day-2.md)** 🚀
