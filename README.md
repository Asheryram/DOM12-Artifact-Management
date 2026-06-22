# FinCorp Secure Supply Chain & Disaster Recovery Lab

A production-grade AWS infrastructure simulation demonstrating:
- Secure CI/CD with immutable artifacts (CodeArtifact + ECR image scanning)
- Automated backend DB migration on container startup
- Cross-region disaster recovery for RDS (eu-west-1 → eu-central-1, RTO ≤ 30 min)
- Expense & Income Tracker app on ECS Fargate + RDS MySQL + CloudFront

---

## Prerequisites

- AWS CLI configured (AdministratorAccess or the DCE sandbox role)
- Terraform >= 1.6
- Docker installed and running
- Node.js >= 18
- GitHub repository with this code pushed to `main`

---

## Deployment

### 1. Set sensitive variables

```bash
export TF_VAR_db_username="fincorp_admin"
export TF_VAR_db_password="YourStrongPassword123!"   # min 16 chars
export TF_VAR_github_repo="your-org/your-repo"       # e.g. Asheryram/DOM12-Artifact-Management
export TF_VAR_codestar_connection_arn=""              # fill in after step 3
```

### 2. Bootstrap infrastructure

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 3. Create the GitHub connection (manual — one-time)

CodePipeline cannot authorise GitHub automatically — this step must be done in the console:

1. AWS Console → **Developer Tools** → **Settings** → **Connections**
2. Click **Create connection** → choose **GitHub**
3. Name it (e.g. `fincorp-github`), click **Connect to GitHub**
4. Install / authorise the **AWS Connector for GitHub** app for your repo
5. Click **Connect**, then copy the full **Connection ARN**
6. Set the variable and re-apply:

```bash
export TF_VAR_codestar_connection_arn="arn:aws:codeconnections:eu-west-1:ACCT:connection/UUID"
terraform apply
```

### 4. Trigger first build

```bash
git push origin main
# Watch: AWS Console → CodePipeline → fincorp-pipeline
```

The pipeline will:
- Pull source from GitHub
- Install backend deps via CodeArtifact (npm-store)
- Build & push Docker image to ECR with a commit-SHA tag
- Wait 60 s then check for HIGH/CRITICAL CVEs (fails build if found)
- Build the React frontend (`npm run build`)
- Sync the built assets to S3 + invalidate CloudFront
- Write `imagedefinitions.json` and deploy the new image to ECS

> **Database migrations run automatically.** On ECS task startup, `index.js` reads
> `src/migrations/init.sql` and runs every statement. Tables are created with
> `CREATE TABLE IF NOT EXISTS` so re-runs are safe.

### 5. Get the app URLs

```bash
terraform output app_frontend_url   # CloudFront HTTPS URL
terraform output app_alb_dns        # ALB HTTP URL (internal)
```

Open the CloudFront URL in your browser. The frontend proxies `/api/*` through
CloudFront to the ALB, so there are no mixed-content errors.

---

## Part 2 — Screenshot Walkthrough

> See **[docs/walkthrough.md](docs/walkthrough.md)** for the full step-by-step screenshot guide — 21 numbered screenshots covering pipeline verification, app health, and the complete DR simulation.

**Quick reference — screenshots to take after the pipeline goes green:**

| # | Where | What it proves |
|---|---|---|
| 1 | CodePipeline → `fincorp-pipeline` | All 3 stages Succeeded |
| 2 | CodeBuild log → "Security scan passed" | Vulnerability gate ran and cleared |
| 3 | ECR → image with commit SHA + Immutable | Traceable, immutable artifact |
| 4 | ECR → 0 HIGH / 0 CRITICAL CVEs | Image safe to deploy |
| 5 | CodeArtifact → npm packages cached | Supply chain proxy working |
| 6 | CloudWatch `/ecs/fincorp-backend` → "Migrations complete." | Auto-migration, no manual DB work |
| 7 | App UI + DevTools 200 OK on `/api/*` | Frontend + API through CloudFront |
| 8 | `/api/health` → `db: 1` | Full ECS → RDS connectivity |
| 9 | ECS task → image URI with commit SHA | Running image tied to Git commit |
| 10 | S3 bucket → `index.html` + `assets/` | Pipeline deployed the frontend build |

