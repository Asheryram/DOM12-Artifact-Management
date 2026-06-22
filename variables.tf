variable "project_name" {
  type        = string
  default     = "fincorp"
  description = "Prefix for all resource names"
}

variable "primary_region" {
  type        = string
  default     = "us-east-1"
  description = "Primary AWS region"
}

variable "dr_region" {
  type        = string
  default     = "us-west-2"
  description = "Disaster recovery region"
}

variable "db_name" {
  type        = string
  default     = "fincorpdb"
  description = "RDS database name"
}

variable "db_username" {
  type        = string
  description = "RDS master username"
  sensitive   = true
}

variable "db_password" {
  type        = string
  description = "RDS master password (minimum 16 characters)"
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 16
    error_message = "db_password must be at least 16 characters long."
  }
}

variable "ecr_repo_name" {
  type        = string
  default     = "fincorp-app"
  description = "ECR repository name"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository in format owner/repo"
}

variable "github_branch" {
  type        = string
  default     = "main"
  description = "Branch to trigger pipeline"
}

variable "codestar_connection_arn" {
  type        = string
  description = "ARN of the CodeStar connection to GitHub"
}


variable "environment" {
  type        = string
  default     = "lab"
  description = "Environment label"
}

variable "backup_retention_days" {
  type        = number
  default     = 35
  description = "Days to retain backups"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t3.micro"
  description = "RDS instance size"
}

variable "ecs_cpu" {
  type        = number
  default     = 256
  description = "Fargate task CPU units"
}

variable "ecs_memory" {
  type        = number
  default     = 512
  description = "Fargate task memory MiB"
}
