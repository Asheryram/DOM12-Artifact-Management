# FinCorp Secure Supply Chain & Disaster Recovery Lab
## Complete Terraform Implementation Prompt

---

## CONTEXT & GOAL

You are building a production-grade AWS infrastructure simulation for **FinCorp**, a fictional financial company. The simulation demonstrates:

1. A **secure, auditable CI/CD pipeline** with immutable artifacts via AWS CodeArtifact + ECR
2. A **Cross-Region Disaster Recovery** strategy for an RDS database (us-east-1 → us-west-2, RTO ≤ 30 min)
3. A **real application** (Expense & Income Tracker) that uses the RDS database, making the DR simulation meaningful

All infrastructure must be written in **Terraform (HCL)**, organized into logical modules, and fully documented.

---

## PART 1 — TERRAFORM PROJECT STRUCTURE

Generate the following file and folder layout. Do not collapse modules — each module must be a separate folder:

```
fincorp-lab/
├── main.tf                  # Root: calls all modules
├── variables.tf
├── outputs.tf
├── terraform.tfvars
├── versions.tf              # Required providers + version locks
│
├── modules/
│   ├── networking/          # VPC, subnets, SGs, IGW, NAT
│   ├── ecr/                 # ECR repo with scan-on-push + tag immutability
│   ├── codeartifact/        # CodeArtifact domain + npm + pip repos
│   ├── codepipeline/        # CodePipeline + CodeBuild (build, scan, push)
│   ├── iam/                 # All IAM roles and policies
│   ├── rds_primary/         # RDS MySQL in us-east-1
│   ├── rds_dr/              # RDS restore target config in us-west-2
│   ├── backup/              # AWS Backup plan + cross-region copy rule
│   ├── app_backend/         # ECS Fargate task + ALB for Node.js/Python API
│   └── app_frontend/        # S3 + CloudFront for React frontend
│
├── app/
│   ├── backend/             # Node.js (Express) REST API source
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   ├── src/
│   │   │   ├── index.js
│   │   │   ├── db.js
│   │   │   ├── routes/
│   │   │   │   ├── transactions.js
│   │   │   │   ├── categories.js
│   │   │   │   └── summary.js
│   │   │   └── migrations/
│   │   │       └── init.sql
│   │   └── .npmrc           # Points to CodeArtifact upstream
│   │
│   └── frontend/            # React SPA source
│       ├── Dockerfile
│       ├── package.json
│       └── src/
│           ├── App.jsx
│           ├── pages/
│           │   ├── Dashboard.jsx
│           │   ├── Transactions.jsx
│           │   └── Categories.jsx
│           └── components/
│               ├── IncomeForm.jsx
│               ├── ExpenseForm.jsx
│               └── SummaryCard.jsx
│
├── scripts/
│   ├── simulate_region_failure.sh   # Deletes primary RDS; triggers DR
│   ├── restore_from_backup.sh       # Restores DB in us-west-2 from backup
│   └── verify_dr.sh                 # Checks restored DB connectivity
│
└── docs/
    ├── architecture.md
    ├── dr_runbook.md
    └── pipeline_guide.md
```

---

## PART 2 — VERSIONS & PROVIDERS

**File: `versions.tf`**

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Uncomment for remote state (recommended for real use)
  # backend "s3" {
  #   bucket         = "fincorp-tfstate"
  #   key            = "global/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "fincorp-tfstate-lock"
  # }
}

