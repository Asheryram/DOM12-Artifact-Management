# FinCorp Lab — Live Demo Walkthrough

> Start here once the pipeline has gone green. Each step tells you where to go, what to point out, and why it matters.

---

## PART A — Pipeline & App Verification

---

### Step 1 — Pipeline: All Three Stages Green

**Go to:** AWS Console → CodePipeline → `fincorp-pipeline`

Alright, this is the payoff. One `git push` to main and look — three green stages. Source, Build, Deploy. No one touched a server, no one ran a script manually. It's fully automated end-to-end.

Point out the **timestamp** on the most recent execution — it matches the last push. Then expand the `Build_and_Scan` stage so the CodeBuild action name is visible.

**📸 Screenshot here.** This is your proof of automated delivery.

---

### Step 2 — Build Stage: Security Gate Passed

**Go to:** (still on the pipeline) → click **Details** inside `Build_and_Scan` → **View logs**

Let's open the build and show what actually happened. Scroll through the log until you see this line:

```
Security scan passed. Image is clean.
```

That line means Amazon Inspector scanned every layer of the Docker image and our gate checked the result. No HIGH vulnerabilities, no CRITICAL ones. If it had found any — the buildspec would have called `exit 1`, the pipeline would have turned red, and **nothing would have deployed**. The vulnerability gate is the reason the Deploy stage even ran.

**📸 Screenshot the log** with "Security scan passed." visible.

---

### Step 3 — ECR: The Image Tag Is a Receipt

**Go to:** ECR → Repositories → `fincorp-fincorp-app` → Images tab

Notice the tag on that image. It's not `latest` — it's the first 8 characters of the Git commit SHA. Every image is permanently tied to the exact commit that built it.

Now look at the **Tag immutability** column: **Immutable**. That means nobody can push a different image under that same tag. Ever. If you need to roll back, that tag will always give you the exact original bytes.

**📸 Screenshot** showing the SHA tag, the Immutable column, and the Scan status: Complete.

---

### Step 4 — ECR: Zero HIGH, Zero CRITICAL

**Go to:** (still in ECR) → click the SHA tag → **Vulnerabilities** tab

Amazon Inspector scanned the image layers and here are the results. Zero HIGH, zero CRITICAL. This is two layers of defense working together: the scan at push time, and the gate in the buildspec that would have blocked deployment if this wasn't clean.

**📸 Screenshot** showing 0 HIGH and 0 CRITICAL on the vulnerability detail page.

---

### Step 5 — CodeArtifact: Packages Came From Here, Not npm

**Go to:** CodeArtifact → Repositories → `fincorp-npm-store` → Packages

CodeBuild never went to npmjs.org directly. It fetched every dependency through this private proxy. These packages — express, helmet, mysql2, dotenv — they're all cached here in our account now.

Why does this matter? **Dependency confusion attacks.** An attacker publishes a malicious package with the same name as an internal one. If your build hits the public registry first, you get the attacker's version. This proxy prevents that — our registry is ours.

**📸 Screenshot** the package list with the EXTERNAL origin column visible.

---

### Step 6 — CloudWatch: The DB Migrated Itself

**Go to:** CloudWatch → Log groups → `/ecs/fincorp-backend` → click the most recent log stream

> **Note (Git Bash):** Prefix any CLI command touching `/ecs/...` paths with `MSYS_NO_PATHCONV=1`.

Look at the very top of the stream:

```
Migrations complete.
FinCorp API running on port 8080
```

The app read `init.sql` on startup and created the database schema itself. No one ran a migration script. No SSH into a bastion host, no manual `mysql` client. The container bootstrapped itself, using `CREATE TABLE IF NOT EXISTS` so it's safe to run on every restart.

**📸 Screenshot** with "Migrations complete." and "FinCorp API running on port 8080" both visible.

---

### Step 7 — App: Frontend Served, API Proxied

**Get the URL:** `terraform output app_frontend_url` — open it in a browser.

The app loads. This is the React SPA, served from S3 through CloudFront.

Now open **DevTools → Network tab**, filter by `/api`, and refresh the page. Look at those requests — `GET /api/transactions` and `GET /api/summary`, both returning **200 OK**. Notice the request URL starts with the CloudFront domain, not the ALB address. The frontend uses relative API paths, CloudFront proxies `/api/*` to the load balancer internally. No mixed-content errors, no CORS issues, HTTPS all the way through.

**📸 Screenshot 1:** The app UI loaded in the browser.  
**📸 Screenshot 2:** DevTools Network tab showing 200 OK on `/api/transactions` and `/api/summary`.

---

### Step 8 — Health Check: The Whole Stack Answers

**Open in browser:**
```
https://<your-cloudfront-domain>/api/health
```

What comes back is the entire architecture in one JSON response:

```json
{ "success": true, "data": { "status": "healthy", "db": 1 } }
```

