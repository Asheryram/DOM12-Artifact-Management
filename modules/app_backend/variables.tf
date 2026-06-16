variable "project_name" { type = string }
variable "environment" { type = string }
variable "ecr_image_url" { type = string }
variable "db_secret_arn" { type = string }
variable "ecs_task_exec_role_arn" { type = string }
variable "ecs_task_role_arn" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "public_subnet_ids" { type = list(string) }
variable "ecs_sg_id" { type = string }
variable "alb_sg_id" { type = string }
variable "vpc_id" { type = string }
variable "ecs_cpu" {
  type    = number
  default = 256
}
variable "ecs_memory" {
  type    = number
  default = 512
}
