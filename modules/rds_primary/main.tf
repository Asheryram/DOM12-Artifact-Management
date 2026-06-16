locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS encryption"
  deletion_window_in_days = 7
  tags                    = local.common_tags
}

resource "aws_db_subnet_group" "primary" {
  name       = "${var.project_name}-primary-subnet-group"
  subnet_ids = var.private_subnet_ids
  tags       = local.common_tags
}

resource "aws_db_instance" "primary" {
  identifier                = "${var.project_name}-primary-db"
  engine                    = "mysql"
  engine_version            = "8.0"
  instance_class            = var.rds_instance_class
  allocated_storage         = 20
  storage_type              = "gp3"
  storage_encrypted         = true
  kms_key_id                = aws_kms_key.rds.arn
  db_name                   = var.db_name
  username                  = var.db_username
  password                  = var.db_password
  db_subnet_group_name      = aws_db_subnet_group.primary.name
  vpc_security_group_ids    = [var.rds_sg_id]
  multi_az                  = false
  publicly_accessible       = false
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-final-snapshot"
  backup_retention_period   = 7
  backup_window             = "03:00-04:00"
  deletion_protection       = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-primary-rds"
    DR   = "source"
  })
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}/db/credentials"
  recovery_window_in_days = 0
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = aws_db_instance.primary.address
    port     = 3306
    dbname   = var.db_name
  })
}
