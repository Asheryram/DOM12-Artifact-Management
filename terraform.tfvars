project_name          = "fincorp"
primary_region        = "us-east-1"
dr_region             = "us-west-2"
db_name               = "fincorpdb"
ecr_repo_name         = "fincorp-app"
github_branch         = "main"
app_image_tag         = "latest"
environment           = "lab"
backup_retention_days = 35
rds_instance_class    = "db.t3.micro"
ecs_cpu               = 256
ecs_memory            = 512

# Set sensitive variables via environment variables to avoid storing secrets in this file:
#   export TF_VAR_db_username="your_db_username"
#   export TF_VAR_db_password="your_16char_min_password"
#   export TF_VAR_github_repo="owner/repo"
#   export TF_VAR_codestar_connection_arn="arn:aws:codestar-connections:..."
db_username             = ""
db_password             = ""
github_repo             = ""
codestar_connection_arn = ""
