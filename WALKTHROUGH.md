# FinCorp Secure Supply Chain & Disaster Recovery Lab — Walkthrough

> Build the pipeline. Then break the region.

A complete Terraform lab that wires a secure CI/CD pipeline — immutable ECR images, CodeArtifact proxying, vulnerability gating — to a real Node.js app backed by RDS MySQL, then lets you simulate a full us-east-1 outage and recover in under 30 minutes.

| | |
|---|---|
| Terraform | >= 1.6 |
| AWS regions | us-east-1 (primary) + us-west-2 (DR) |
| RTO target | <= 30 minutes |
| Modules | 10 |
| App stack | Node.js Express + React (Vite) + MySQL |

---

## Table of Contents

1. [Architecture](#1-architecture)
2. [Deploying the Lab](#2-deploying-the-lab)
3. [The Pipeline in Detail](#3-the-pipeline-in-detail)
4. [Disaster Recovery Simulation](#4-disaster-recovery-simulation)
5. [Security Controls](#5-security-controls)

---

## 1. Architecture

Two independent concerns wired to one app: a hardened build pipeline that guarantees every deployed image is traceable and scanned, and a cross-region backup strategy that gives you a recovery path when the primary region is gone.

```
┌──────────────────────────────────── us-east-1 (Primary) ────────────────────────────────────┐
│                                                                                              │
│  Developer                                                                                   │
│     │  git push                                                                              │
│     ▼                                                                                        │
│  GitHub ──► CodePipeline ──► CodeBuild                                                       │
│                               │                                                              │
│                    ┌──────────┴──────────┐                                                   │
│                    ▼                     ▼                                                   │
│             CodeArtifact          Docker build                                               │
│             npm-store (proxy)           │                                                    │
│             pip-store (proxy)           ▼                                                    │
│                    │            ECR (IMMUTABLE + scan-on-push)                               │
│                    └─── npm ci ──► vulnerability gate → pass / FAIL BUILD                   │
│                                                   │                                          │
│                                                   ▼                                          │
│  CloudFront ◄── S3 (React SPA)        ECS Fargate ◄── ALB (:80)                             │
│                                                   │                                          │
│                                             RDS MySQL ◄── Secrets Manager (VPC endpoint)     │
│                                                   │                                          │
│                                            AWS Backup (daily 02:00 UTC)                     │
│                                                   │  cross-region copy                       │
└───────────────────────────────────────────────────┼──────────────────────────────────────────┘
                                                    │
┌───────────────────────────────────────────────────▼──────────────────────────────────────────┐
│                                       us-west-2 (DR)                                         │
│                                                                                              │
│                                  Backup Vault (DR)                                           │
│                                  └── restore ──► RDS (recovered)                            │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Module map

| Module | What it creates |
|---|---|
| `networking` | Custom VPC, public + private subnets, IGW, 4 security groups, 4 Interface + 1 Gateway VPC endpoints (replaces NAT gateway) |
| `ecr` | ECR repo with IMMUTABLE tags and scan-on-push |
| `codeartifact` | npm-store + pip-store proxying public registries |
| `codepipeline` | CodePipeline + CodeBuild project + buildspec.yml |
| `iam` | 5 least-privilege roles scoped to specific ARNs |
| `rds_primary` | RDS MySQL 8.0 + Secrets Manager credential storage |
| `rds_dr` | VPC + subnet group pre-provisioned in us-west-2 for restore |
| `backup` | AWS Backup plan with daily cross-region copy to us-west-2 |
| `app_backend` | ECS Fargate cluster + ALB + task definition |
| `app_frontend` | S3 + CloudFront distribution with OAC |

---

## 2. Deploying the Lab

### Step 01 — Prerequisites

Verify these are installed and configured before running any Terraform commands.

```bash
terraform --version    # need >= 1.6.0
aws --version          # need >= 2.x
docker info            # Docker daemon must be running
node --version         # need >= 18
```

### Step 02 — Create the GitHub connection (manual — do this before Terraform)

CodeStar connections require a browser-based OAuth handshake with GitHub that Terraform cannot perform. **Create it first**, then hand the ARN to Terraform — this way you only apply once.

1. Open the AWS Console and type **`connections`** in the top search bar
2. Click **Connections (Developer Tools)** in the results
3. Click **Create connection** → select **GitHub** → name it `fincorp-github` → click **Connect to GitHub**
4. A GitHub OAuth popup opens — sign in and click **Authorize AWS Connector for GitHub**
5. Back in the console, click **Connect** — the status changes to **Available**
6. Click the connection name → copy the **ARN** from the top of the page

It looks like one of these (AWS rebranded the service in 2024 — both formats are valid):
```
arn:aws:codeconnections:eu-west-1:529088286633:connection/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
arn:aws:codestar-connections:us-east-1:529088286633:connection/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

> **Finding Developer Tools again:** if you lose your place, search **`Developer Tools`** in the AWS Console search bar, or navigate via **CodePipeline → Settings → Connections** in the left sidebar.

### Step 03 — Set sensitive variables

Never write credentials into `terraform.tfvars`. Export them as environment variables — Terraform picks them up automatically via the `TF_VAR_` prefix.

```bash
export TF_VAR_db_username="fincorp_admin"
export TF_VAR_db_password="YourStrongPassword123!"        # min 16 chars
export TF_VAR_github_repo="Asheryram/DOM12-Artifact-Management"   # owner/repo format
export TF_VAR_codestar_connection_arn="arn:aws:codestar-connections:us-east-1:529088286633:connection/YOUR-ID"
```

> All four variables are **required**. `terraform plan` will fail with a validation error if any is missing or empty — this is intentional to catch mistakes before any AWS resources are touched.

### Step 04 — Bootstrap infrastructure

Terraform will create ~45 AWS resources across both regions. The plan step shows you exactly what will be created before anything is touched. Apply typically takes 8–12 minutes — RDS provisioning is the longest step.

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### Step 06 — Trigger first build and seed the database

```bash
# Trigger the pipeline
git push origin main
# Watch: AWS Console → CodePipeline → fincorp-pipeline

# Seed the database after RDS is running
mysql -h $(terraform output -raw primary_db_endpoint) \
  -u $TF_VAR_db_username -p$TF_VAR_db_password \
  < app/backend/src/migrations/init.sql

# Get your app URLs
terraform output app_frontend_url
terraform output app_alb_dns
```

### Step 07 — Tear down (cleanup)

```bash
terraform destroy
```

> **Note:** The `final_snapshot_identifier` on the RDS instance means a final snapshot is taken before deletion. Delete it manually in the AWS Console if you want a clean account.

---

## 3. The Pipeline in Detail

Every push to `main` triggers three pipeline stages. The build stage does more than compile — it gates deployment on image security.

### Stage 1 — Source (GitHub via CodeStar)

CodePipeline watches your repo's `main` branch. On push, it copies the source into an encrypted, versioned S3 artifact bucket and triggers the next stage.

### Stage 2 — Build & Scan (CodeBuild)

Four things happen in sequence. If any step fails, the pipeline halts and the image is never deployed.

**1 — Auth**

CodeBuild fetches a short-lived CodeArtifact token and rewrites `.npmrc` to point at the internal `npm-store` proxy. `npm ci` runs against CodeArtifact, not npmjs.org directly. This closes the dependency confusion attack vector.

**2 — Build**

```bash
IMAGE_TAG=${CODEBUILD_RESOLVED_SOURCE_VERSION:0:8}
docker build -t $ECR_REPO_URL:$IMAGE_TAG ./app/backend
docker push $ECR_REPO_URL:$IMAGE_TAG
```

The image is tagged with the first 8 characters of the git commit SHA — never `latest`. Because ECR is `IMMUTABLE`, a tag can never be silently overwritten by a later push.

**3 — Scan**

ECR's scan-on-push runs Basic scanning (Amazon Inspector) automatically on every pushed image. The buildspec waits 60 seconds, then queries the findings.

**4 — Gate**

```bash
if [ "$HIGH" != "None" ] && [ "$HIGH" != "0" ]; then
  echo "BUILD FAILED: High vulnerabilities detected."
  exit 1
fi
if [ "$CRITICAL" != "None" ] && [ "$CRITICAL" != "0" ]; then
  echo "BUILD FAILED: Critical vulnerabilities detected."
  exit 1
fi
```

If HIGH or CRITICAL vulnerabilities are found, the build exits 1. CodePipeline marks the stage **Failed** — nothing reaches ECS. The previous clean image keeps running.

### Stage 3 — Deploy (ECS rolling update)

CodeBuild writes `imagedefinitions.json` with the commit-SHA-tagged image URI. The ECS deploy action uses this to register a new task definition revision and roll it out, replacing the previous task with zero-downtime rotation.

### Demo: trigger a deliberate gate failure

Replace the first line of `app/backend/Dockerfile` with `FROM node:14-alpine` and push. Node 14 is EOL with known CVEs — the build will fail at the scan gate, and ECS will keep running the previous clean image.

---

## 4. Disaster Recovery Simulation

The lab's centrepiece. You delete the primary RDS instance to simulate a region failure, then restore from the cross-region AWS Backup vault in us-west-2.

> **Warning:** `simulate_region_failure.sh` permanently deletes the primary database. It requires you to type `CONFIRM`. In a real disaster you would not run this script — the region would already be unavailable. In the lab, this is how you force the condition to practise the runbook.

### Step D1 — Simulate the failure

```bash
PROJECT_NAME=fincorp ./scripts/simulate_region_failure.sh

# You will be prompted:
# WARNING: This will DELETE the primary database.
# Type 'CONFIRM' to proceed: _
```

The script calls `aws rds delete-db-instance` then waits for the instance to fully disappear before returning.

### Step D2 — Restore from cross-region backup

```bash
PROJECT_NAME=fincorp \
BACKUP_ROLE_ARN=$(terraform output -raw backup_role_arn) \
DR_RDS_SG_ID=<sg-id from rds_dr module output> \
DB_NAME=fincorpdb \
./scripts/restore_from_backup.sh
```

The script:
1. Finds the latest recovery point in the `fincorp-backup-vault-dr` vault in us-west-2
2. Starts an AWS Backup restore job targeting the pre-provisioned `rds_dr` subnet group
3. Polls every 30 seconds and reports elapsed time
4. Prints the restored endpoint when complete

### Step D3 — Verify data integrity

```bash
DR_DB_ENDPOINT=<address from restore script output> \
DB_USERNAME=$TF_VAR_db_username \
DB_PASS=$TF_VAR_db_password \
./scripts/verify_dr.sh

# Expected output:
# Connection OK
# transaction_count: N
# category_count: 13
```

### Step D4 — Cut over the app

Update Secrets Manager with the restored DB endpoint, then force a new ECS deployment to pick up the change:

```bash
aws ecs update-service \
  --cluster fincorp-cluster \
  --service fincorp-backend-service \
  --force-new-deployment \
  --region us-west-2
```

### Expected timeline

| Time | What's happening |
|---|---|
| 0 – 5 min | Detect & decide. CloudWatch alarms fire: RDS connections drop to 0, ALB healthy hosts = 0. Declare DR. |
| 5 – 6 min | Start restore job. Script locates latest recovery point in us-west-2 vault and kicks off AWS Backup restore. |
| 6 – 25 min | RDS restoring. AWS provisions a new MySQL instance from the backup snapshot in us-west-2. |
| 25 – 28 min | Verify & cut over. Run verify_dr.sh, confirm row counts, update ECS DB_HOST, force new deployment. |
| ~30 min | **App is serving traffic from the recovered database in us-west-2. RTO target met.** |

---

## 5. Security Controls

Every control here was a deliberate architectural decision. The notes explain the threat each one addresses.

### IMMUTABLE image tags

`ECR image_tag_mutability = IMMUTABLE` — once `fincorp-app:a3f1b2c4` is pushed, that SHA always refers to the same layers. Rollbacks are trustworthy. Prevents tag-hijacking where a malicious image is pushed under an existing tag.

### Vulnerability gate

`buildspec.yml` exits 1 on HIGH/CRITICAL findings. The check is in the build script, not a CloudWatch alarm — it directly blocks deployment rather than alerting after the fact.

### Secrets Manager injection

DB credentials never touch environment variables at the Terraform level. ECS reads them from Secrets Manager at task start via the `secrets` block in the task definition. They appear in the container's process environment but are not in the task definition JSON, CloudWatch logs, or S3 artifacts.

### CodeArtifact proxy

`npm ci` runs against the internal `npm-store`, not npmjs.org directly. This closes the dependency confusion attack vector: an attacker cannot intercept a package name resolution by publishing a higher-versioned package to the public registry under your internal package names.

### KMS encryption

RDS, ECR, the CodeArtifact domain, and the S3 pipeline bucket all use KMS-managed keys. Separate keys per service limit the blast radius of a key compromise.

### Private subnets

RDS and ECS tasks live in private subnets with no public IPs. Inbound to RDS is restricted to the ECS security group on port 3306 only. The only public entry point is the ALB.

### Least-privilege IAM

Five separate IAM roles — CodeBuild, CodePipeline, ECS execution, ECS task, Backup — each scoped to specific ARNs. CodeBuild can push to its ECR repo and read from its CodeArtifact repos; it cannot touch RDS or ECS.

---

## API Reference

The backend exposes the following endpoints. All responses use `{ "success": true, "data": ... }` or `{ "success": false, "error": "..." }`.

| Method | Path | Description |
|---|---|---|
| GET | `/api/health` | Health check — returns DB connectivity status |
| GET | `/api/summary` | Total income, expense, net balance (all-time + current month + 6-month monthly breakdown) |
| GET | `/api/transactions` | List transactions. Query params: `type=income\|expense`, `limit`, `offset` |
| POST | `/api/transactions` | Create transaction: `{ type, amount, description, category_id, transaction_date }` |
| DELETE | `/api/transactions/:id` | Delete a transaction |
| GET | `/api/categories` | List categories. Query param: `type=income\|expense` |
| POST | `/api/categories` | Create category: `{ name, type, color, icon }` |
| DELETE | `/api/categories/:id` | Delete category (fails if transactions reference it) |
