# [ST0-3] Terraform スケルトン（envs / modules / backend / GitHub Actions OIDC）

> 親：マスター設計書 §11 / §13 / §14 / STEP 0 詳細設計書 §7 / §17
> リポジトリ：https://github.com/Colo-bot05/coloOS
> ブランチ命名：`infra/ST0-3-terraform-skeleton`
> 想定工数：1日
> 依存：ST0-2（GitHub テンプレ・ブランチ保護）
> 後続をブロック：ST0-4（VPC/RDS）、ST0-5（ECS/ALB）、ST0-6（Cognito/IdP）、ST0-7（Secrets）、ST0-8（Bedrock VPCE）

---

## 背景（なぜやるか）

Phase 1 のインフラはすべて IaC（Terraform）で管理する方針（マスター §11、CLAUDE.md §7.4）。`infra/terraform/` の下に環境別エントリ（envs/{stg,prod}）と再利用可能なモジュール群を配置する設計だが、この骨格が無いと VPC・RDS・ECS・Cognito など以降のすべてのインフラ Issue が着手できない。**ST0-3 は ST0-4 以降のインフラ Issue をブロックする最重要 Issue**。

加えて、Terraform の state 管理（S3 + DynamoDB ロック）と GitHub Actions からの認証経路（OIDC ロール）も同時に整備しておくことで、**シークレットを CI に置かない安全な運用**が確立する。

## 目的

- `infra/terraform/envs/{stg,prod}/` と `infra/terraform/modules/` のディレクトリ骨格を作成
- Terraform / AWS provider のバージョン固定（`required_version` / `required_providers`）
- リモート state バックエンド（S3 + DynamoDB ロック）を構築（手動 or 専用スクリプト）
- GitHub Actions が AssumeRole で AWS にアクセスする OIDC ロール構成
- 環境別（STG / Prod）の `terraform plan` / `apply` が空（モジュール未配置）でも成功する状態
- 開発者向けに `docs/runbook/terraform-setup.md` を整備

---

## 受け入れ条件（Definition of Done）

### A. ディレクトリ骨格

- [ ] `infra/terraform/envs/stg/` と `infra/terraform/envs/prod/` が作成され、それぞれに `main.tf` / `variables.tf` / `outputs.tf` / `terraform.tfvars.example` / `backend.tf` が存在
- [ ] `infra/terraform/modules/` 配下に空モジュール用 `.gitkeep` が `vpc/` `rds/` `ecs/` `cognito/` `secrets/` `observability/` `bedrock/` `s3/` `dns_acm/` の各ディレクトリに配置される
- [ ] `infra/terraform/README.md` で配置・運用ルールを記述

### B. バージョン固定

- [ ] `envs/{stg,prod}/main.tf` で `required_version = ">= 1.9, < 2.0"`
- [ ] `required_providers` に `aws ~> 5.x`、`tls ~> 4.x`（OIDC用）を固定
- [ ] `.terraform.lock.hcl` を初回 `terraform init` 後にコミット

### C. State バックエンド（S3 + DynamoDB）

- [ ] **bootstrap 用の Terraform**（`infra/terraform/bootstrap/`）で S3 バケット `coloos-tfstate-{env}` と DynamoDB テーブル `coloos-tflock` を作成（一度だけ手動 apply）
- [ ] envs/{stg,prod}/backend.tf で S3 backend を設定（key は `{env}/terraform.tfstate`）
- [ ] バケットは Versioning ON、暗号化 SSE-S3 以上、Public Access Block 完全禁止
- [ ] DynamoDB テーブルは PAY_PER_REQUEST、Hash Key `LockID`

### D. GitHub Actions OIDC

- [ ] `infra/terraform/modules/github_oidc/` を作成し、IAM OIDC Provider と AssumeRole 用 IAM Role を構築
- [ ] Trust Policy で `repo:Colo-bot05/coloOS:*` のみ許可
- [ ] role 名：`coloos-gha-deploy-{env}`（環境別）
- [ ] role ARN を SSM Parameter Store `/coloos/{env}/gha/role_arn` に保存
- [ ] envs/stg と envs/prod の両方で OIDC role を作成

### E. CI で `terraform fmt` / `terraform validate` / `terraform plan` が走る

- [ ] `.github/workflows/terraform-ci.yml` を作成
- [ ] PR で `infra/terraform/**` に変更があったら fmt / validate / plan を実行
- [ ] plan 出力を PR コメントに自動投稿（`hashicorp/setup-terraform` + `actions/github-script`）
- [ ] OIDC で読み取り専用ロールを AssumeRole し plan のみ実行（apply は別 workflow）

### F. ドキュメント

- [ ] `docs/runbook/terraform-setup.md` を新規作成
  - 前提（Terraform 1.9+、AWS CLI、AWS Profile設定）
  - bootstrap 手順（1回だけ実行）
  - 通常の `init` / `plan` / `apply` の流れ
  - state ロックがハングした時の解除手順
  - state バケット・テーブルへの命名規則
  - Drift 検知の運用
  - ロールバック手順（state 復旧）
