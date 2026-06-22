output "domain_name" { value = aws_codeartifact_domain.main.domain }
output "domain_arn" { value = aws_codeartifact_domain.main.arn }
output "npm_repository_endpoint" { value = "https://${aws_codeartifact_domain.main.domain}-${data.aws_caller_identity.current.account_id}.d.codeartifact.${data.aws_region.current.name}.amazonaws.com/npm/${aws_codeartifact_repository.npm_store.repository}/" }
output "pip_repository_endpoint" { value = "https://${aws_codeartifact_domain.main.domain}-${data.aws_caller_identity.current.account_id}.d.codeartifact.${data.aws_region.current.name}.amazonaws.com/pypi/${aws_codeartifact_repository.pip_store.repository}/simple/" }
output "npm_repository_arn" { value = aws_codeartifact_repository.npm_store.arn }
output "pip_repository_arn" { value = aws_codeartifact_repository.pip_store.arn }