provider "aws" {
  alias  = "primary"
  region = var.primary_region   # us-east-1
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region        # us-west-2
}
```

---

## PART 3 — ROOT VARIABLES & TFVARS

**File: `variables.tf`** — declare all variables with descriptions and types.

Required variables (generate with full `variable` blocks, descriptions, types, and where relevant, validation blocks):

| Variable | Type | Default | Description |
|---|---|---|---|
| `project_name` | string | `"fincorp"` | Prefix for all resource names |
| `primary_region` | string | `"us-east-1"` | Primary AWS region |
| `dr_region` | string | `"us-west-2"` | Disaster recovery region |
| `db_name` | string | `"fincorpdb"` | RDS database name |
| `db_username` | string | — | RDS master username (sensitive) |
| `db_password` | string | — | RDS master password (sensitive, min 16 chars) |
| `ecr_repo_name` | string | `"fincorp-app"` | ECR repository name |
| `github_repo` | string | — | GitHub repo in format `owner/repo` |
| `github_branch` | string | `"main"` | Branch to trigger pipeline |
| `app_image_tag` | string | `"latest"` | Docker image tag |
| `environment` | string | `"lab"` | Environment label |
| `backup_retention_days` | number | `35` | Days to retain backups |
| `rds_instance_class` | string | `"db.t3.micro"` | RDS instance size |
| `ecs_cpu` | number | `256` | Fargate task CPU units |
| `ecs_memory` | number | `512` | Fargate task memory MiB |

Add a `validation` block to `db_password` ensuring length ≥ 16.

**File: `terraform.tfvars`** — provide non-sensitive defaults; leave sensitive vars as empty strings with a comment instructing use of `TF_VAR_` env vars or AWS Secrets Manager.

---

## PART 4 — NETWORKING MODULE

**Module: `modules/networking/`**

Generate `main.tf`, `variables.tf`, `outputs.tf`.

Resources to create (all tagged with `project_name` and `environment`):

- `aws_vpc` — CIDR `10.0.0.0/16`, DNS support enabled
- `aws_internet_gateway` — attached to VPC
- Two **public subnets** in different AZs (e.g., `10.0.1.0/24`, `10.0.2.0/24`)
- Two **private subnets** in different AZs (e.g., `10.0.11.0/24`, `10.0.12.0/24`)
- `aws_eip` + `aws_nat_gateway` — NAT in public subnet for private egress
- `aws_route_table` (public) — routes `0.0.0.0/0` to IGW; associated with public subnets
- `aws_route_table` (private) — routes `0.0.0.0/0` to NAT; associated with private subnets
- **Security Group: `rds_sg`** — ingress 3306 from ECS SG only; egress all
- **Security Group: `ecs_sg`** — ingress 8080 from ALB SG; egress all (to reach RDS + internet for CodeArtifact)
- **Security Group: `alb_sg`** — ingress 80 + 443 from `0.0.0.0/0`; egress to ECS SG

Outputs: `vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `rds_sg_id`, `ecs_sg_id`, `alb_sg_id`

---

## PART 5 — ECR MODULE

**Module: `modules/ecr/`**

```hcl
resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-${var.ecr_repo_name}"
  image_tag_mutability = "IMMUTABLE"   # Tag immutability ON

  image_scanning_configuration {
    scan_on_push = true   # Image scanning ON
  }

  encryption_configuration {
    encryption_type = "KMS"
  }

  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "cleanup" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
```

Also generate an `aws_ecr_repository_policy` that allows only the CodeBuild IAM role to push images.

Output: `repository_url`, `repository_arn`

---

## PART 6 — CODEARTIFACT MODULE

**Module: `modules/codeartifact/`**

Create:

1. `aws_codeartifact_domain` — name `fincorp-artifacts`, encrypted with KMS
2. `aws_codeartifact_repository` named `npm-store`:
   - `external_connections` = `"public:npmjs"` (upstream proxy for npmjs.org)
3. `aws_codeartifact_repository` named `pip-store`:
   - `external_connections` = `"public:pypi"` (upstream proxy for PyPI)
4. `aws_codeartifact_repository_permissions_policy` — grants CodeBuild role `codeartifact:GetAuthorizationToken`, `codeartifact:ReadFromRepository`, `codeartifact:GetRepositoryEndpoint`

Add a **Terraform `local-exec` provisioner** (or document as a manual step) that configures `.npmrc` in the app to point to the CodeArtifact npm endpoint using the AWS CLI token fetch command:

```bash
aws codeartifact login --tool npm \
  --domain fincorp-artifacts \
  --domain-owner <ACCOUNT_ID> \
  --repository npm-store \
  --region us-east-1
```

Output: `domain_name`, `npm_repository_endpoint`, `pip_repository_endpoint`

---

## PART 7 — IAM MODULE

**Module: `modules/iam/`**

Create the following IAM roles with least-privilege inline + managed policies:

### 7.1 CodeBuild Role (`fincorp-codebuild-role`)
Trust policy: `codebuild.amazonaws.com`

Permissions:
- `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`, `ecr:DescribeImages`, `ecr:DescribeImageScanFindings` — on the ECR repo ARN
- `codeartifact:GetAuthorizationToken`, `codeartifact:ReadFromRepository`, `codeartifact:GetRepositoryEndpoint` — on CodeArtifact domain + repos
- `sts:GetServiceBearerToken` — for CodeArtifact token
- `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents` — for CloudWatch
- `s3:GetObject`, `s3:PutObject` — on pipeline artifact S3 bucket

### 7.2 CodePipeline Role (`fincorp-codepipeline-role`)
Trust: `codepipeline.amazonaws.com`
Permissions: `codebuild:*`, `s3:*` (on pipeline bucket), `codestar-connections:UseConnection`

