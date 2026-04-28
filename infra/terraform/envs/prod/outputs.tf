output "github_oidc_role_arn" {
  description = "GitHub Actions の AssumeRole 対象 IAM Role ARN（prod）"
  value       = module.github_oidc.role_arn
}

output "github_oidc_provider_arn" {
  description = "GitHub OIDC Provider ARN（既存を data source で参照）"
  value       = module.github_oidc.provider_arn
}

output "github_oidc_ssm_parameter_name" {
  description = "Role ARN を保存した SSM Parameter 名"
  value       = module.github_oidc.ssm_parameter_name
}
