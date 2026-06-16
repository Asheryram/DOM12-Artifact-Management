output "pipeline_name" { value = aws_codepipeline.fincorp.name }
output "pipeline_arn" { value = aws_codepipeline.fincorp.arn }
output "pipeline_bucket_arn" { value = aws_s3_bucket.pipeline_artifacts.arn }
output "pipeline_bucket_name" { value = aws_s3_bucket.pipeline_artifacts.bucket }
