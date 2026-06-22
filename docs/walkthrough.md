# FinCorp Lab — Screenshot Walkthrough

This guide walks through the entire lab in screenshot order. Start from Step 1 if the pipeline has just gone green. Each step tells you exactly where to navigate, what to look for, and what the screenshot proves.

---

## PART A — Pipeline & Application Verification

### Step 1 — CodePipeline: All Three Stages Green

**Navigate to:** AWS Console → CodePipeline → Pipelines → `fincorp-pipeline`

**What to look for:**
- Three stages stacked vertically: **Source**, **Build_and_Scan**, **Deploy**
- Each stage has a green **Succeeded** label
- The most recent execution timestamp is visible

**What this proves:** A single `git push` triggers the full pipeline — source pull, image build, vulnerability scan, frontend deploy, and ECS deploy — all automated.

> Take the screenshot with all three stages visible and their green badges showing.

---

### Step 2 — Build Stage Expanded: CodeBuild Detail

**Navigate to:** Same pipeline page → click **Details** inside the `Build_and_Scan` stage

**What to look for:**
- CodeBuild project name: `fincorp-build`
- Status: **Succeeded**
- Duration shown (typically 4–7 minutes)

Click **View logs** to open CloudWatch. Look for these lines in the log output:
```
Security scan passed. Image is clean.
Build phase complete.
```

**What this proves:** The vulnerability gate ran and no HIGH or CRITICAL CVEs were found. Build only passed because the image is clean.

> Screenshot the build log with "Security scan passed" visible.

---

### Step 3 — ECR: Immutable Image Tag

**Navigate to:** AWS Console → ECR → Repositories → `fincorp-fincorp-app` → Images tab

**What to look for:**
- An image with an 8-character commit SHA tag (e.g. `a1b2c3d4`) — not `latest`
- **Tag immutability** column: **Immutable**
- **Scan status** column: **Complete**
- Push date matching your most recent pipeline run

**What this proves:** Images are tagged with the exact Git commit SHA, making every deployment traceable to a specific code change. The `IMMUTABLE` tag prevents overwriting — a rollback always gets the exact original image.

> Screenshot the images list with the tag, immutability, and scan status all visible.

---

### Step 4 — ECR: Vulnerability Scan Results

**Navigate to:** (still on ECR) → click the commit SHA image tag → **Vulnerabilities** tab

**What to look for:**
- Scan status: **Complete**
- **CRITICAL: 0, HIGH: 0** (or a low count of MEDIUM/LOW only)
- If there are findings, the severity distribution chart shows no red/orange bars

**What this proves:** Amazon Inspector scanned the Docker image layers. The buildspec gate would have failed the pipeline if HIGH or CRITICAL findings existed — so reaching Deploy proves the image is clean.

> Screenshot the vulnerability detail page showing 0 HIGH and 0 CRITICAL.

---

### Step 5 — CodeArtifact: npm Packages Cached

**Navigate to:** AWS Console → CodeArtifact → Repositories → `fincorp-npm-store` → Packages

**What to look for:**
- A list of npm packages (express, cors, helmet, mysql2, dotenv, etc.)
- Each package shows its version
- Origin: **EXTERNAL** (fetched from npmjs.org and now cached here)

**What this proves:** CodeBuild installed dependencies through CodeArtifact acting as a caching proxy. The packages are now stored in your account — future builds won't depend on npmjs.org availability, and you have a full audit trail of every dependency version used.

> Screenshot the package list with at least 5–6 packages visible.

---

### Step 6 — CloudWatch Logs: Auto-Migration Confirmation

**Navigate to:** AWS Console → CloudWatch → Log groups → `/ecs/fincorp-backend`

Click the **most recent log stream** (named like `ecs/fincorp-backend/TASK-ID`).

**What to look for near the top of the stream:**
```
Migrations complete.
FinCorp API running on port 8080
```

