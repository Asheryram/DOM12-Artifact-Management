#!/bin/bash
# FinCorp DR - Verify database connectivity and data integrity
set -e

DR_ENDPOINT="${DR_DB_ENDPOINT}"
DB_USER="${DB_USERNAME}"
DB_NAME="${DB_NAME:-fincorpdb}"

if [ -z "$DR_ENDPOINT" ] || [ -z "$DB_USER" ]; then
  echo "ERROR: Set DR_DB_ENDPOINT and DB_USERNAME environment variables."
  exit 1
fi

echo "Verifying connection to DR database at $DR_ENDPOINT..."

mysql -h "$DR_ENDPOINT" -u "$DB_USER" -p"${DB_PASS}" "$DB_NAME" <<EOF
SELECT 'Connection OK' AS status;
SELECT COUNT(*) AS transaction_count FROM transactions;
SELECT COUNT(*) AS category_count FROM categories;
SELECT type, SUM(amount) AS total FROM transactions GROUP BY type;
EOF

echo "DR verification complete."
