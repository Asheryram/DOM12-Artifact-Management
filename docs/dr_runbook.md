# FinCorp DR Runbook

## RTO / RPO Targets

| Metric | Target |
|---|---|
| RTO (Recovery Time Objective) | <= 30 minutes |
| RPO (Recovery Point Objective) | <= 24 hours (daily backup) |

## Step 1 - Detection

Monitor these CloudWatch alarms for primary region failure:
- RDS/DatabaseConnections drops to 0
- ECS service health check failures > 3 consecutive
- ALB HealthyHostCount = 0

## Step 2 - Decision

Declare DR if primary region is unreachable for > 5 minutes and cannot self-recover.

## Step 3 - Execution

```bash
# Simulate (lab only)
PROJECT_NAME=fincorp ./scripts/simulate_region_failure.sh

# Restore in us-west-2
PROJECT_NAME=fincorp \
BACKUP_ROLE_ARN=<arn from terraform output> \
DR_RDS_SG_ID=<dr sg id from rds_dr module output> \
DB_NAME=fincorpdb \
./scripts/restore_from_backup.sh
```

## Step 4 - Validation

```bash
DR_DB_ENDPOINT=<restored endpoint> \
DB_USERNAME=<username> \
DB_PASS=<password> \
./scripts/verify_dr.sh
```

Expected output:
```
Connection OK
transaction_count: <N>
category_count: 13
```

## Step 5 - Post-Recovery

1. Update ECS service environment variable DB_HOST to the restored endpoint
2. Force new ECS deployment: `aws ecs update-service --force-new-deployment`
3. Verify ALB health checks pass
4. Update DNS if using Route 53
5. Notify stakeholders

## Timeline

| Step | Expected Duration |
|---|---|
| Detection and decision | 0-5 min |
| Restore job start | 1 min |
| RDS restore in us-west-2 | 15-20 min |
| ECS update and health check | 3-5 min |
| **Total** | **~25 min** |
