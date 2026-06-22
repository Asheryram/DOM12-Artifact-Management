# FinCorp Lab — Live Demo Walkthrough

> Start here once the pipeline has gone green. Follow each step, take the screenshot when prompted, and save it with the exact filename shown.

---

## PART A — Pipeline & App Verification

---

### Step 1 — Pipeline: All Three Stages Green

**Go to:** AWS Console → CodePipeline → `fincorp-pipeline`

Alright, this is the payoff. One `git push` to main and look — three green stages. Source, Build, Deploy. No one touched a server, no one ran a script manually. It's fully automated end-to-end. Point out the timestamp — it matches the last push.

### 📸 `01-pipeline-all-green.png`
> Three stages all showing **Succeeded** in green.

---

### Step 2 — ECR: Immutable Image, Clean Scan

**Go to:** ECR → Repositories → `fincorp-fincorp-app` → Images tab

Two things to show here. First, the tag — it's not `latest`, it's the first 8 characters of the Git commit SHA. Every image is permanently tied to the exact commit that built it. Second, the **Immutable** column. Nobody can push a different image under that same tag — rollbacks always get the original bytes.

Now click the SHA tag and open the **Vulnerabilities** tab. Zero HIGH, zero CRITICAL. The buildspec gate checked these results and only let the pipeline continue because the image was clean.

### 📸 `02-ecr-image-scan-pass.png`
> ECR images list showing the SHA tag, **Immutable**, and Scan status **Complete**. Then the vulnerability tab showing 0 HIGH / 0 CRITICAL.

---

### Step 3 — CodeArtifact: Packages Came From Here, Not npm

**Go to:** CodeArtifact → Repositories → `fincorp-npm-store` → Packages

CodeBuild never touched npmjs.org directly. Every dependency — express, helmet, mysql2, dotenv — was fetched through this private proxy and is now cached here in our account. The EXTERNAL origin column shows where each package originally came from. This is how we prevent dependency confusion attacks.

### 📸 `03-codeartifact-packages.png`
> The package list with EXTERNAL origin visible.

---

### Step 4 — CloudWatch: The Database Migrated Itself

**Go to:** CloudWatch → Log groups → `/ecs/fincorp-backend` → click the most recent log stream

Look at the top of the stream:

```
Migrations complete.
FinCorp API running on port 8080
```

The app read `init.sql` on startup and created the database schema by itself. No migration scripts, no SSH, no manual `mysql` client. The container bootstrapped the entire database on first run.

### 📸 `04-cloudwatch-migrations-complete.png`
> Log stream showing **"Migrations complete."** and **"FinCorp API running on port 8080"**.

---

### Step 5 — App Working End-to-End

**Get the URL:** run `terraform output app_frontend_url` and open it in a browser.

The React app loads from S3 through CloudFront. Open DevTools → Network tab, filter by `/api`, and refresh. Both `/api/transactions` and `/api/summary` return **200 OK** — and notice the request URL uses the CloudFront domain, not the ALB. The frontend proxies all API calls through CloudFront. No mixed-content errors.

Now go to `https://<cloudfront-domain>/api/health` in the address bar. What comes back:

```json
{ "success": true, "data": { "status": "healthy", "db": 1 } }
```

`db: 1` means the entire chain answered — CloudFront → ALB → ECS → RDS.

### 📸 `05-app-health-check.png`
> The `/api/health` JSON response showing `"db": 1` in the browser.

### 📸 `06-app-ui-running.png`
> The app UI loaded in the browser with the transaction/dashboard view visible.

---

## PART B — Disaster Recovery Simulation

> **This section takes 28–42 minutes.** Start Step 7 first, then go back and take the Part A screenshots while the backup runs.

---

### Step 6 — Trigger an On-Demand Backup

**Go to:** AWS Backup → Protected resources → `fincorp-primary-db` → **Create on-demand backup**

The backup plan runs at 02:00 UTC daily — we're not waiting. Fill in:
- Vault: `fincorp-backup-vault-primary`
- IAM role: `fincorp-backup-role`
- Enable **Copy to destination** → vault `fincorp-backup-vault-dr`, region **eu-central-1**

Hit **Create on-demand backup**. Go to Jobs → Backup jobs and wait for it to show Completed. Then switch region to **eu-central-1** → AWS Backup → `fincorp-backup-vault-dr` → Recovery points and confirm the copy landed there too.