### 7.3 ECS Task Execution Role (`fincorp-ecs-execution-role`)
Trust: `ecs-tasks.amazonaws.com`
Managed policy: `AmazonECSTaskExecutionRolePolicy`
Plus: `secretsmanager:GetSecretValue` for DB credentials secret

### 7.4 ECS Task Role (`fincorp-ecs-task-role`)
Trust: `ecs-tasks.amazonaws.com`
Permissions: `rds-db:connect`

### 7.5 AWS Backup Role (`fincorp-backup-role`)
Trust: `backup.amazonaws.com`
Managed policies: `AWSBackupServiceRolePolicyForBackup`, `AWSBackupServiceRolePolicyForRestores`

Output all role ARNs.

---

## PART 8 — CODEPIPELINE MODULE

**Module: `modules/codepipeline/`**

### 8.1 S3 Artifact Bucket
```hcl
resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket        = "${var.project_name}-pipeline-artifacts-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" }
  }
}
```

### 8.2 CodeBuild Project
```hcl
resource "aws_codebuild_project" "build_and_scan" {
  name          = "${var.project_name}-build"
  service_role  = var.codebuild_role_arn
  build_timeout = 20

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true   # Required for Docker builds

    environment_variable { name = "ECR_REPO_URL"    value = var.ecr_repository_url }
    environment_variable { name = "IMAGE_TAG"        value = var.app_image_tag }
    environment_variable { name = "AWS_REGION"       value = var.primary_region }
    environment_variable { name = "CA_DOMAIN"        value = var.codeartifact_domain }
    environment_variable { name = "CA_DOMAIN_OWNER"  value = data.aws_caller_identity.current.account_id }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/buildspec.yml")
  }

  logs_config {
    cloudwatch_logs { group_name = "/aws/codebuild/${var.project_name}-build" }
  }
}
```

### 8.3 `buildspec.yml` (inline in module)

Generate a complete `buildspec.yml` that:

1. **Pre-build phase:**
   - Fetches CodeArtifact auth token and configures `.npmrc`
   - Logs into ECR via `aws ecr get-login-password`

2. **Build phase:**
   - Runs `npm ci` (packages fetched via CodeArtifact, not npmjs.org directly)
   - Runs `docker build -t $ECR_REPO_URL:$IMAGE_TAG .`
   - Pushes the image: `docker push $ECR_REPO_URL:$IMAGE_TAG`

3. **Post-build phase (CRITICAL — pipeline fails here if vulnerabilities found):**
   ```yaml
   post_build:
     commands:
       - echo "Waiting for ECR scan results..."
       - sleep 60
       - |
         SCAN_STATUS=$(aws ecr describe-image-scan-findings \
           --repository-name $ECR_REPO_NAME \
           --image-id imageTag=$IMAGE_TAG \
           --query 'imageScanStatus.status' \
           --output text)
         echo "Scan status: $SCAN_STATUS"
       - |
         HIGH=$(aws ecr describe-image-scan-findings \
           --repository-name $ECR_REPO_NAME \
           --image-id imageTag=$IMAGE_TAG \
           --query 'imageScanFindings.findingSeverityCounts.HIGH' \
           --output text)
         CRITICAL=$(aws ecr describe-image-scan-findings \
           --repository-name $ECR_REPO_NAME \
           --image-id imageTag=$IMAGE_TAG \
           --query 'imageScanFindings.findingSeverityCounts.CRITICAL' \
           --output text)
         echo "HIGH: $HIGH | CRITICAL: $CRITICAL"
         if [ "$HIGH" != "None" ] || [ "$CRITICAL" != "None" ]; then
           echo "BUILD FAILED: High or Critical vulnerabilities detected in Docker image."
           exit 1
         fi
       - echo "Security scan passed. Image is clean."
   ```

### 8.4 CodePipeline

```hcl
resource "aws_codepipeline" "fincorp" {
  name     = "${var.project_name}-pipeline"
  role_arn = var.codepipeline_role_arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "GitHub_Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        ConnectionArn    = var.codestar_connection_arn
        FullRepositoryId = var.github_repo
        BranchName       = var.github_branch
      }
    }
  }

  stage {
    name = "Build_and_Scan"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      configuration = {
        ProjectName = aws_codebuild_project.build_and_scan.name
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "Deploy_to_ECS"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      version         = "1"
      input_artifacts = ["build_output"]
      configuration = {
        ClusterName = var.ecs_cluster_name
        ServiceName = var.ecs_service_name
        FileName    = "imagedefinitions.json"
      }
    }
  }
}
```