`db: 1` comes from `SELECT 1 AS ok` running against RDS. Every hop in the diagram just answered — CloudFront, ALB, ECS Fargate, RDS MySQL. All green.

**📸 Screenshot** the raw JSON in the browser.

---

### Step 9 — ECS Task: Running the Exact Scanned Image

**Go to:** ECS → Clusters → `fincorp-cluster` → Services → `fincorp-service` → Tasks tab → click the task ID

Scroll to the **Containers** section and look at the **Image** field. The URI ends with the same 8-character commit SHA from Step 3. The container running right now is provably the same image that passed the vulnerability scan. You can trace from "it's running" all the way back to the Git commit, through the pipeline, through the scan.

**📸 Screenshot** the task detail with the image URI showing the commit SHA.

---

### Step 10 — S3: Pipeline Deployed the Frontend

**Go to:** S3 → find the bucket named `fincorp-frontend-*` → Objects

`index.html` is there. The `assets/` folder has files with hashed names — those are the JS and CSS bundles. Hashed filenames get cached aggressively by CloudFront. `index.html` gets `Cache-Control: no-cache`, so the browser always fetches it fresh. That's how you get aggressive caching without ever serving stale JavaScript.

None of this was uploaded manually. The pipeline's `post_build` phase ran `aws s3 sync` and put it all here.

**📸 Screenshot** the bucket object list with `index.html` and `assets/` visible.

---

## PART B — Disaster Recovery Simulation

> **This section takes 28–42 minutes.** Kick off Step 11 first, then take the Part A screenshots while you wait for the backup to complete.

---

### Step 11 — Trigger an On-Demand Backup

**Go to:** AWS Backup → Protected resources → find `fincorp-primary-db` → **Create on-demand backup**

The backup plan fires daily at 02:00 UTC — we're not waiting for that. Settings:

- Backup vault: `fincorp-backup-vault-primary`
- IAM role: `fincorp-backup-role`
- **Enable Copy to destination** → vault `fincorp-backup-vault-dr`, region **eu-central-1**

Hit **Create on-demand backup**, then go to **Jobs → Backup jobs** and watch it go from Running to Completed.

**📸 Screenshot 1:** Backup job in **Running** state.  
**📸 Screenshot 2:** Job showing **Completed**.

---

### Step 12 — DR Vault: Recovery Point Landed in eu-central-1

**Switch region to eu-central-1** → AWS Backup → Backup vaults → `fincorp-backup-vault-dr` → Recovery points tab

The cross-region copy completed. That recovery point is now sitting in eu-central-1, completely independent of eu-west-1. If the primary region went dark right now, this is what we'd use to recover. Let's prove that.

**📸 Screenshot** the recovery point showing **Completed** status in eu-central-1.

---

### Step 13 — Confirm the App Is Healthy Before the Failure

**Open:** `https://<cloudfront-domain>/api/health`

Confirm it returns `db: 1`. This is your baseline — the "before" state. Screenshot it because you'll compare it to what comes next.

**📸 Screenshot** the healthy response.

---

### Step 14 — Simulate the Failure

**Run in terminal:**
```bash
PRIMARY_REGION=eu-west-1 PROJECT_NAME=fincorp bash scripts/simulate_region_failure.sh
```

It asks you to type `CONFIRM`. Do it. The script calls `aws rds delete-db-instance --skip-final-snapshot` — no recovery from the primary side. The database is gone.

**Go to:** RDS console (eu-west-1) → Databases

Watch `fincorp-primary-db` flip to **Deleting**. This is the failure event.

**📸 Screenshot** `fincorp-primary-db` in **Deleting** state.

---

### Step 15 — The App Is Down

**Open:** `https://<cloudfront-domain>/api/health`

Hit it again. The database is gone — what do you get?

```json
{ "success": false, "error": "Database unreachable" }
```

503. The failure is real. The app is actually down. Now we recover.

**📸 Screenshot** the 503 / error response.

---

### Step 16 — Start the Restore

**Get the required values:**
```bash
terraform output backup_role_arn
terraform output dr_rds_sg_id
```

**Run the restore:**
```bash
PRIMARY_REGION=eu-west-1 \
DR_REGION=eu-central-1 \
PROJECT_NAME=fincorp \
BACKUP_ROLE_ARN="<paste value>" \
DR_RDS_SG_ID="<paste value>" \
DB_NAME=fincorpdb \
bash scripts/restore_from_backup.sh
```

The script finds the latest recovery point in the DR vault and starts an RDS restore job in eu-central-1. You'll see it polling every 30 seconds:

```
[...] Status: RUNNING | Elapsed: 30s
[...] Status: RUNNING | Elapsed: 60s
```

Keep this terminal open — this is the live recovery in progress.

**📸 Screenshot** the terminal mid-poll showing the restore is running.

---

### Step 17 — Recovery Successful

