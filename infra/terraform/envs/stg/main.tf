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

# GitHub Actions の AssumeRole 用 IAM Role + OIDC Provider。
# stg を最初に apply するため、create_oidc_provider はデフォルトの true。
# prod 側は create_oidc_provider = false にして既存 Provider を data source で参照。
module "github_oidc" {
  source = "../../modules/github_oidc"

  env        = var.env
  github_org = "Colo-bot05"
  repo_name  = "coloOS"
}

# 以降、ST0-4 で vpc、ST0-5 で ecs、ST0-6 で cognito を追加していく。
