output "github_oidc_role_arn" {
  description = "GitHub Actions の AssumeRole 対象 IAM Role ARN"
  value       = module.github_oidc.role_arn
}

output "github_oidc_provider_arn" {
  description = "GitHub OIDC Provider ARN（新規作成 or 既存参照）"
  value       = module.github_oidc.provider_arn
}

output "github_oidc_ssm_parameter_name" {
  description = "Role ARN を保存した SSM Parameter 名"
  value       = module.github_oidc.ssm_parameter_name
}
