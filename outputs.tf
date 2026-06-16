output "ecr_repository_url" {
  description = "ECR repository URL for the application image"
  value       = module.ecr.repository_url
}

output "codeartifact_npm_endpoint" {
  description = "CodeArtifact npm repository endpoint"
  value       = module.codeartifact.npm_repository_endpoint
}

output "codepipeline_name" {
  description = "Name of the CodePipeline"
  value       = module.codepipeline.pipeline_name
}

output "primary_db_endpoint" {
  description = "Primary RDS database endpoint"
  value       = module.rds_primary.db_endpoint
  sensitive   = true
}

output "primary_db_identifier" {
  description = "Primary RDS database identifier"
  value       = module.rds_primary.db_identifier
}

output "backup_plan_id" {
  description = "AWS Backup plan ID"
  value       = module.backup.backup_plan_id
}

output "dr_vault_arn" {
  description = "DR backup vault ARN in us-west-2"
  value       = module.backup.dr_vault_arn
}

output "app_alb_dns" {
  description = "Application Load Balancer DNS name"
  value       = module.app_backend.alb_dns_name
}

output "app_frontend_url" {
  description = "Frontend CloudFront URL"
  value       = "https://${module.app_frontend.cloudfront_domain}"
}

output "app_api_url" {
  description = "Backend API URL"
  value       = "http://${module.app_backend.alb_dns_name}"
}

output "dr_simulation_commands" {
  description = "Commands to run DR simulation"
  value       = <<-EOT
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