### 📸 `07-backup-completed-dr-vault.png`
> The recovery point in `fincorp-backup-vault-dr` (eu-central-1) with status **Completed**.

---

### Step 7 — Simulate the Failure

Confirm the app is healthy first — open `/api/health` and verify `db: 1`. Then run:

```bash
PRIMARY_REGION=eu-west-1 PROJECT_NAME=fincorp bash scripts/simulate_region_failure.sh
```

Type `CONFIRM`. The script deletes `fincorp-primary-db` with no final snapshot — the database is permanently gone. Switch to the RDS console and watch it go to **Deleting**.

### 📸 `08-rds-primary-deleting.png`
> RDS console showing `fincorp-primary-db` with status **Deleting**.

Now refresh `/api/health`. The database is gone — you should see a 503 or error response. The failure is real.

### 📸 `09-app-503-down.png`
> Browser showing the 503 / database unreachable error on `/api/health`.

---

### Step 8 — Restore in eu-central-1

Get the values you need:

```bash
terraform output backup_role_arn
terraform output dr_rds_sg_id
```

Run the restore:

```bash
PRIMARY_REGION=eu-west-1 \
DR_REGION=eu-central-1 \
PROJECT_NAME=fincorp \
BACKUP_ROLE_ARN="<paste value>" \
DR_RDS_SG_ID="<paste value>" \
DB_NAME=fincorpdb \
bash scripts/restore_from_backup.sh
```

The script polls every 30 seconds. Wait 15–20 minutes. When you see this — that's the moment:

```
======================================
 RECOVERY SUCCESSFUL in eu-central-1
 Elapsed: 1180s (~19 min)
======================================
```

Check the elapsed time. Under 1800 seconds = under the 30-minute RTO target. Copy the restored endpoint from the output.

### 📸 `10-recovery-successful.png`
> Terminal showing **"RECOVERY SUCCESSFUL"** with the elapsed time visible.

Now switch to **eu-central-1** in the console → RDS → Databases.

### 📸 `11-rds-dr-available.png`
> RDS console in eu-central-1 showing `fincorp-restored-db` with status **Available**.

---

### Step 9 — Point ECS at the DR Database and Recover

Update Secrets Manager with the new host, then redeploy:

```bash
DR_ENDPOINT="fincorp-restored-db.xxxxxx.eu-central-1.rds.amazonaws.com"

aws secretsmanager put-secret-value \
  --secret-id fincorp/db/credentials \
  --secret-string "{\"username\":\"fincorp_admin\",\"password\":\"YourStrongPassword123!\",\"host\":\"$DR_ENDPOINT\",\"port\":3306,\"dbname\":\"fincorpdb\"}" \
  --region eu-west-1

aws ecs update-service \
  --cluster fincorp-cluster \
  --service fincorp-service \
  --force-new-deployment \
  --region eu-west-1
```

Wait 2–3 minutes for the new task to reach RUNNING, then open the app.

### 📸 `12-app-recovered.png`
> The app UI loading normally, or `/api/health` returning `"db": 1` — DR complete.

---

## Screenshot Summary

| Filename | What to show |
|---|---|
| `01-pipeline-all-green.png` | CodePipeline — all 3 stages Succeeded |
| `02-ecr-image-scan-pass.png` | ECR image with SHA tag + 0 HIGH/CRITICAL |
| `03-codeartifact-packages.png` | CodeArtifact npm package list |
| `04-cloudwatch-migrations-complete.png` | CloudWatch log — "Migrations complete." |
| `05-app-health-check.png` | `/api/health` response with `db: 1` |
| `06-app-ui-running.png` | App UI loaded in browser |
| `07-backup-completed-dr-vault.png` | Recovery point Completed in eu-central-1 vault |
| `08-rds-primary-deleting.png` | RDS `fincorp-primary-db` in Deleting state |
| `09-app-503-down.png` | App returning 503 after DB deleted |
| `10-recovery-successful.png` | Terminal — "RECOVERY SUCCESSFUL" + elapsed time |
| `11-rds-dr-available.png` | RDS `fincorp-restored-db` Available in eu-central-1 |
| `12-app-recovered.png` | App working again after DR |
