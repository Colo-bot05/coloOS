# GitHub Actions OIDC Provider と AssumeRole 用 IAM Role を作成する。
#
# OIDC Provider は AWS アカウント内で1つだけ存在できるため、
# - 最初の env（stg 想定）では create_oidc_provider = true（新規作成）
# - 2 つ目以降の env（prod など）では create_oidc_provider = false（data source で既存参照）
# のパターンを取る。
#
# Trust Policy の sub 条件は repo:Colo-bot05/coloOS:* に厳密に限定。
# これを緩める変更は CLAUDE.md / AGENTS.md の規約により禁止（別 Issue で議論）。

locals {
  oidc_provider_arn = (
    var.create_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github[0].arn
  )
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # GitHub の OIDC 証明書 thumbprint。
  # 2023 年以降 AWS が自動検証するため固定値で運用可能だが、
  # GitHub 側のローテーションが起きた場合は本値を更新する（runbook §10 参照）。
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1

  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    # 保護対象ブランチ（main / staging / release/stg / release/prod）からの workflow のみ AssumeRole 可。
    # PR ブランチ（feature/* / fix/* など）からは AssumeRole 不可（terraform-ci.yml は plan 用なので
    # 別経路の short-lived credential や PR コメント post 用 token に分離されるべき。後続 Issue で整備）。
    # values を緩める変更は CLAUDE.md / AGENTS.md 規約により禁止（GPT クロスレビュー F-009）。
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        for b in var.protected_branches :
        "repo:${var.github_org}/${var.repo_name}:ref:refs/heads/${b}"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "coloos-gha-deploy-${var.env}"
  assume_role_policy = data.aws_iam_policy_document.trust.json
  description        = "GitHub Actions OIDC AssumeRole IAM Role for ${var.env}"
}

# Phase 1 暫定: ReadOnlyAccess（terraform plan 用）。
# Apply 用の最小権限ロールは ST0-22 / ST0-23 で別途整備する方針。
resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.deploy.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Role ARN を SSM Parameter Store に保存。CI / 他モジュールが参照可能。
resource "aws_ssm_parameter" "role_arn" {
  name        = "/coloos/${var.env}/gha/role_arn"
  type        = "String"
  value       = aws_iam_role.deploy.arn
  description = "GitHub Actions OIDC AssumeRole ARN for ${var.env}"
}
