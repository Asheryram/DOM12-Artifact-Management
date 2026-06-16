locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

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
  provider = aws.primary
  name     = "${var.project_name}-daily-backup"

  rule {
    rule_name         = "daily-backup-rule"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 2 * * ? *)"

    lifecycle {
      delete_after = var.retention_days
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn

      lifecycle {
        delete_after = var.retention_days
      }
    }
  }

  tags = local.common_tags
}

resource "aws_backup_selection" "rds_primary" {
  provider     = aws.primary
  name         = "${var.project_name}-rds-selection"
  plan_id      = aws_backup_plan.daily_with_crossregion.id
  iam_role_arn = var.backup_role_arn
  resources    = [var.rds_instance_arn]
}
