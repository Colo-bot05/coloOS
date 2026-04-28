terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# GitHub Actions の AssumeRole 用 IAM Role。
# OIDC Provider は AWS アカウント内で1つだけ作成可能なので、
# stg apply で作成済の Provider を data source 経由で参照する。
module "github_oidc" {
  source = "../../modules/github_oidc"

  env                  = var.env
  github_org           = "Colo-bot05"
  repo_name            = "coloOS"
  create_oidc_provider = false # stg 側で作成済を再利用
}

# 以降、ST0-4 以降の本番リソースは別 Issue で順次追加。