- [ ] root `README.md` から auth-setup.md と並べてリンク

### G. 動作確認

- [ ] STG 環境で `terraform init` 成功（S3 backend 接続成功）
- [ ] STG 環境で `terraform plan` がエラーなし、変更0で完了
- [ ] PR 作成時に terraform-ci.yml が実行され plan 結果がコメントされる
- [ ] state ファイルが `s3://coloos-tfstate-stg/stg/terraform.tfstate` に作られている

### H. PR / 運用

- [ ] CLAUDE.md / AGENTS.md 規約セルフチェック完了
- [ ] AIレビュー（GPT or Gemini）通過。**実装が Bedrock/Claude なら、レビューは Azure OpenAI または Vertex AI**
- [ ] **ブランチ削除しない**（CLAUDE.md §12.1）

---

## 想定実装内容（概要レベル）

### A. ディレクトリツリー

```
infra/terraform/
├─ bootstrap/                    # state バケット・テーブルを作る一度きり用
│   ├─ main.tf
│   ├─ variables.tf
│   └─ README.md
├─ envs/
│   ├─ stg/
│   │   ├─ main.tf
│   │   ├─ variables.tf
│   │   ├─ outputs.tf
│   │   ├─ backend.tf
│   │   ├─ providers.tf
│   │   └─ terraform.tfvars.example
│   └─ prod/
│       └─ （同上）
├─ modules/
│   ├─ vpc/.gitkeep
│   ├─ rds/.gitkeep
│   ├─ ecs/.gitkeep
│   ├─ cognito/.gitkeep
│   ├─ secrets/.gitkeep
│   ├─ observability/.gitkeep
│   ├─ bedrock/.gitkeep
│   ├─ s3/.gitkeep
│   ├─ dns_acm/.gitkeep
│   └─ github_oidc/
│       ├─ main.tf
│       ├─ variables.tf
│       └─ outputs.tf
└─ README.md
```

### B. envs/stg/main.tf（雛形）

```hcl
terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project    = "coloos"
      Env        = var.env
      ManagedBy  = "terraform"
      Repository = "Colo-bot05/coloOS"
    }
  }
}

module "github_oidc" {
  source     = "../../modules/github_oidc"
  env        = var.env
  github_org = "Colo-bot05"
  repo_name  = "coloOS"
}

# 以降、ST0-4 で vpc, ST0-5 で ecs, ST0-6 で cognito を追加していく
```

### C. envs/stg/backend.tf

```hcl
terraform {
  backend "s3" {
    bucket         = "coloos-tfstate-stg"
    key            = "stg/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "coloos-tflock"
    encrypt        = true
  }
}
```

### D. envs/stg/variables.tf

```hcl
variable "region" {
  type    = string
  default = "ap-northeast-1"
}
variable "env" {
  type    = string
  default = "stg"
  validation {
    condition     = contains(["stg", "prod"], var.env)
    error_message = "env must be stg or prod"
  }
}
```

### E. bootstrap/main.tf（一度きり実行）

```hcl
terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 5.0" } }
}

provider "aws" { region = "ap-northeast-1" }

resource "aws_s3_bucket" "tfstate" {
  bucket = "coloos-tfstate-${var.env}"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tflock" {
  name         = "coloos-tflock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}
```

### F. github_oidc モジュール（抜粋）

```hcl
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.repo_name}:*"]
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
}

# Plan 用は ReadOnly、Apply 用は別ロールで運用（後続 Issue で拡張）
resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.deploy.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_ssm_parameter" "role_arn" {
  name  = "/coloos/${var.env}/gha/role_arn"
  type  = "String"
  value = aws_iam_role.deploy.arn
}
```

### G. terraform-ci.yml（GitHub Actions）

```yaml
name: terraform-ci
on:
  pull_request:
    paths: ["infra/terraform/**"]
permissions:
  id-token: write
  contents: read
  pull-requests: write
jobs:
  plan:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        env: [stg]
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with: { terraform_version: 1.9.x }
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/coloos-gha-deploy-${{ matrix.env }}
          aws-region: ap-northeast-1
      - name: fmt
        run: terraform -chdir=infra/terraform/envs/${{ matrix.env }} fmt -check -recursive
      - name: init
        run: terraform -chdir=infra/terraform/envs/${{ matrix.env }} init -input=false
      - name: validate
        run: terraform -chdir=infra/terraform/envs/${{ matrix.env }} validate
      - name: plan
        id: plan
        run: terraform -chdir=infra/terraform/envs/${{ matrix.env }} plan -no-color -input=false -out=tfplan
        continue-on-error: true
      - name: post-plan
        uses: actions/github-script@v7
        with:
          script: |
            // plan結果をPRコメントに投稿
```

### H. docs/runbook/terraform-setup.md 章立て

