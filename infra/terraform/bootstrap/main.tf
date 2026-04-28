terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # bootstrap は chicken-and-egg 問題回避のため backend を持たない（ローカル state）。
  # 複数人運用へ移る場合は backend.tf を後付けして terraform init -migrate-state で S3 へ移行する。
  # 詳細は docs/runbook/terraform-setup.md §2.3。
}

provider "aws" {
  region = "ap-northeast-1"

  default_tags {
    tags = {
      Project    = "coloos"
      Env        = var.env
      ManagedBy  = "terraform"
      Repository = "Colo-bot05/coloOS"
      Module     = "bootstrap"
    }
  }
}

# ---- S3 Bucket: Terraform state 格納 ----
# env ごとに 1 バケット作成（coloos-tfstate-stg / coloos-tfstate-prod）。
resource "aws_s3_bucket" "tfstate" {
  bucket = "coloos-tfstate-${var.env}"

  # 取り違えで destroy しないよう lifecycle で予防（CLAUDE.md §12.9）。
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Public 化を構造的に禁止（CLAUDE.md §11 / §12.3）。
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---- DynamoDB Table: Terraform state ロック ----
# env をまたいで共有（1 テーブルのみ）。
# stg apply で作成、prod apply 時は -var create_lock_table=false で抑止する。
resource "aws_dynamodb_table" "tflock" {
  count = var.create_lock_table ? 1 : 0

  name         = "coloos-tflock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  lifecycle {
    prevent_destroy = true
  }
}
