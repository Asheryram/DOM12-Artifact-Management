# FinCorp DR Runbook

**Primary region:** eu-west-1  
**DR region:** eu-central-1

## RTO / RPO Targets

| Metric | Target |
|---|---|
| RTO (Recovery Time Objective) | ≤ 30 minutes |
| RPO (Recovery Point Objective) | ≤ 24 hours (daily backup at 02:00 UTC) |

---

## Phase 0 — Pre-requisites Check

Before starting, confirm:

1. The Terraform `backup` module deployed successfully — vault `fincorp-backup-vault-dr` exists in eu-central-1
2. The DR VPC and subnet group `fincorp-dr-subnet-group` exist in eu-central-1
3. At least one recovery point exists in the DR vault (see Phase 1)

```bash
# Verify DR vault exists and has recovery points
MSYS_NO_PATHCONV=1 aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name fincorp-backup-vault-dr \
  --region eu-central-1 \
  --query 'RecoveryPoints[*].[Status,CreationDate]' \
  --output table
```

---

## Phase 1 — Create a Recovery Point

The backup plan fires daily at 02:00 UTC. For the lab, trigger one now.

### Console (recommended for screenshots)

1. AWS Console → **AWS Backup** → **Protected resources**
2. Find the RDS instance `fincorp-primary-db` → click **Create on-demand backup**
3. Settings:
   - Backup vault: `fincorp-backup-vault-primary`
   - IAM role: `fincorp-backup-role`
   - Enable **Copy to destination** → vault `fincorp-backup-vault-dr`, region `eu-central-1`
4. Click **Create on-demand backup**

> **Screenshot:** Backup Jobs page showing the backup job with status **Running**, then **Completed**.

5. Verify the copy: AWS Backup → switch region to **eu-central-1** → **Backup vaults** → `fincorp-backup-vault-dr` → **Recovery points**

> **Screenshot:** Recovery point in eu-central-1 showing status **Completed**.

### CLI alternative

```bash
BACKUP_ROLE_ARN=$(terraform output -raw backup_role_arn)
RDS_ARN=$(terraform output -raw primary_db_arn)

MSYS_NO_PATHCONV=1 aws backup start-backup-job \
  --backup-vault-name fincorp-backup-vault-primary \
  --resource-arn "$RDS_ARN" \
  --iam-role-arn "$BACKUP_ROLE_ARN" \
  --region eu-west-1

# Poll until the copy appears in eu-central-1 (5-10 min):
MSYS_NO_PATHCONV=1 aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name fincorp-backup-vault-dr \
  --region eu-central-1 \
  --query 'RecoveryPoints[*].[Status,CreationDate]' \
  --output table
```

Wait until status shows **COMPLETED** before proceeding.

---

## Phase 2 — Detection

Confirm the primary region is unhealthy before simulating failure:

- Open the CloudFront URL — app loads normally (green light)
- Hit `/api/health` — returns `{ "status": "healthy", "db": 1 }`

> **Screenshot:** App working normally before the failure.

---

## Phase 3 — Simulate Primary Region Failure

This permanently deletes the primary RDS instance to simulate eu-west-1 going down.

```bash
PRIMARY_REGION=eu-west-1 PROJECT_NAME=fincorp bash scripts/simulate_region_failure.sh
```

Type `CONFIRM` when prompted. Wait ~3–5 minutes for deletion to complete.

> **Screenshot:** RDS Console → Databases — `fincorp-primary-db` showing status **Deleting**.
> **Screenshot:** After deletion, the `/api/health` endpoint returns **503 Service Unavailable** — proves the failure is real.

---

## Phase 4 — Restore in eu-central-1

Get the required ARNs:

```bash
terraform output backup_role_arn
terraform output dr_rds_sg_id
```

Run the restore:

```bash
PRIMARY_REGION=eu-west-1 \
DR_REGION=eu-central-1 \
PROJECT_NAME=fincorp \
BACKUP_ROLE_ARN="<paste from terraform output backup_role_arn>" \
DR_RDS_SG_ID="<paste from terraform output dr_rds_sg_id>" \
DB_NAME=fincorpdb \
bash scripts/restore_from_backup.sh
```

The script polls every 30 seconds. Expected output after 15–20 minutes:

```
======================================
 RECOVERY SUCCESSFUL in eu-central-1
 Elapsed: 1180s (~19 min)
======================================
Restored DB Endpoint: fincorp-restored-db.xxxxxx.eu-central-1.rds.amazonaws.com
```

> **Screenshot:** Terminal output showing "RECOVERY SUCCESSFUL" with elapsed time.
> **Screenshot:** RDS Console in eu-central-1 → `fincorp-restored-db` in **Available** state.

---

## Phase 5 — Validate Data Integrity

Connect to the restored DB and verify the schema and row counts.
Run this from **AWS CloudShell** (switch the console to eu-central-1 first — no local MySQL client needed).

```bash
# In CloudShell (eu-central-1)
mysql -h fincorp-restored-db.xxxxxx.eu-central-1.rds.amazonaws.com \
      -u fincorp_admin \
      -p'YourStrongPassword123!' \
      fincorpdb \
      -e "SELECT 'Connection OK'; SELECT COUNT(*) AS categories FROM categories; SELECT COUNT(*) AS transactions FROM transactions;"
```

**Expected output:**
```
+--------------+
| Connection OK|
+--------------+
+------------+
| categories |
+------------+
|         13 |
+------------+
+-------------+----------+
| categories  | total    |
+-------------+----------+
...
```

> **Screenshot:** CloudShell terminal showing `Connection OK` and category/transaction counts.

---

## Phase 6 — Point ECS at the DR Database

Update the Secrets Manager secret so ECS picks up the new DB host on the next deployment:

```bash
DR_ENDPOINT="fincorp-restored-db.xxxxxx.eu-central-1.rds.amazonaws.com"

# Update secret (replace password with your actual value)
aws secretsmanager put-secret-value \
  --secret-id fincorp/db/credentials \
  --secret-string "{\"username\":\"fincorp_admin\",\"password\":\"YourStrongPassword123!\",\"host\":\"$DR_ENDPOINT\",\"port\":3306,\"dbname\":\"fincorpdb\"}" \
  --region eu-west-1

# Force new ECS deployment — new task reads updated secret
aws ecs update-service \
  --cluster fincorp-cluster \
  --service fincorp-service \
  --force-new-deployment \
  --region eu-west-1
```

Wait ~2–3 minutes for the new task to reach RUNNING status.

> **Screenshot:** ECS service → Tasks tab — new task in **RUNNING** state.
> **Screenshot:** App loading successfully from CloudFront URL — DR complete.

---

## Phase 7 — Post-Recovery Checklist

| Check | Command / Action |
|---|---|
| ECS task healthy | ECS Console → service → tasks → RUNNING |
| `/api/health` returns 200 | `curl https://<cloudfront>/api/health` |
| Transactions visible in UI | Open app in browser |
| CloudWatch logs show `Migrations complete` | CW → `/ecs/fincorp-backend` → latest stream |
| Notify stakeholders | — |

---

## Timeline Summary

| Phase | Action | Expected Time |
|---|---|---|
| 1 | On-demand backup + cross-region copy | 5–10 min |
| 3 | Simulate failure (delete RDS) | 3–5 min |
| 4 | Restore in eu-central-1 | 15–20 min |
| 5 | Validate data | 2 min |
| 6 | ECS update + health check | 3–5 min |
| **Total** | | **~28–42 min** |

**RTO target (≤ 30 min) is achievable** when the DR vault already has a recent recovery point (i.e., the daily backup has already run). The on-demand backup step adds 5–10 minutes only in lab scenarios.