1. 前提環境
2. 初回セットアップ（bootstrap 実行手順）
3. 通常運用（init / plan / apply）
4. 環境別の切り替え方
5. state ロックトラブル対処
6. Drift 検知の運用（週次手動 plan）
7. ロールバック（state バックアップから復旧）
8. 命名規則・タグ規約
9. CI/CD との関係
10. トラブルシューティング

---

## 想定テスト

| No | 観点 | 操作 | 期待結果 |
|---|---|---|---|
| 1 | bootstrap | `terraform -chdir=bootstrap apply -var env=stg` | S3 バケット・DynamoDB 作成成功 |
| 2 | バケット設定 | aws CLI で確認 | Versioning ON / SSE 有効 / Public Access Block 全部TRUE |
| 3 | env init | `terraform -chdir=envs/stg init` | S3 backend 接続成功 |
| 4 | env plan | `terraform -chdir=envs/stg plan` | エラーなし、Changes: 0 |
| 5 | OIDC | aws_iam_role が作成されている | Trust Policyに `repo:Colo-bot05/coloOS:*` |
| 6 | SSM | `aws ssm get-parameter --name /coloos/stg/gha/role_arn` | role_arn が返る |
| 7 | CI | infra/terraform 配下を変更したPR | terraform-ci.yml が走る |
| 8 | CI plan出力 | PRコメント | terraform plan 出力が貼られる |
| 9 | fmt | `terraform fmt -check -recursive` | 差分なし |
| 10 | validate | `terraform validate` | エラーなし |

---

## 関連リンク

- マスター設計書 §11 AWS構成 / §14 シークレット管理 / §16 GitHub運用 / §22 ロールバック
- STEP 0 詳細設計書 §7 infra/初期構成 / §13 CI/CD / §17 Issue一覧（ST0-3）
- ST0-2：GitHub テンプレ・ブランチ保護（依存）
- ST0-4：VPC / RDS / pgvector（後続）
- CLAUDE.md §7.4 SQL/マイグレーション / §11 環境変数とシークレット / §12.5 Adapter経由 / §12.8 本番直接コミット禁止

---

## 優先度・期限

- 優先度：**最高**（ST0-4 以降のすべてのインフラ Issue をブロック）
- 期限：ST0-2 完了から1営業日以内

---

## 役割分担

| 担当 | タスク |
|---|---|
| **人間（宮本）** | bootstrap の初回手動 apply（state バケット作成）、AWS Account ID / GitHub Secrets 設定（`AWS_ACCOUNT_ID`） |
| **Claude Code** | envs / modules ディレクトリ作成、bootstrap module、github_oidc module、terraform-ci.yml、`docs/runbook/terraform-setup.md` |
| **AIレビュー** | HCL の読みやすさ・命名規則・Trust Policy のセキュリティ観点 |
| **人間（宮本）** | STG での `terraform plan` 実走確認、PR 最終承認 |

---

## リスクと対応

| リスク | 影響 | 対応 |
|---|---|---|
| bootstrap の state がローカルのまま放置 | 高 | bootstrap module に明示的に「ローカル state」コメントを書き、運用後に S3 移行する手順を runbook に明記 |
| OIDC の Trust Policy が広すぎる | 高 | `repo:Colo-bot05/coloOS:*` でリポジトリ限定。branch ごとの絞り込みは別 Issue で検討 |
| state バケットが Public 化される | 致命的 | Public Access Block 全部TRUE、aws_s3_bucket_policy で deny も追加検討 |
| Terraform バージョンずれ | 中 | `.tool-versions` または asdf 設定をリポジトリにコミット、CI で同一バージョンを使用 |
| GitHub Actions OIDC の thumbprint が変わる | 中 | TLS thumbprint を都度更新する手順を runbook に記載 |
| state ロックが残ってデプロイ停止 | 中 | DynamoDB のロック手動解除手順を runbook に記載 |

---

## 補足・注意事項

- bootstrap だけは S3 backend が無い状態で初回実行されるため、ローカル state で apply → 完了後にS3 移行する流れ。runbook に明記
- 本 Issue は「インフラ apply のための土台」のみ。実 リソース（VPC / RDS / ECS / Cognito）は後続 Issue
- `terraform.tfvars` は `.gitignore` に入れる。`.tfvars.example` のみ commit
- IAM の権限は最小限から開始。実 apply で権限不足が出た時に都度追加（runbook に手順）
- GitHub Secrets に `AWS_ACCOUNT_ID` を登録（人間担当）

---

**Cowork から Claude Code への申し送り**

Terraform / IAM / OIDC は **誤設定が即セキュリティ事故になる領域**です。HCL の例示は雛形なので、必ず GPT / Gemini のレビューを通してください（CLAUDE.md §9.4・AGENTS.md §3.4）。

特に Trust Policy の `sub` 条件（`repo:Colo-bot05/coloOS:*`）は厳格にして、第三者リポジトリから AssumeRole されないように注意。bootstrap の state は最初ローカルでもOKですが、`docs/runbook/terraform-setup.md` で「S3 移行後はローカル state を削除する」を明記してください。