---

## PART 9 — RDS PRIMARY MODULE (us-east-1)

**Module: `modules/rds_primary/`**

```hcl
resource "aws_db_subnet_group" "primary" {
  name       = "${var.project_name}-primary-subnet-group"
  subnet_ids = var.private_subnet_ids
}

resource "aws_db_instance" "primary" {
  identifier              = "${var.project_name}-primary-db"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = var.rds_instance_class
  allocated_storage       = 20
  storage_type            = "gp3"
  storage_encrypted       = true
  db_name                 = var.db_name
  username                = var.db_username
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.primary.name
  vpc_security_group_ids  = [var.rds_sg_id]
  multi_az                = false          # Single-AZ for lab (cost-saving)
  publicly_accessible     = false
  skip_final_snapshot     = false
  final_snapshot_identifier = "${var.project_name}-final-snapshot-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  deletion_protection     = false          # Set true in production
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-primary-rds"
    DR   = "source"
  })
}
```

Store DB credentials in **AWS Secrets Manager**:

```hcl
resource "aws_secretsmanager_secret" "db_credentials" {
  name = "${var.project_name}/db/credentials"
  recovery_window_in_days = 0   # Immediate deletion in lab
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = aws_db_instance.primary.address
    port     = 5432
    dbname   = var.db_name
  })
}
```

Output: `db_instance_id`, `db_endpoint`, `db_arn`, `db_identifier`, `secret_arn`

---

## PART 10 — AWS BACKUP MODULE

**Module: `modules/backup/`**

```hcl
resource "aws_backup_vault" "primary" {
  provider = aws.primary
  name     = "${var.project_name}-backup-vault-primary"
  tags     = local.common_tags
}

resource "aws_backup_vault" "dr" {
  provider = aws.dr
  name     = "${var.project_name}-backup-vault-dr"
  tags     = local.common_tags
}

resource "aws_backup_plan" "daily_with_crossregion" {
  name = "${var.project_name}-daily-backup"

  rule {
    rule_name         = "daily-backup-rule"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 2 * * ? *)"   # 2 AM UTC daily
    
    lifecycle {
      delete_after = var.backup_retention_days
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn   # Cross-region copy to us-west-2

      lifecycle {
        delete_after = var.backup_retention_days
      }
    }
  }

  tags = local.common_tags
}

resource "aws_backup_selection" "rds_primary" {
  name         = "${var.project_name}-rds-selection"
  plan_id      = aws_backup_plan.daily_with_crossregion.id
  iam_role_arn = var.backup_role_arn

  resources = [var.rds_instance_arn]
}
```

Output: `backup_plan_id`, `dr_vault_arn`, `primary_vault_arn`

---

## PART 11 — APP BACKEND MODULE (ECS Fargate)

**Module: `modules/app_backend/`**

Create:
- `aws_ecs_cluster` — named `${var.project_name}-cluster`
- `aws_cloudwatch_log_group` — `/ecs/${var.project_name}-backend`
- `aws_ecs_task_definition` — Fargate launch type, the container reads DB credentials from Secrets Manager via `secrets` block
- `aws_alb` + `aws_alb_target_group` + `aws_alb_listener` — HTTP on port 80, forwarding to ECS on port 8080
- `aws_ecs_service` — desired count 1, rolling deployment, registers with ALB target group

**Container environment variables** (injected from Secrets Manager + Terraform outputs):
```
DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASS, NODE_ENV=production
```

Output: `alb_dns_name`, `ecs_cluster_name`, `ecs_service_name`

---

## PART 12 — APP FRONTEND MODULE (S3 + CloudFront)

**Module: `modules/app_frontend/`**

- `aws_s3_bucket` — private, versioned, SSE-S3 encrypted
- `aws_s3_bucket_policy` — allows only CloudFront OAC
- `aws_cloudfront_origin_access_control`
- `aws_cloudfront_distribution` — origin = S3, default root object = `index.html`, error response 404 → `/index.html` (SPA routing)
- `aws_s3_object` for a placeholder `index.html` (real app uploaded by CI/CD)

Output: `cloudfront_domain`, `s3_bucket_name`, `distribution_id`

---

## PART 13 — APPLICATION CODE

### 13.1 Database Schema (`app/backend/src/migrations/init.sql`)