---

## Part 3 — Disaster Recovery Simulation

> **Time required:** ~25–30 minutes end-to-end.
> The RDS restore in eu-central-1 takes 15–20 minutes on its own.

### Phase 1 — Trigger an On-Demand Backup

The backup plan runs daily at 02:00 UTC. For the lab, trigger one immediately:

**AWS Console:**
1. Go to **AWS Backup** → **Protected resources**
2. Find the RDS instance `fincorp-primary-db`
3. Click **Create on-demand backup**
4. Vault: `fincorp-backup-vault-primary`
5. IAM role: select the `fincorp-backup-role` (from Terraform)
6. Enable **Copy to destination**: vault `fincorp-backup-vault-dr` in **eu-central-1**
7. Click **Create on-demand backup**

> **Screenshot:** AWS Backup → Jobs → Backup jobs — show the job running then completed.

**Or via CLI:**

```bash
# Get the backup role ARN
BACKUP_ROLE_ARN=$(terraform output -raw backup_role_arn)
RDS_ARN=$(terraform output -raw primary_db_arn)

aws backup start-backup-job \
  --backup-vault-name fincorp-backup-vault-primary \
  --resource-arn "$RDS_ARN" \
  --iam-role-arn "$BACKUP_ROLE_ARN" \
  --region eu-west-1

# Wait ~5-10 minutes, then verify the copy arrived in eu-central-1:
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name fincorp-backup-vault-dr \
  --region eu-central-1 \
  --query 'RecoveryPoints[*].[Status,CreationDate]' \
  --output table
```

Wait until the DR vault shows a recovery point with status **COMPLETED** before proceeding.

> **Screenshot:** The recovery point listed in `fincorp-backup-vault-dr` in eu-central-1.

---

### Phase 2 — Simulate the Primary Region Failure

This deletes the primary RDS instance to simulate eu-west-1 going down.

```bash
# PowerShell or Git Bash (MSYS_NO_PATHCONV=1 prefix if using Git Bash)
PRIMARY_REGION=eu-west-1 PROJECT_NAME=fincorp bash scripts/simulate_region_failure.sh
```

Type `CONFIRM` when prompted. The script:
1. Calls `aws rds delete-db-instance --skip-final-snapshot`
2. Waits until the instance is fully deleted (~5 min)

> **Screenshot:** RDS Console → Databases — show `fincorp-primary-db` in **Deleting** state.

At this point, the app's `/api/health` will return 503 — this is expected.

> **Screenshot:** Browser showing 503 on `/api/health` (proves the failure is real).

---

### Phase 3 — Restore in eu-central-1

Get the required values from Terraform:

```bash
terraform output backup_role_arn
terraform output dr_rds_sg_id
```

Run the restore script:

```bash
PRIMARY_REGION=eu-west-1 \
DR_REGION=eu-central-1 \
PROJECT_NAME=fincorp \
BACKUP_ROLE_ARN="<from terraform output backup_role_arn>" \
DR_RDS_SG_ID="<from terraform output dr_rds_sg_id>" \
DB_NAME=fincorpdb \
bash scripts/restore_from_backup.sh
```

The script:
1. Finds the latest recovery point in `fincorp-backup-vault-dr` (eu-central-1)
2. Starts a restore job into the DR VPC and subnet group
3. Polls every 30 s and prints elapsed time
4. Prints the restored endpoint when done

Expected output after ~15–20 minutes:
```
======================================
 RECOVERY SUCCESSFUL in eu-central-1
 Elapsed: 1180s
======================================
Restored DB Endpoint: fincorp-restored-db.xxxxxx.eu-central-1.rds.amazonaws.com
```

> **Screenshot:** Terminal showing "RECOVERY SUCCESSFUL" with elapsed time.
> **Screenshot:** RDS Console in eu-central-1 → `fincorp-restored-db` in **Available** state.

---

### Phase 4 — Validate Data Integrity

The verify script connects to the restored DB and counts rows. Because RDS requires a MySQL client, run this from AWS CloudShell (eu-central-1):

**AWS Console → CloudShell (switch region to eu-central-1)**

