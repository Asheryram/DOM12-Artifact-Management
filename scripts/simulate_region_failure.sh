#!/bin/bash
# FinCorp DR Lab - Simulate Region Failure by deleting the primary RDS instance
set -e

PROJECT_NAME="${PROJECT_NAME:-fincorp}"
PRIMARY_REGION="${PRIMARY_REGION:-eu-west-1}"
DB_IDENTIFIER="${PROJECT_NAME}-primary-db"

echo "======================================"
echo " FinCorp DR Simulation: Region Failure"
echo " Target: $DB_IDENTIFIER in $PRIMARY_REGION"
echo "======================================"
echo ""
echo "WARNING: This will DELETE the primary database instance."
read -p "Type 'CONFIRM' to proceed: " CONFIRM

if [ "$CONFIRM" != "CONFIRM" ]; then
  echo "Aborted."
  exit 1
fi

echo "[$(date)] Initiating deletion of $DB_IDENTIFIER in $PRIMARY_REGION..."

aws rds delete-db-instance \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --skip-final-snapshot \
  --region "$PRIMARY_REGION"

echo "[$(date)] Deletion initiated. Waiting for instance to be removed (~3-5 minutes)..."

aws rds wait db-instance-deleted \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --region "$PRIMARY_REGION"

echo "[$(date)] PRIMARY DATABASE DELETED. Region failure simulated."
echo ""
echo "Next step: Run ./scripts/restore_from_backup.sh to recover in DR region."
