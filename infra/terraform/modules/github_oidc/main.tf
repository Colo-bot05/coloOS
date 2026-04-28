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

# tflock inline policy で参照する account_id / region を取得（ハードコード回避、ST0-3.1）。
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

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

# State lock テーブル R/W の最小権限（ST0-3.1）。
# ReadOnlyAccess は dynamodb:GetItem は許可するが PutItem / DeleteItem は許可しない。
# Terraform plan は state lock 取得時に PutItem を、解放時に DeleteItem を呼ぶため、
# このテーブル 1 つに限定して 3 アクションのみ許可する。
# 対象を coloos-tflock テーブルに厳密に限定（他の DynamoDB リソースには影響なし）。
# これを広げる変更（他テーブル / "*" / 他 Action 追加）は CLAUDE.md / AGENTS.md 規約により禁止。
resource "aws_iam_role_policy" "tflock" {
  name = "tflock-state-lock-rw"
  role = aws_iam_role.deploy.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
      ]
      Resource = "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/coloos-tflock"
    }]
  })
}

# Role ARN を SSM Parameter Store に保存。CI / 他モジュールが参照可能。
resource "aws_ssm_parameter" "role_arn" {
  name        = "/coloos/${var.env}/gha/role_arn"
  type        = "String"
  value       = aws_iam_role.deploy.arn
  description = "GitHub Actions OIDC AssumeRole ARN for ${var.env}"
}