```sql
CREATE DATABASE IF NOT EXISTS fincorpdb;
USE fincorpdb;

-- Income/Expense Categories
CREATE TABLE IF NOT EXISTS categories (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  name        VARCHAR(100) NOT NULL,
  type        ENUM('income', 'expense') NOT NULL,
  color       VARCHAR(7) DEFAULT '#6366f1',
  icon        VARCHAR(50) DEFAULT 'circle',
  created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_category_name_type (name, type)
);

-- Transactions (both income and expense)
CREATE TABLE IF NOT EXISTS transactions (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  type          ENUM('income', 'expense') NOT NULL,
  amount        DECIMAL(12, 2) NOT NULL,
  description   VARCHAR(255),
  category_id   INT NOT NULL,
  transaction_date DATE NOT NULL DEFAULT (CURRENT_DATE),
  created_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (category_id) REFERENCES categories(id)
);

-- Seed default categories
INSERT IGNORE INTO categories (name, type, color) VALUES
  ('Salary',       'income',  '#22c55e'),
  ('Freelance',    'income',  '#3b82f6'),
  ('Investment',   'income',  '#a855f7'),
  ('Gift',         'income',  '#f59e0b'),
  ('Other Income', 'income',  '#6366f1'),
  ('Rent',         'expense', '#ef4444'),
  ('Food',         'expense', '#f97316'),
  ('Transport',    'expense', '#eab308'),
  ('Utilities',    'expense', '#06b6d4'),
  ('Healthcare',   'expense', '#ec4899'),
  ('Shopping',     'expense', '#8b5cf6'),
  ('Entertainment','expense', '#64748b'),
  ('Other Expense','expense', '#374151');
```

### 13.2 Backend API (`app/backend/src/index.js`)

Generate a **Node.js Express** application with:

**Endpoints:**

| Method | Path | Description |
|---|---|---|
| GET | `/api/health` | Health check (returns DB connectivity status) |
| GET | `/api/summary` | Total income, total expense, net balance for current month and all-time |
| GET | `/api/transactions` | List transactions (optional `?type=income\|expense&limit=50&offset=0`) |
| POST | `/api/transactions` | Create a transaction `{ type, amount, description, category_id, transaction_date }` |
| DELETE | `/api/transactions/:id` | Delete a transaction |
| GET | `/api/categories` | List all categories (optionally `?type=income\|expense`) |
| POST | `/api/categories` | Create a custom category `{ name, type, color, icon }` |
| DELETE | `/api/categories/:id` | Delete a category (only if no transactions reference it) |

All responses use `{ success: true, data: ... }` or `{ success: false, error: "..." }`.

Use `mysql2/promise` for database connections with connection pooling.
Read DB config from environment variables (set via ECS secrets injection from Secrets Manager).
Include proper error handling and HTTP status codes.
Add CORS middleware allowing the CloudFront domain.
Add `helmet` for security headers.

### 13.3 Frontend (`app/frontend/src/`)

Generate a **React** SPA (Vite build) with the following pages and design:

**Design Language:**
- Dark financial theme: background `#0f1117`, card surface `#1a1d27`, accent `#6366f1` (indigo)
- Font: Inter (loaded from Google Fonts via CDN)
- Clean sidebar navigation, responsive

**Pages:**

