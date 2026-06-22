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
  aws_region   = var.primary_region
}

module "iam" {
  source                  = "./modules/iam"
  providers               = { aws = aws.primary }
  project_name            = var.project_name
  environment             = var.environment
  ecr_repository_arn      = module.ecr.repository_arn
  codeartifact_domain     = module.codeartifact.domain_name
  codeartifact_domain_arn = module.codeartifact.domain_arn
  npm_repository_arn      = module.codeartifact.npm_repository_arn
  pip_repository_arn      = module.codeartifact.pip_repository_arn
}

module "ecr" {
  source        = "./modules/ecr"
  providers     = { aws = aws.primary }
  project_name  = var.project_name
  ecr_repo_name = var.ecr_repo_name
  environment   = var.environment
}

module "codeartifact" {
  source       = "./modules/codeartifact"
  providers    = { aws = aws.primary }
  project_name = var.project_name
  environment  = var.environment
}

module "codepipeline" {
  source                  = "./modules/codepipeline"
  providers               = { aws = aws.primary }
  project_name            = var.project_name
  environment             = var.environment
  primary_region          = var.primary_region
  ecr_repository_url      = module.ecr.repository_url
  ecr_repo_name           = var.ecr_repo_name
  codebuild_role_arn      = module.iam.codebuild_role_arn
  codepipeline_role_arn   = module.iam.codepipeline_role_arn
  codeartifact_domain     = module.codeartifact.domain_name
  github_repo             = var.github_repo
  github_branch           = var.github_branch
  codestar_connection_arn = var.codestar_connection_arn
  ecs_cluster_name           = module.app_backend.ecs_cluster_name
  ecs_service_name           = module.app_backend.ecs_service_name
  frontend_bucket            = module.app_frontend.s3_bucket_name
  cloudfront_distribution_id = module.app_frontend.distribution_id
  alb_dns                    = module.app_backend.alb_dns_name

  depends_on = [module.iam, module.ecr, module.codeartifact, module.app_backend, module.app_frontend]
}

module "rds_primary" {
  source             = "./modules/rds_primary"
  providers          = { aws = aws.primary }
  project_name       = var.project_name
  environment        = var.environment
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  rds_instance_class = var.rds_instance_class
  private_subnet_ids = module.networking.private_subnet_ids
  rds_sg_id          = module.networking.rds_sg_id

  depends_on = [module.networking]
}

module "backup" {
  source           = "./modules/backup"
  providers        = { aws.primary = aws.primary, aws.dr = aws.dr }
  project_name     = var.project_name
  environment      = var.environment
  rds_instance_arn = module.rds_primary.db_arn
  backup_role_arn  = module.iam.backup_role_arn
  retention_days   = var.backup_retention_days

  depends_on = [module.rds_primary, module.iam]
}

module "app_backend" {
  source                 = "./modules/app_backend"
  providers              = { aws = aws.primary }
  project_name           = var.project_name
  environment            = var.environment
  aws_region             = var.primary_region
  # Bootstrap placeholder — CodePipeline replaces this with the commit-SHA tag on first deploy
  ecr_image_url          = "${module.ecr.repository_url}:latest"
  db_secret_arn          = module.rds_primary.secret_arn
  ecs_task_exec_role_arn = module.iam.ecs_execution_role_arn
  ecs_task_role_arn      = module.iam.ecs_task_role_arn
  private_subnet_ids     = module.networking.private_subnet_ids
  public_subnet_ids      = module.networking.public_subnet_ids
  ecs_sg_id              = module.networking.ecs_sg_id
  alb_sg_id              = module.networking.alb_sg_id
  vpc_id                 = module.networking.vpc_id
  ecs_cpu                = var.ecs_cpu
  ecs_memory             = var.ecs_memory

  depends_on = [module.networking, module.iam, module.rds_primary]
}

module "app_frontend" {
  source       = "./modules/app_frontend"
  providers    = { aws = aws.primary }
  project_name = var.project_name
  environment  = var.environment
  api_endpoint = "http://${module.app_backend.alb_dns_name}"

  depends_on = [module.app_backend]
}
