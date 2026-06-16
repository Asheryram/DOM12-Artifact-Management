data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_kms_key" "codeartifact" {
  description             = "KMS key for CodeArtifact domain encryption"
  deletion_window_in_days = 7
  tags                    = local.common_tags
}

resource "aws_codeartifact_domain" "main" {
  domain         = "${var.project_name}-artifacts"
  encryption_key = aws_kms_key.codeartifact.arn
  tags           = local.common_tags
}

resource "aws_codeartifact_repository" "npm_store" {
  repository = "npm-store"
  domain     = aws_codeartifact_domain.main.domain

  external_connections {
    external_connection_name = "public:npmjs"
  }

  tags = local.common_tags
}

resource "aws_codeartifact_repository" "pip_store" {
  repository = "pip-store"
  domain     = aws_codeartifact_domain.main.domain

  external_connections {
    external_connection_name = "public:pypi"
  }

  tags = local.common_tags
}

resource "aws_codeartifact_repository_permissions_policy" "npm_store" {
  repository      = aws_codeartifact_repository.npm_store.repository
  domain          = aws_codeartifact_domain.main.domain
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action = [
        "codeartifact:GetAuthorizationToken",
        "codeartifact:ReadFromRepository",
        "codeartifact:GetRepositoryEndpoint",
        "codeartifact:DescribeRepository"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_codeartifact_repository_permissions_policy" "pip_store" {
  repository      = aws_codeartifact_repository.pip_store.repository
  domain          = aws_codeartifact_domain.main.domain
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action = [
        "codeartifact:GetAuthorizationToken",
        "codeartifact:ReadFromRepository",
        "codeartifact:GetRepositoryEndpoint"
      ]
      Resource = "*"
    }]
  })
}