Wait 15–20 minutes. When you see this — that's the moment:

```
======================================
 RECOVERY SUCCESSFUL in eu-central-1
 Elapsed: 1180s (~19 min)
======================================
Restored DB Endpoint: fincorp-restored-db.xxxxxx.eu-central-1.rds.amazonaws.com
```

Check the elapsed time. Anything under 1800 seconds is under the 30-minute RTO target. Copy the endpoint — you'll need it next.

**📸 Screenshot** the terminal with "RECOVERY SUCCESSFUL" and the elapsed time.

---

### Step 18 — RDS Is Live in eu-central-1

**Switch region to eu-central-1** → RDS → Databases

There it is — `fincorp-restored-db`, status **Available**. That database was restored from a cross-region backup into the DR VPC that Terraform pre-provisioned. The networking was already there waiting for exactly this.

**📸 Screenshot** `fincorp-restored-db` in **Available** state in eu-central-1.

---

### Step 19 — Verify the Data Made It

**Open CloudShell** (switch console to eu-central-1 first — no local MySQL client needed)

```bash
mysql -h fincorp-restored-db.xxxxxx.eu-central-1.rds.amazonaws.com \
      -u fincorp_admin \
      -p'YourStrongPassword123!' \
      fincorpdb \
      -e "SELECT 'Connection OK'; SELECT COUNT(*) AS categories FROM categories;"
```

Expected:
```
Connection OK
+------------+
| categories |
+------------+
|         13 |
+------------+
```

Connection works. Schema is intact. 13 categories — same as before the failure. The RPO is met: the data survived.

**📸 Screenshot** the CloudShell terminal with "Connection OK" and the category count.

---

### Step 20 — Point ECS at the DR Database

Update Secrets Manager with the new host, then force a new ECS deployment:

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

ECS reads credentials from Secrets Manager on task start — not baked into the image. The new task will connect to the DR database, migrations will run (they're idempotent), and it'll come up healthy.

**Go to:** ECS → `fincorp-cluster` → `fincorp-service` → Tasks

Watch the new task spin up and reach **RUNNING**.

**📸 Screenshot** the Tasks tab with the new task in **RUNNING** state.

---

### Step 21 — The App Is Back

**Open:** `https://<cloudfront-domain>/api/health`

```json
{ "success": true, "data": { "status": "healthy", "db": 1 } }
```

Then open the main app URL. The transaction list loads. The categories are there.

The primary database was deleted, the app went down, we restored from a cross-region backup, and the app is fully operational from the DR database. Check the time from Step 14 to right now — that's your demonstrated RTO.

**📸 Screenshot 1:** Health check returning `db: 1`.  
**📸 Screenshot 2:** The app UI loading normally — recovery complete.

---

## Screenshot Checklist

| # | What to capture | What it proves |
|---|---|---|
| 1 | CodePipeline — 3 green Succeeded stages | Automated end-to-end delivery |
| 2 | CodeBuild log — "Security scan passed." | Vulnerability gate ran and cleared |
| 3 | ECR — SHA tag + Immutable column | Traceable, tamper-proof artifact |
| 4 | ECR — 0 HIGH / 0 CRITICAL vulnerabilities | Image is safe to deploy |
| 5 | CodeArtifact — npm packages list | Supply chain proxy, no direct npmjs.org |
| 6 | CloudWatch — "Migrations complete." | Container self-bootstrapped the DB schema |
| 7a | App UI in browser | Frontend deployed by pipeline |
| 7b | DevTools — 200 OK on `/api/transactions` | API reachable via CloudFront proxy |
| 8 | `/api/health` → `db: 1` | Full stack: CloudFront → ECS → RDS |
| 9 | ECS task — image URI with commit SHA | Running image tied to the scanned commit |
| 10 | S3 bucket — `index.html` + `assets/` | Pipeline deployed the build output |
| 11a | Backup job — Running | Cross-region backup in progress |
| 11b | Backup job — Completed | Backup succeeded |
| 12 | DR vault in eu-central-1 — recovery point Completed | Cross-region copy ready |
| 13 | `/api/health` → `db: 1` (before failure) | Baseline — app healthy |
| 14 | RDS — `fincorp-primary-db` Deleting | Primary failure simulated |
| 15 | Browser — 503 on `/api/health` | App is actually down |
| 16 | Terminal — restore polling (Running) | Recovery in progress |
| 17 | Terminal — "RECOVERY SUCCESSFUL" + elapsed time | RTO demonstrated |
| 18 | RDS eu-central-1 — `fincorp-restored-db` Available | DR database live |
| 19 | CloudShell — "Connection OK" + 13 categories | Data integrity confirmed |
| 20 | ECS — new task RUNNING | ECS repointed to DR database |
| 21a | `/api/health` → `db: 1` (after recovery) | App fully recovered |
| 21b | App UI loading normally | DR simulation complete |
