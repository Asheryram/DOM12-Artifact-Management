#!/bin/bash
# FinCorp DR Lab - Restore from Cross-Region Backup in DR region
set -e

PROJECT_NAME="${PROJECT_NAME:-fincorp}"
PRIMARY_REGION="${PRIMARY_REGION:-eu-west-1}"
DR_REGION="${DR_REGION:-eu-central-1}"
DR_VAULT_NAME="${PROJECT_NAME}-backup-vault-dr"
RESTORE_DB_IDENTIFIER="${PROJECT_NAME}-restored-db"
DB_SUBNET_GROUP="${PROJECT_NAME}-dr-subnet-group"
RDS_SG_ID="${DR_RDS_SG_ID:?ERROR: DR_RDS_SG_ID must be set}"
BACKUP_ROLE_ARN="${BACKUP_ROLE_ARN:?ERROR: BACKUP_ROLE_ARN must be set}"
DB_NAME="${DB_NAME:-fincorpdb}"

echo "======================================"
echo " FinCorp DR Recovery"
echo " Vault : $DR_VAULT_NAME ($DR_REGION)"
echo " Target: $RESTORE_DB_IDENTIFIER"
echo "======================================"

echo "[$(date)] Finding latest completed recovery point in $DR_VAULT_NAME..."

RECOVERY_POINT_ARN=$(aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$DR_VAULT_NAME" \
  --region "$DR_REGION" \
  --query 'RecoveryPoints | sort_by(@, &CreationDate) | [-1].RecoveryPointArn' \
  --output text)

if [ -z "$RECOVERY_POINT_ARN" ] || [ "$RECOVERY_POINT_ARN" = "None" ]; then
  echo "ERROR: No recovery points found in $DR_VAULT_NAME."
  echo "Trigger an on-demand backup first and wait for the cross-region copy to complete."
  exit 1
fi

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
echo "[$(date)] Polling every 30 s (expect 15-20 minutes)..."
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
    echo " Elapsed: ${ELAPSED}s (~$(( ELAPSED / 60 )) min)"
    echo "======================================"
    break
  elif [ "$STATUS" = "FAILED" ] || [ "$STATUS" = "ABORTED" ]; then
    echo "RESTORE FAILED with status: $STATUS"
    aws backup describe-restore-job \
      --restore-job-id "$RESTORE_JOB_ID" \
      --region "$DR_REGION" \
      --query 'StatusMessage' \
      --output text
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
echo ""
echo "Next steps:"
echo "  1. Update Secrets Manager with the new host: $ENDPOINT"
echo "  2. Force a new ECS deployment: aws ecs update-service --cluster fincorp-cluster --service fincorp-service --force-new-deployment --region $PRIMARY_REGION"
echo "  3. Verify: DR_DB_ENDPOINT=$ENDPOINT DB_USERNAME=<user> DB_PASS=<pass> bash scripts/verify_dr.sh"
