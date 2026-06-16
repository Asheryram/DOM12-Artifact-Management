#!/bin/bash
# FinCorp DR Lab - Restore from Cross-Region Backup
set -e

PROJECT_NAME="${PROJECT_NAME:-fincorp}"
DR_VAULT_NAME="${PROJECT_NAME}-backup-vault-dr"
DR_REGION="us-west-2"
RESTORE_DB_IDENTIFIER="${PROJECT_NAME}-restored-db"
DB_SUBNET_GROUP="${PROJECT_NAME}-dr-subnet-group"
RDS_SG_ID="${DR_RDS_SG_ID}"
BACKUP_ROLE_ARN="${BACKUP_ROLE_ARN}"
DB_NAME="${DB_NAME:-fincorpdb}"

echo "======================================"
echo " FinCorp DR Recovery: us-west-2"
echo "======================================"

echo "[$(date)] Finding latest recovery point in $DR_VAULT_NAME..."

RECOVERY_POINT_ARN=$(aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$DR_VAULT_NAME" \
  --region "$DR_REGION" \
  --query 'RecoveryPoints | sort_by(@, &CreationDate) | [-1].RecoveryPointArn' \
  --output text)

echo "[$(date)] Latest recovery point: $RECOVERY_POINT_ARN"

echo "[$(date)] Starting restore job in $DR_REGION..."

RESTORE_JOB_ID=$(aws backup start-restore-job \
  --recovery-point-arn "$RECOVERY_POINT_ARN" \
  --iam-role-arn "$BACKUP_ROLE_ARN" \
  --region "$DR_REGION" \
  --resource-type "RDS" \
  --metadata "{
    \"DBInstanceIdentifier\": \"$RESTORE_DB_IDENTIFIER\",
    \"DBSubnetGroupName\": \"$DB_SUBNET_GROUP\",
    \"VpcSecurityGroupIds\": \"$RDS_SG_ID\",
    \"MultiAZ\": \"false\",
    \"PubliclyAccessible\": \"false\"
  }" \
  --query 'RestoreJobId' \
  --output text)

echo "[$(date)] Restore job started: $RESTORE_JOB_ID"
echo "[$(date)] Waiting for restore to complete (10-25 minutes)..."
START_TIME=$(date +%s)

while true; do
  STATUS=$(aws backup describe-restore-job \
    --restore-job-id "$RESTORE_JOB_ID" \
    --region "$DR_REGION" \
    --query 'Status' \
    --output text)

  ELAPSED=$(( $(date +%s) - START_TIME ))
  echo "[$(date)] Status: $STATUS | Elapsed: ${ELAPSED}s"

  if [ "$STATUS" = "COMPLETED" ]; then
    echo ""
    echo "======================================"
    echo " RECOVERY SUCCESSFUL in $DR_REGION"
    echo " Elapsed: ${ELAPSED}s"
    echo "======================================"
    break
  elif [ "$STATUS" = "FAILED" ] || [ "$STATUS" = "ABORTED" ]; then
    echo "RESTORE FAILED with status: $STATUS"
    exit 1
  fi
  sleep 30
done

ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$RESTORE_DB_IDENTIFIER" \
  --region "$DR_REGION" \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

echo ""
echo "Restored DB Endpoint: $ENDPOINT"
echo "Run: ./scripts/verify_dr.sh"