```bash
# Get the credentials from Secrets Manager in the primary region
# (or use the values you set in TF_VAR_* env vars)
DR_DB_ENDPOINT="fincorp-restored-db.xxxxxx.eu-central-1.rds.amazonaws.com"
DB_USERNAME="fincorp_admin"
DB_PASS="YourStrongPassword123!"

mysql -h "$DR_DB_ENDPOINT" -u "$DB_USERNAME" -p"$DB_PASS" fincorpdb \
  -e "SELECT 'Connection OK'; SELECT COUNT(*) AS categories FROM categories; SELECT COUNT(*) AS transactions FROM transactions;"
```

**Expected output:**
```
Connection OK
+------------+
| categories |
+------------+
|         13 |
+------------+
```

> **Screenshot:** CloudShell terminal showing `Connection OK` and the row counts.

---

### Phase 5 — Update ECS to Point at DR Database

Update the Secrets Manager secret in eu-west-1 with the new host, then force a new ECS deployment:

```bash
DR_ENDPOINT="fincorp-restored-db.xxxxxx.eu-central-1.rds.amazonaws.com"

# Update the secret
aws secretsmanager put-secret-value \
  --secret-id fincorp/db/credentials \
  --secret-string "{\"username\":\"fincorp_admin\",\"password\":\"YourStrongPassword123!\",\"host\":\"$DR_ENDPOINT\",\"port\":3306,\"dbname\":\"fincorpdb\"}" \
  --region eu-west-1

# Force new ECS deployment (picks up new secret on task start)
aws ecs update-service \
  --cluster fincorp-cluster \
  --service fincorp-service \
  --force-new-deployment \
  --region eu-west-1
```

Wait ~2 minutes for the new task to be healthy, then open the CloudFront URL and confirm the app is working.

> **Screenshot:** ECS service showing new task in **RUNNING** state.
> **Screenshot:** App loading successfully — DR complete.

---

### DR Timeline Summary

| Step | Action | Expected Time |
|---|---|---|
| 1 | On-demand backup + cross-region copy | 5–10 min |
| 2 | Simulate failure (delete primary RDS) | 3–5 min |
| 3 | Restore in eu-central-1 | 15–20 min |
| 4 | Validate data integrity | 2 min |
| 5 | Update ECS + new deployment | 3–5 min |
| **Total** | | **~28–42 min** |

---

## Cleanup

```bash
terraform destroy
```

If destroy fails on target groups, manually delete the ALB listener first:
AWS Console → EC2 → Load Balancers → `fincorp-alb` → Listeners → Delete listener, then re-run.

---

## Project Structure

```
DOM12-Artifact-Management/
├── main.tf / variables.tf / outputs.tf / versions.tf / terraform.tfvars
├── modules/
│   ├── networking/      Custom VPC, subnets, IGW, VPC endpoints (no NAT)
│   ├── ecr/             ECR repo (immutable tags, AES256, scan-on-push, force_delete)
│   ├── codeartifact/    npm + pip proxy repositories
│   ├── codepipeline/    CodePipeline + CodeBuild + buildspec.yml
│   ├── iam/             Least-privilege roles for all services
│   ├── rds_primary/     RDS MySQL in eu-west-1 (encrypted, private subnet)
│   ├── rds_dr/          DR VPC + subnets + SG pre-provisioned in eu-central-1
│   ├── backup/          AWS Backup with daily schedule + cross-region copy
│   ├── app_backend/     ECS Fargate + ALB (private subnets, VPC endpoints)
│   └── app_frontend/    S3 + CloudFront (ALB origin for /api/* proxy)
├── app/
│   ├── backend/         Node.js Express API (auto-migrates DB on startup)
│   └── frontend/        React SPA (Vite, relative API URLs via CloudFront proxy)
├── scripts/
│   ├── simulate_region_failure.sh
│   ├── restore_from_backup.sh
│   └── verify_dr.sh
└── docs/
    ├── architecture.md
    ├── dr_runbook.md
    └── pipeline_guide.md
```

## Documentation

- [Screenshot Walkthrough](docs/walkthrough.md) — step-by-step screenshot guide (pipeline through DR)
- [Architecture](docs/architecture.md)
- [DR Runbook](docs/dr_runbook.md)
- [Pipeline Guide](docs/pipeline_guide.md)
