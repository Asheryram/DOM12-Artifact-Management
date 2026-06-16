output "db_instance_id" {
  value = aws_db_instance.primary.id
}

output "db_endpoint" {
  value     = aws_db_instance.primary.address
  sensitive = true
}

output "db_arn" {
  value = aws_db_instance.primary.arn
}

output "db_identifier" {
  value = aws_db_instance.primary.identifier
}

output "secret_arn" {
  value = aws_secretsmanager_secret.db_credentials.arn
}
