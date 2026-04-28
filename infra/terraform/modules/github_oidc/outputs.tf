output "role_arn" {
  description = "AssumeRole 対象の IAM Role ARN"
  value       = aws_iam_role.deploy.arn
}

output "provider_arn" {
  description = "GitHub OIDC Provider ARN（新規作成 or 既存参照）"
  value       = local.oidc_provider_arn
}

output "ssm_parameter_name" {
  description = "Role ARN を保存した SSM Parameter 名"
  value       = aws_ssm_parameter.role_arn.name
}