**What this proves:** The backend ran `init.sql` on startup using `CREATE TABLE IF NOT EXISTS`, creating the database schema automatically — no manual `mysql` client or migration command was needed. The ECS task is self-bootstrapping.

> Screenshot the log stream with "Migrations complete." and "FinCorp API running on port 8080" visible.

> **Note if using Git Bash:** Prefix AWS CLI commands with `MSYS_NO_PATHCONV=1` when the path starts with `/`.

---

### Step 7 — App: Frontend Loading in Browser

**Get the URL:**
```bash
terraform output app_frontend_url
```

Open the URL in your browser.

**What to look for:**
- The FinCorp Expense & Income Tracker interface loads
- No "FinCorp Expense & Income Tracker — Deploy the React app via CodePipeline" placeholder
- The transaction list is visible (empty is fine — it means DB is connected and returned 0 rows)

Open **DevTools → Network tab**, filter by `api`, and refresh.

**What to look for in the Network tab:**
- `GET /api/transactions?limit=10` → **200 OK**
- `GET /api/summary` → **200 OK**
- Request URL starts with the CloudFront domain (not the ALB) — this confirms the `/api/*` proxy through CloudFront is working

**What this proves:** The React frontend is served from S3 via CloudFront. API calls are proxied through CloudFront to the ALB over HTTPS — no mixed content errors.

> Screenshot 1: the app UI with the transaction list visible.
> Screenshot 2: DevTools Network tab with the 200 OK responses to `/api/transactions` and `/api/summary`.

---

### Step 8 — Health Check: End-to-End Connectivity

**Open in browser:**
```
https://<your-cloudfront-domain>/api/health
```

**Expected response:**
```json
{
  "success": true,
  "data": {
    "status": "healthy",
    "db": 1
  }
}
```

**What this proves:** The full chain is working — CloudFront → ALB → ECS Fargate → RDS MySQL. The `db: 1` field comes from `SELECT 1 AS ok` running against the live database.

> Screenshot the raw JSON response in the browser.

---

### Step 9 — ECS: Running Task with Correct Image

**Navigate to:** AWS Console → ECS → Clusters → `fincorp-cluster` → Services → `fincorp-service` → Tasks tab

**What to look for:**
- At least 1 task with status **RUNNING**
- Click the task ID → scroll to **Containers** section → **Image** field
- The image URI ends with the same 8-character commit SHA from Step 3

**What this proves:** ECS is running exactly the image that passed the vulnerability scan. The image tag ties the running container back to the specific Git commit.

> Screenshot the task detail showing the image URI with the commit SHA tag.

---

### Step 10 — S3: Frontend Assets Deployed by Pipeline

**Navigate to:** AWS Console → S3 → Buckets → `fincorp-frontend-*` → Objects

**What to look for:**
- `index.html` at the root
- An `assets/` folder containing hashed JS and CSS filenames (e.g. `index-Ab3xK.js`)
- Click `index.html` → **Properties** tab → **Metadata** → `Cache-Control: no-cache`

**What this proves:** The pipeline's `post_build` phase ran `aws s3 sync` to deploy the React build output. The `no-cache` header on `index.html` ensures users always get the latest version after a new deploy.

> Screenshot the S3 bucket object list with `index.html` and `assets/` visible.

---

## PART B — Disaster Recovery Simulation

> **Time required:** 28–42 minutes. Start the on-demand backup first, then take the Part A screenshots while you wait.

---

### Step 11 — AWS Backup: On-Demand Backup Job

**Navigate to:** AWS Console → AWS Backup → **My account** → **Create on-demand backup**

Settings to use:
- Resource type: **RDS**
- Resource ID: `fincorp-primary-db`
- Backup vault: `fincorp-backup-vault-primary`
- IAM role: `fincorp-backup-role`
- Enable **Copy to destination region**: vault `fincorp-backup-vault-dr`, region **eu-central-1**

Click **Create on-demand backup**.

