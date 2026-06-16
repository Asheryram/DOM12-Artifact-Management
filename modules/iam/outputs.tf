output "codebuild_role_arn" { value = aws_iam_role.codebuild.arn }
output "codepipeline_role_arn" { value = aws_iam_role.codepipeline.arn }
output "ecs_execution_role_arn" { value = aws_iam_role.ecs_execution.arn }
output "ecs_task_role_arn" { value = aws_iam_role.ecs_task.arn }
output "backup_role_arn" { value = aws_iam_role.backup.arn }