#### Dashboard (`/`)
- **4 summary cards** across the top:
  - Total Income (green, ↑ icon)
  - Total Expenses (red, ↓ icon)  
  - Net Balance (indigo, = icon, shows positive/negative color)
  - Transactions This Month (blue, # count)
- **Bar chart** — Monthly income vs expense (last 6 months) using Recharts
- **Recent Transactions list** — last 10, shows category color dot, description, amount, date

#### Transactions (`/transactions`)
- **Add Transaction form** (top or side panel):
  - Toggle: Income / Expense
  - Amount input (number, 2 decimal)
  - Description text input
  - Category dropdown (filtered by selected type)
  - Date picker
  - Submit button
- **Transactions table** below:
  - Columns: Date | Type (badge) | Category | Description | Amount
  - Color-coded amounts (green for income, red for expense)
  - Delete button per row
  - Filter bar: All / Income / Expense

#### Categories (`/categories`)
- **Two columns**: Income Categories | Expense Categories
- Each category shown as a card with its color swatch, name, and transaction count
- **Add Category form** at top:
  - Name input
  - Type toggle (Income/Expense)
  - Color picker (simple palette of 10 colors)
  - Submit button
- Delete button on category card (disabled/greyed if category has transactions)

**API integration:** Use `axios` with a base URL read from `VITE_API_URL` env var (set to ALB DNS during build).

---

## PART 14 — DISASTER RECOVERY SCRIPTS

### 14.1 `scripts/simulate_region_failure.sh`

```bash
#!/bin/bash
# FinCorp DR Lab - Simulate Region Failure
# This script deletes the primary RDS instance to simulate an us-east-1 outage.

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
```

### 14.2 `scripts/restore_from_backup.sh`

```bash
#!/bin/bash
# FinCorp DR Lab - Restore from Cross-Region Backup
# Restores the latest recovery point from the DR vault in us-west-2

set -e

PROJECT_NAME="${PROJECT_NAME:-fincorp}"
DR_VAULT_NAME="${PROJECT_NAME}-backup-vault-dr"
DR_REGION="us-west-2"
RESTORE_DB_IDENTIFIER="${PROJECT_NAME}-restored-db"
DB_SUBNET_GROUP="${PROJECT_NAME}-dr-subnet-group"   # Must pre-exist (created by rds_dr module)
RDS_SG_ID="${DR_RDS_SG_ID}"                         # Set via env var from Terraform output
BACKUP_ROLE_ARN="${BACKUP_ROLE_ARN}"                 # Set via env var from Terraform output
DB_NAME="${DB_NAME:-fincorpdb}"

echo "======================================"
echo " FinCorp DR Recovery: us-west-2"
echo "======================================"

# 1. Find the latest recovery point
echo "[$(date)] Finding latest recovery point in $DR_VAULT_NAME..."

RECOVERY_POINT_ARN=$(aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$DR_VAULT_NAME" \
  --region "$DR_REGION" \
  --query 'RecoveryPoints | sort_by(@, &CreationDate) | [-1].RecoveryPointArn' \
  --output text)

echo "[$(date)] Latest recovery point: $RECOVERY_POINT_ARN"

# 2. Get the resource ARN from the recovery point
RESOURCE_ARN=$(aws backup describe-recovery-point \
  --backup-vault-name "$DR_VAULT_NAME" \
  --recovery-point-arn "$RECOVERY_POINT_ARN" \
  --region "$DR_REGION" \
  --query 'ResourceArn' \
  --output text)

echo "[$(date)] Original resource: $RESOURCE_ARN"

# 3. Start restore job
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

# 4. Poll until complete
echo "[$(date)] Waiting for restore to complete (this may take 10-25 minutes)..."
START_TIME=$(date +%s)

while true; do
  STATUS=$(aws backup describe-restore-job \
    --restore-job-id "$RESTORE_JOB_ID" \
    --region "$DR_REGION" \
    --query 'Status' \
    --output text)

  ELAPSED=$(( $(date +%s) - START_TIME ))
  MINUTES=$(( ELAPSED / 60 ))
  SECONDS=$(( ELAPSED % 60 ))

  echo "[$(date)] Status: $STATUS | Elapsed: ${MINUTES}m ${SECONDS}s"

  if [ "$STATUS" = "COMPLETED" ]; then
    echo ""
    echo "======================================"
    echo " RECOVERY SUCCESSFUL in $DR_REGION"
    echo " Elapsed time: ${MINUTES}m ${SECONDS}s"
    echo "======================================"
    break
  elif [ "$STATUS" = "FAILED" ] || [ "$STATUS" = "ABORTED" ]; then
    echo "RESTORE FAILED with status: $STATUS"
    exit 1
  fi

  sleep 30
done

# 5. Get restored DB endpoint
ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$RESTORE_DB_IDENTIFIER" \
  --region "$DR_REGION" \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

echo ""
echo "Restored DB Endpoint: $ENDPOINT"
echo "Update your ECS service environment variable DB_HOST to: $ENDPOINT"
echo "Then run: ./scripts/verify_dr.sh"
```

### 14.3 `scripts/verify_dr.sh`

```bash
#!/bin/bash
# Verify DR database connectivity and data integrity

DR_ENDPOINT="${DR_DB_ENDPOINT}"
DB_USER="${DB_USERNAME}"
DB_NAME="${DB_NAME:-fincorpdb}"

echo "Verifying connection to DR database at $DR_ENDPOINT..."

mysql -h "$DR_ENDPOINT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
SELECT 'Connection OK' AS status;
SELECT COUNT(*) AS transaction_count FROM transactions;
SELECT COUNT(*) AS category_count FROM categories;
SELECT type, SUM(amount) AS total FROM transactions GROUP BY type;
EOF

echo "DR verification complete."
```

---

## PART 15 — ROOT MAIN.TF

**File: `main.tf`**

Wire all modules together. Pass outputs from one module as inputs to dependent modules. Use `providers` meta-argument where modules target a specific region (e.g., `rds_dr` and DR vault use the `aws.dr` provider alias).

```hcl
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Lab         = "FinCorp-SecureSupplyChain-DR"
  }
}

module "networking" {
  source       = "./modules/networking"
  providers    = { aws = aws.primary }
  project_name = var.project_name
  environment  = var.environment
}

module "iam" {
  source              = "./modules/iam"
  providers           = { aws = aws.primary }
  project_name        = var.project_name
  ecr_repository_arn  = module.ecr.repository_arn
  codeartifact_domain = module.codeartifact.domain_name
  rds_instance_arn    = module.rds_primary.db_arn
}

module "ecr" {
  source        = "./modules/ecr"
  providers     = { aws = aws.primary }
  project_name  = var.project_name
  ecr_repo_name = var.ecr_repo_name
  environment   = var.environment
}

module "codeartifact" {
  source        = "./modules/codeartifact"
  providers     = { aws = aws.primary }
  project_name  = var.project_name
  environment   = var.environment
}

module "codepipeline" {
  source                = "./modules/codepipeline"
  providers             = { aws = aws.primary }
  project_name          = var.project_name
  ecr_repository_url    = module.ecr.repository_url
  ecr_repo_name         = var.ecr_repo_name
  codebuild_role_arn    = module.iam.codebuild_role_arn
  codepipeline_role_arn = module.iam.codepipeline_role_arn
  codeartifact_domain   = module.codeartifact.domain_name
  github_repo           = var.github_repo
  github_branch         = var.github_branch
  ecs_cluster_name      = module.app_backend.ecs_cluster_name
  ecs_service_name      = module.app_backend.ecs_service_name
}

module "rds_primary" {
  source             = "./modules/rds_primary"
  providers          = { aws = aws.primary }
  project_name       = var.project_name
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  rds_instance_class = var.rds_instance_class
  private_subnet_ids = module.networking.private_subnet_ids
  rds_sg_id          = module.networking.rds_sg_id
}

module "backup" {
  source           = "./modules/backup"
  providers        = { aws.primary = aws.primary, aws.dr = aws.dr }
  project_name     = var.project_name
  rds_instance_arn = module.rds_primary.db_arn
  backup_role_arn  = module.iam.backup_role_arn
  retention_days   = var.backup_retention_days
}

module "app_backend" {
  source                = "./modules/app_backend"
  providers             = { aws = aws.primary }
  project_name          = var.project_name
  ecr_image_url         = "${module.ecr.repository_url}:${var.app_image_tag}"
  db_secret_arn         = module.rds_primary.secret_arn
  ecs_task_exec_role_arn= module.iam.ecs_execution_role_arn
  ecs_task_role_arn     = module.iam.ecs_task_role_arn
  private_subnet_ids    = module.networking.private_subnet_ids
  public_subnet_ids     = module.networking.public_subnet_ids
  ecs_sg_id             = module.networking.ecs_sg_id
  alb_sg_id             = module.networking.alb_sg_id
  vpc_id                = module.networking.vpc_id
  ecs_cpu               = var.ecs_cpu
  ecs_memory            = var.ecs_memory
}

module "app_frontend" {
  source       = "./modules/app_frontend"
  providers    = { aws = aws.primary }
  project_name = var.project_name
  api_endpoint = "http://${module.app_backend.alb_dns_name}"
}
```

---

## PART 16 — OUTPUTS

**File: `outputs.tf`**

```hcl
output "ecr_repository_url"      { value = module.ecr.repository_url }
output "codeartifact_npm_endpoint"{ value = module.codeartifact.npm_repository_endpoint }
output "codepipeline_name"        { value = module.codepipeline.pipeline_name }
output "primary_db_endpoint"      { value = module.rds_primary.db_endpoint }
output "primary_db_identifier"    { value = module.rds_primary.db_identifier }
output "backup_plan_id"           { value = module.backup.backup_plan_id }
output "dr_vault_arn"             { value = module.backup.dr_vault_arn }
output "app_alb_dns"              { value = module.app_backend.alb_dns_name }
output "app_frontend_url"         { value = "https://${module.app_frontend.cloudfront_domain}" }
output "app_api_url"              { value = "http://${module.app_backend.alb_dns_name}" }

output "dr_simulation_commands" {
  value = <<-EOT
    # ---- DR SIMULATION COMMANDS ----
    # Step 1: Simulate failure
    PROJECT_NAME=${var.project_name} ./scripts/simulate_region_failure.sh

    # Step 2: Restore in us-west-2
    PROJECT_NAME=${var.project_name} \
    BACKUP_ROLE_ARN=${module.iam.backup_role_arn} \
    DR_RDS_SG_ID=<dr-sg-id> \
    DB_NAME=${var.db_name} \
    ./scripts/restore_from_backup.sh

    # Step 3: Verify
    DR_DB_ENDPOINT=<restored-endpoint> \
    DB_USERNAME=${var.db_username} \
    ./scripts/verify_dr.sh
  EOT
}
```

---

## PART 17 — DOCUMENTATION

### `docs/architecture.md`

Generate a full architecture document containing:
1. **Overview** — What FinCorp's system does and why
2. **Architecture Diagram** (ASCII art) showing:
   - Developer → GitHub → CodePipeline → CodeBuild → CodeArtifact (npm/pip proxy) → ECR (immutable, scanned) → ECS Fargate → RDS (us-east-1)
   - AWS Backup → Cross-Region Copy → DR Vault (us-west-2)
   - CloudFront → S3 (frontend)
3. **Security Controls** — IMMUTABLE tags, scan-on-push, vulnerability gate, Secrets Manager, KMS encryption, private subnets, security groups, IAM least privilege
4. **Data Flow** — How the Expense/Income app reads and writes to RDS

### `docs/dr_runbook.md`

Generate a step-by-step DR runbook:
1. **Detection** — How you know the primary region has failed (CloudWatch alarms)
2. **Decision** — RTO/RPO thresholds (target: restore within 30 minutes)
3. **Execution** — Run `simulate_region_failure.sh`, then `restore_from_backup.sh`
4. **Validation** — Run `verify_dr.sh`, confirm app connects to restored DB
5. **Post-Recovery** — Update DNS / ALB endpoint, update ECS environment variables, notify stakeholders
6. **Timeline Table** showing expected elapsed time per step

### `docs/pipeline_guide.md`

Document the pipeline:
1. How CodeArtifact acts as a secure upstream proxy (packages never fetched directly from internet)
2. Tag immutability explanation and why it matters
3. Scan-on-push + the vulnerability gate in `buildspec.yml`
4. How to view scan results in the AWS Console
5. How to intentionally trigger a build failure for demonstration (use a Dockerfile that installs an old vulnerable package)

---

## PART 18 — DEPLOYMENT SEQUENCE

Generate a `README.md` at project root with these ordered steps:

```
1. Prerequisites
   - AWS CLI configured with AdministratorAccess
   - Terraform >= 1.6 installed
   - Docker installed and running
   - Node.js >= 18 installed
   - GitHub repo created with app code pushed

2. Bootstrap
   terraform init
   terraform plan -out=tfplan
   terraform apply tfplan

3. Connect GitHub to CodePipeline
   - Go to AWS Console → Developer Tools → Connections
   - Authorize the GitHub App for your repo
   - Copy the Connection ARN into terraform.tfvars as codestar_connection_arn

4. Trigger First Build
   git push origin main
   # Watch pipeline in AWS Console → CodePipeline

5. Access the App
   terraform output app_frontend_url

6. Seed the Database
   mysql -h $(terraform output -raw primary_db_endpoint) \
     -u $DB_USER -p $DB_PASS < app/backend/src/migrations/init.sql

7. Run DR Simulation
   # Follow docs/dr_runbook.md
   PROJECT_NAME=fincorp ./scripts/simulate_region_failure.sh

8. Destroy (cleanup lab)
   terraform destroy
```

---

## CONSTRAINTS & QUALITY REQUIREMENTS

- **Every resource must have a `tags` block** with at minimum: `Project`, `Environment`, `ManagedBy = "Terraform"`.
- **No hardcoded credentials** anywhere. All secrets via `var` (fed by `TF_VAR_` env vars) or Secrets Manager.
- **All S3 buckets**: block public access, versioning enabled, SSE encryption.
- **All RDS**: encrypted at rest with KMS, no public access.
- **All IAM policies**: least-privilege, scoped to specific ARNs not `*` where possible.
- **`depends_on`**: add where Terraform cannot infer ordering (e.g., IAM role before CodeBuild).
- **Use `data` sources** for: current AWS account ID, available AZs, current region.
- **All modules**: include a `README.md` listing inputs, outputs, and what it creates.
- **The buildspec.yml vulnerability gate must `exit 1`** on High/Critical findings — this is a hard requirement, not optional logging.

---

*End of FinCorp Terraform Lab Prompt — generate all files in the structure above, complete and production-ready.*