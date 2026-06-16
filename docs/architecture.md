# FinCorp Architecture

## Overview

FinCorp is a production-grade AWS infrastructure simulation for a financial company demonstrating:
- A secure, auditable CI/CD pipeline with immutable artifacts via AWS CodeArtifact and ECR
- Cross-region disaster recovery for RDS (us-east-1 to us-west-2, RTO <= 30 min)
- An Expense & Income Tracker app that makes the DR simulation meaningful

## Architecture Diagram

```
+---------------------------------------------------------------------+
|                         us-east-1 (Primary)                         |
|                                                                     |
|  Developer                                                          |
|     | git push                                                      |
|     v                                                               |
|  GitHub --> CodePipeline --> CodeBuild                              |
|                                  |                                  |
|                         +--------+--------+                         |
|                         |                 |                         |
|                  CodeArtifact        Docker Build                   |
|                  (npm-store)              |                         |
|                  (pip-store)        ECR (IMMUTABLE,                 |
|                         |            scan-on-push)                  |
|                         +--- npm ci -----+                          |
|                                                                     |
|  CloudFront <-- S3 (React SPA)   ECS Fargate <-- ALB (HTTP:80)     |
|                                       |                             |
|                                  RDS MySQL                          |
|                                  (us-east-1, encrypted)            |
|                                       |                             |
|                                  AWS Backup                         |
|                                       | cross-region copy           |
+---------------------------------------+-----------------------------+
                                        |
+---------------------------------------v-----------------------------+
|                         us-west-2 (DR)                              |
|                                                                     |
|                        Backup Vault (DR)                            |
|                        +-- restore --> RDS (restored)               |
+---------------------------------------------------------------------+
```

## Security Controls

| Control | Implementation |
|---|---|
| Immutable image tags | ECR IMAGE_TAG_MUTABILITY = IMMUTABLE |
| Image scanning | ECR scan_on_push = true |
| Vulnerability gate | buildspec.yml exits 1 on HIGH/CRITICAL |
| Secrets management | AWS Secrets Manager, injected via ECS secrets |
| Encryption at rest | KMS for RDS, ECR, CodeArtifact; S3 SSE |
| Private networking | RDS and ECS in private subnets, no public access |
| Security groups | RDS ingress only from ECS SG on port 3306 |
| IAM least privilege | Scoped roles per service, no wildcard resources |

## Data Flow

1. User opens CloudFront URL -> React SPA loads from S3
2. React calls ALB -> ECS Fargate (Node.js API)
3. API reads DB credentials from Secrets Manager (injected at task start)
4. API connects to RDS MySQL via connection pool
5. Results returned as JSON { success: true, data: [...] }
