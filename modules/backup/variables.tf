variable "project_name" { type = string }
variable "environment" { type = string }
variable "rds_instance_arn" { type = string }
variable "backup_role_arn" { type = string }
variable "retention_days" {
  type    = number
  default = 35
}
