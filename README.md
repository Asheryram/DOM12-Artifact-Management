# FinCorp Secure Supply Chain & Disaster Recovery Lab

A production-grade AWS infrastructure simulation demonstrating:
- Secure CI/CD with immutable artifacts (CodeArtifact + ECR)
- Cross-region disaster recovery for RDS (us-east-1 to us-west-2, RTO <= 30 min)
- An Expense & Income Tracker app on ECS Fargate + RDS MySQL

## Prerequisites

- AWS CLI configured with AdministratorAccess
- Terraform >= 1.6 installed
- Docker installed and running
- Node.js >= 18 installed
- GitHub repository created with app code pushed

## Deployment

### 1. Set sensitive variables

```bash
export TF_VAR_db_username="fincorp_admin"
export TF_VAR_db_password="YourStrongPassword123!"   # min 16 chars
export TF_VAR_github_repo="your-org/your-repo"
export TF_VAR_codestar_connection_arn=""              # fill after step 3
```

### 2. Bootstrap infrastructure

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 3. Connect GitHub to CodePipeline

1. Go to AWS Console -> Developer Tools -> Settings -> Connections
2. Authorize the GitHub App for your repository
3. Copy the Connection ARN
4. Set TF_VAR_codestar_connection_arn and re-apply

### 4. Trigger first build

```bash
git push origin main
# Watch: AWS Console -> CodePipeline -> fincorp-pipeline
```

### 5. Access the app

```bash
terraform output app_frontend_url
terraform output app_alb_dns
```

### 6. Seed the database

```bash
mysql -h $(terraform output -raw primary_db_endpoint) \
  -u $TF_VAR_db_username -p$TF_VAR_db_password \
  < app/backend/src/migrations/init.sql
```

### 7. Run DR simulation

Follow docs/dr_runbook.md:

```bash
PROJECT_NAME=fincorp ./scripts/simulate_region_failure.sh
```

Then restore:

```bash
PROJECT_NAME=fincorp \
BACKUP_ROLE_ARN=$(terraform output -raw backup_role_arn) \
DB_NAME=fincorpdb \
./scripts/restore_from_backup.sh
```

### 8. Destroy (cleanup)

```bash
terraform destroy
```

## Project Structure

```
fincorp-lab/
├── main.tf / variables.tf / outputs.tf / versions.tf / terraform.tfvars
├── modules/
│   ├── networking/      VPC, subnets, security groups
│   ├── ecr/             ECR repo (immutable tags, scan-on-push)
│   ├── codeartifact/    npm + pip proxy repositories
│   ├── codepipeline/    CodePipeline + CodeBuild + buildspec
│   ├── iam/             Least-privilege roles for all services
│   ├── rds_primary/     RDS MySQL in us-east-1
│   ├── rds_dr/          DR networking pre-requisites in us-west-2
│   ├── backup/          AWS Backup with cross-region copy
│   ├── app_backend/     ECS Fargate + ALB
│   └── app_frontend/    S3 + CloudFront
├── app/
│   ├── backend/         Node.js Express API
│   └── frontend/        React SPA (Vite)
├── scripts/             DR simulation scripts
└── docs/                Architecture, DR runbook, pipeline guide
```

## Documentation

- [Architecture](docs/architecture.md)
- [DR Runbook](docs/dr_runbook.md)
- [Pipeline Guide](docs/pipeline_guide.md)