**Navigate to:** AWS Backup → **Jobs** → **Backup jobs** tab

**What to look for:**
- A new backup job with resource `fincorp-primary-db`
- Status changes: `Created` → `Running` → `Completed`

**What this proves:** AWS Backup is protecting the RDS instance and copying the recovery point cross-region to the DR vault.

> Screenshot the backup job in **Running** state.
> Screenshot again when it shows **Completed**.

---

### Step 12 — DR Vault: Recovery Point Arrived in eu-central-1

**Navigate to:** AWS Console → **switch region to eu-central-1** → AWS Backup → Backup vaults → `fincorp-backup-vault-dr` → Recovery points tab

**What to look for:**
- A recovery point with status **Completed**
- Resource type: **RDS**
- Creation date matches the backup from Step 11

**What this proves:** The cross-region copy succeeded. The recovery point is now available in the DR region and can be used to restore an RDS instance independently of the primary region.

> Screenshot the recovery point list showing status **Completed** in eu-central-1.

---

### Step 13 — Confirm App Healthy Before Failure

**Open in browser:**
```
https://<your-cloudfront-domain>/api/health
```

Confirm it still returns `{ "success": true, "data": { "status": "healthy", "db": 1 } }`.

**What this proves:** Baseline — the app is healthy before the simulated failure.

> Screenshot the health check returning 200 with `db: 1`.

---

### Step 14 — Simulate Failure: Delete Primary RDS

Run in terminal (PowerShell or Git Bash with `MSYS_NO_PATHCONV=1`):

```bash
PRIMARY_REGION=eu-west-1 PROJECT_NAME=fincorp bash scripts/simulate_region_failure.sh
```

Type `CONFIRM` when prompted.

**Navigate to:** AWS Console (eu-west-1) → RDS → Databases

**What to look for:**
- `fincorp-primary-db` with status **Deleting**
- After 3–5 minutes: the instance disappears from the list

**What this proves:** The primary database is gone — simulating an unrecoverable regional failure.

> Screenshot the RDS console showing `fincorp-primary-db` in **Deleting** state.

---

### Step 15 — App Showing Failure

**Open in browser:**
```
https://<your-cloudfront-domain>/api/health
```

**What to look for:**
- Response: `{ "success": false, "error": "Database unreachable" }` with HTTP 503
- Or the browser shows a 5xx error

**What this proves:** The failure is real — the application is down because the database is gone.

> Screenshot the 503 / error response in the browser.

---

### Step 16 — Restore Script Running in Terminal

Get the required values:
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

**What to look for in the terminal:**
- `Starting restore job in eu-central-1...`
- `Restore job started: XXXX`
- Polling lines: `Status: RUNNING | Elapsed: 30s`, `60s`, `90s`...

> Screenshot the terminal while it is polling — shows the restore is in progress.

---

### Step 17 — Recovery Successful: Terminal Output

Wait 15–20 minutes for the restore to complete.

**What to look for in the terminal:**
```
======================================
 RECOVERY SUCCESSFUL in eu-central-1
 Elapsed: 1180s (~19 min)
======================================
Restored DB Endpoint: fincorp-restored-db.xxxxxx.eu-central-1.rds.amazonaws.com
```

**What this proves:** RDS was fully restored from the cross-region backup within the RTO window.

> Screenshot the terminal showing "RECOVERY SUCCESSFUL" with the elapsed time and restored endpoint.

---

### Step 18 — RDS Restored in eu-central-1

**Navigate to:** AWS Console → **switch region to eu-central-1** → RDS → Databases

**What to look for:**
- A new instance named `fincorp-restored-db`
- Status: **Available**
- Engine: MySQL 8.0
- Subnet group: `fincorp-dr-subnet-group`

**What this proves:** The database is running in the DR region inside the pre-provisioned DR VPC, ready to accept connections.

> Screenshot the RDS console in eu-central-1 showing `fincorp-restored-db` as **Available**.

---

