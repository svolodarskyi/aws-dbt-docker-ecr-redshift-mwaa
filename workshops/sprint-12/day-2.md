# Sprint 12 - Day 2: CloudWatch Alarms & SNS Alerts

**Goal**: Configure proactive alerting for critical issues

**Duration**: ~6 hours

**Outcome**: Comprehensive alarm coverage, SNS notifications configured

---

## Critical Alarms Created

### 1. DAG Failure Alarm
- **Metric**: DAG run state = failed
- **Threshold**: ≥ 1 failure
- **Period**: 5 minutes
- **Action**: SNS notification

### 2. ECS Task Failure Alarm
- **Metric**: ECS task stopped with error
- **Threshold**: ≥ 1 failure
- **Period**: 5 minutes
- **Action**: SNS notification + auto-retry

### 3. Redshift Disk Space Alarm
- **Metric**: Disk usage percentage
- **Threshold**: > 80%
- **Period**: 15 minutes
- **Action**: SNS warning → Escalate if > 90%

### 4. High Error Rate Alarm
- **Metric**: Error log count
- **Threshold**: > 10 errors in 5 minutes
- **Period**: 5 minutes
- **Action**: SNS notification

### 5. Pipeline SLA Breach
- **Metric**: Pipeline duration
- **Threshold**: > 60 minutes
- **Period**: Check after completion
- **Action**: SNS notification to stakeholders

---

## SNS Configuration

### Topic Structure
```
data-pipeline-alerts-dev    (Development alerts)
data-pipeline-alerts-prod   (Production alerts - PagerDuty integration)
```

### Subscribers
✅ Team email distribution list
✅ Slack webhook (optional)
✅ PagerDuty (production only)
✅ On-call rotation (production)

### Alert Levels
- **P1 (Critical)**: Production pipeline down, data loss risk
- **P2 (High)**: Pipeline failures, SLA breaches
- **P3 (Medium)**: Resource constraints, degraded performance
- **P4 (Low)**: Warnings, informational

---

## Testing Alerts

### Intentional Failure Tests
```bash
# Trigger DAG failure
# Upload invalid file to test validation alarm

# Trigger high error rate
# Generate multiple errors quickly

# Verify SNS delivery
# Check email/Slack for notifications
```

---

## Success Criteria

```bash
# Alarms exist
aws cloudwatch describe-alarms | grep data-platform

# SNS topics configured
aws sns list-topics | grep data-pipeline-alerts

# Test alarm triggered
# Manual test shows notification received
```

---

**Status**: ✅ Day 2 Complete
**Next**: Day 3 - Final Dashboard & Demo

**See [day-3.md](./day-3.md)** 🚀
