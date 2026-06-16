#!/bin/bash
# FinCorp DR Lab - Simulate Region Failure
set -e

DB_IDENTIFIER="${PROJECT_NAME:-fincorp}-primary-db"
REGION="us-east-1"

echo "======================================"
echo " FinCorp DR Simulation: Region Failure"
echo " Target: $DB_IDENTIFIER in $REGION"
echo "======================================"
echo ""
echo "WARNING: This will DELETE the primary database."
read -p "Type 'CONFIRM' to proceed: " CONFIRM

if [ "$CONFIRM" != "CONFIRM" ]; then
  echo "Aborted."
  exit 1
fi

echo "[$(date)] Initiating deletion of $DB_IDENTIFIER..."

aws rds delete-db-instance \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --skip-final-snapshot \
  --region "$REGION"

echo "[$(date)] Deletion initiated. Waiting for instance to be removed..."

aws rds wait db-instance-deleted \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --region "$REGION"

echo "[$(date)] PRIMARY DATABASE DELETED. Region failure simulated."
echo ""
echo "Next step: Run ./scripts/restore_from_backup.sh to recover in us-west-2"