### Step 19 — Data Integrity: CloudShell Verification

**Navigate to:** AWS Console → **switch region to eu-central-1** → CloudShell (top bar icon)

Run in CloudShell:
```bash
mysql -h fincorp-restored-db.xxxxxx.eu-central-1.rds.amazonaws.com \
      -u fincorp_admin \
      -p'YourStrongPassword123!' \
      fincorpdb \
      -e "SELECT 'Connection OK'; SELECT COUNT(*) AS categories FROM categories;"
```

**What to look for:**
```
+--------------+
| Connection OK|
+--------------+
+------------+
| categories |
+------------+
|         13 |
+------------+
```

**What this proves:** The restored database has the correct schema (13 categories) — data integrity is confirmed. The RPO is met: the backup captured the state before the failure.

> Screenshot the CloudShell terminal with "Connection OK" and the category count visible.

---

### Step 20 — Update ECS and Restore the App

Update Secrets Manager with the DR endpoint, then force a new deployment:

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

**Navigate to:** ECS → Clusters → `fincorp-cluster` → Services → `fincorp-service` → Tasks tab

**What to look for:**
- A new task spinning up alongside the old one
- Old task drains and stops
- New task status: **RUNNING**

> Screenshot the ECS tasks tab showing the new task in **RUNNING** state.

---

### Step 21 — App Recovered: Final Confirmation

**Open in browser:**
```
https://<your-cloudfront-domain>/api/health
```

**What to look for:**
```json
{ "success": true, "data": { "status": "healthy", "db": 1 } }
```

Also open the main app URL and confirm the transactions/categories load normally.

**What this proves:** The full DR scenario is complete — primary region failed, database was restored from a cross-region backup in ~20 minutes, ECS was repointed, and the app is fully operational from the DR database.

> Screenshot the health check showing `db: 1`.
> Screenshot the app UI loading normally.

---

## Summary: Screenshot Checklist

| # | Screenshot | What it proves |
|---|---|---|
| 1 | CodePipeline — all 3 stages green | Automated pipeline end-to-end |
| 2 | CodeBuild log — "Security scan passed" | Vulnerability gate ran and passed |
| 3 | ECR — image with commit SHA + Immutable tag | Traceable, immutable artifact |
| 4 | ECR — 0 HIGH / 0 CRITICAL CVEs | Image is safe to deploy |
| 5 | CodeArtifact — npm packages cached | Supply chain control (no direct npmjs.org) |
| 6 | CloudWatch — "Migrations complete." | Auto-migration, no manual DB setup |
| 7a | App UI loading in browser | Frontend deployed via pipeline |
| 7b | DevTools — 200 OK on /api/transactions | API reachable through CloudFront proxy |
| 8 | /api/health → `db: 1` | Full stack connectivity |
| 9 | ECS task detail — image URI with commit SHA | Running image tied to the Git commit |
| 10 | S3 bucket — index.html + assets/ | Pipeline deployed the frontend build |
| 11a | Backup job — Running | Backup in progress |
| 11b | Backup job — Completed | Backup succeeded |
| 12 | DR vault recovery point — Completed (eu-central-1) | Cross-region copy succeeded |
| 13 | Health check — healthy (before failure) | Baseline confirmation |
| 14 | RDS — fincorp-primary-db Deleting | Failure simulated |
| 15 | Browser — 503 on /api/health | App is down (failure confirmed) |
| 16 | Terminal — restore polling output | Restore in progress |
| 17 | Terminal — "RECOVERY SUCCESSFUL" | RDS restored within RTO |
| 18 | RDS (eu-central-1) — fincorp-restored-db Available | DR database live |
| 19 | CloudShell — "Connection OK" + 13 categories | Data integrity confirmed |
| 20 | ECS — new task RUNNING | ECS repointed to DR database |
| 21a | Health check — `db: 1` (post-recovery) | Full stack working from DR |
| 21b | App UI loading normally | DR complete, app fully recovered |
