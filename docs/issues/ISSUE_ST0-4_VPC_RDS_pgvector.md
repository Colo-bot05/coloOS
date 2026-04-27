# [ST0-4] VPC / Subnets / NAT GW / SG モジュール + RDS（pgvector有効化）モジュール作成・STG適用

> 親：マスター設計書 §11 / §12 / STEP 0 詳細設計書 §7 / §17
> リポジトリ：https://github.com/Colo-bot05/coloOS
> ブランチ命名：`infra/ST0-4-vpc-rds-pgvector`
> 想定工数：2日
> 依存：ST0-3（Terraform スケルトン）
> 後続をブロック：ST0-5（ECS）、ST0-6（Cognito Lambda の DB アクセス）、ST0-13（Memory Migration）、業務AI全般

---

## 背景（なぜやるか）

ECS（ST0-5）も Cognito の Lambda（ST0-6）も Memory のマイグレーション（ST0-13）も、**動作する VPC とアクセス可能な RDS が無いと apply できない**。Memory機構の核は pgvector による埋め込み検索なので、**RDS Engine バージョンと pgvector 拡張の有効化を最初に確実にしておく**ことがプロジェクト全体のリスクヘッジになる（マスター設計書 §17.3 のリスク列にも記載）。

VPC・RDS は 1度作ると後で構成変更しにくいリソースが多い（CIDR、Subnet、AZ）。STEP 0 で一気に Phase 1 が乗る形にしておく。

## 目的

- VPC モジュール作成：3層構成（public / private / db）× 2 AZ
- NAT GW（cost と冗長性を踏まえ STG は1台、Prod は2台）
- Security Group の最小権限設計（ALB / ECS / Lambda / RDS）
- RDS PostgreSQL 16 モジュール作成（**pgvector 拡張有効化**を Parameter Group + 初回 SQL で実現）
- DB Subnet Group / Parameter Group / Option Group / Master User の Secrets Manager 統合
- STG 環境で `terraform apply` 完了、ECS や Lambda から接続できる土台が出来ている状態

---

## 受け入れ条件（Definition of Done）

### A. VPC モジュール (`infra/terraform/modules/vpc/`)

- [ ] CIDR / リージョンを変数化、デフォルトは STG: `10.10.0.0/16` / Prod: `10.20.0.0/16`
- [ ] 2 AZ で、各 AZ に public/private/db Subnet を配置（合計6 Subnet）
- [ ] Internet Gateway / NAT GW（STG: 1台 / Prod: 2台、変数で切替）
- [ ] Public Route Table → IGW、Private Route Table → NAT、DB Route Table（同 AZ 内のみ ECS から到達可能、外部出ない）
- [ ] VPC Flow Logs を CloudWatch Logs に出力（保持90日）
- [ ] Security Group：`alb-sg`（HTTPS:443 from internet）、`ecs-sg`（80/8000 from alb-sg）、`lambda-sg`（egress only）、`rds-sg`（5432 from ecs-sg / lambda-sg のみ）
- [ ] outputs：vpc_id、public_subnet_ids、private_subnet_ids、db_subnet_ids、各 SG の id

### B. RDS モジュール (`infra/terraform/modules/rds/`)

- [ ] Engine：postgres 16
- [ ] STG：`db.t4g.medium`、Single AZ、ストレージ 50GB gp3、Backup 7日、PITR OFF
- [ ] Prod パラメータは変数で切替可能（`db.m6g.large`、Multi AZ、Backup 30日、PITR ON）
- [ ] Master Username `coloos_admin`、Master Password は **Secrets Manager で生成（`manage_master_user_password = true`）**
- [ ] DB Parameter Group：`shared_preload_libraries = vector` をパラメータで設定（pgvector用に必要）
- [ ] Option Group：必要に応じて
- [ ] DB Subnet Group：VPC モジュールの db_subnet_ids を使用
- [ ] Storage Encryption ON（KMS デフォルト or カスタムキー）
- [ ] Performance Insights ON（無料枠）
- [ ] Enhanced Monitoring 60秒
- [ ] Deletion Protection：STG OFF / Prod ON
- [ ] outputs：endpoint、port、secret_arn、db_name

### C. pgvector 拡張の有効化

- [ ] `parameter_group` で `shared_preload_libraries = vector` を指定（再起動が必要）
- [ ] `null_resource` または別の自動化手段で初回起動後に `CREATE EXTENSION IF NOT EXISTS vector;` を実行する仕組みを用意（例：Lambda + RDS Data API、または ECS の one-shot タスク）
- [ ] 単体検証：psqlで `\dx` 実行 → vector が ON

### D. Secrets Manager 統合

- [ ] DB マスタークレデンシャルが Secrets Manager に自動保存される
- [ ] Lambda / ECS が IAM 経由で取得できる Resource Policy
- [ ] ローテーションは Phase 1 では未設定（後続 Issue）

### E. envs/stg への組み込み

- [ ] `envs/stg/main.tf` から `module "vpc"` と `module "rds"` を呼び出し
- [ ] `terraform plan` で全リソースが作成予定として表示される
- [ ] STG 環境で `terraform apply` 成功
- [ ] Bastion 経由 or Session Manager で psql 接続できることを確認

### F. ドキュメント

- [ ] `docs/runbook/database-setup.md` を新規作成
  - VPC / Subnet 構成の説明
  - RDS 接続方法（Session Manager + psql）
  - pgvector の初期化手順
  - DB クレデンシャルの取得方法（Secrets Manager）
  - バックアップ / リストア手順
  - スケールアップ手順
  - トラブルシューティング

### G. テスト・検証

- [ ] `terraform validate` 通過
- [ ] CI（terraform-ci.yml）で plan が正常実行
- [ ] STG で実 apply 完了
- [ ] psql 接続テスト成功
- [ ] `CREATE EXTENSION vector` 実行成功
- [ ] サンプル `vector(3)` カラムを使った INSERT/SELECT 動作確認

### H. PR / 運用

- [ ] CLAUDE.md / AGENTS.md 規約セルフチェック完了
- [ ] AIレビュー（GPT or Gemini）通過
- [ ] **マージ後ブランチを削除しない**

---

## 想定実装内容（概要レベル）

### A. VPC モジュール（抜粋）

```hcl
# modules/vpc/main.tf
resource "aws_vpc" "main" {
  cidr_block           = var.cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "coloos-${var.env}-vpc" }
}

# Subnets（2 AZ × 3層）
locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_subnet" "public" {
  for_each = { for idx, az in local.azs : idx => az }
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.cidr, 8, each.key)         # 10.10.0.0/24, 10.10.1.0/24
  availability_zone = each.value
  map_public_ip_on_launch = true
  tags = { Name = "coloos-${var.env}-public-${each.value}", Tier = "public" }
}

resource "aws_subnet" "private" {
  for_each = { for idx, az in local.azs : idx => az }
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.cidr, 8, each.key + 10)    # 10.10.10.0/24, 11.0/24
  availability_zone = each.value
  tags = { Name = "coloos-${var.env}-private-${each.value}", Tier = "private" }
}

resource "aws_subnet" "db" {
  for_each = { for idx, az in local.azs : idx => az }
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.cidr, 8, each.key + 20)    # 10.10.20.0/24, 21.0/24
  availability_zone = each.value
  tags = { Name = "coloos-${var.env}-db-${each.value}", Tier = "db" }
}

# IGW / NAT GW / Route Tables / Flow Logs / Security Groups は省略
```

### B. RDS モジュール（抜粋）

```hcl
resource "aws_db_subnet_group" "main" {
  name       = "coloos-${var.env}-db-subnet"
  subnet_ids = var.db_subnet_ids
}

resource "aws_db_parameter_group" "main" {
  name   = "coloos-${var.env}-pg16-pgvector"
  family = "postgres16"

  parameter {
    name         = "shared_preload_libraries"
    value        = "vector"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "log_statement"
    value = "ddl"
  }
  parameter {
    name  = "log_min_duration_statement"
    value = "500"
  }
}

resource "aws_db_instance" "main" {
  identifier              = "coloos-${var.env}"
  engine                  = "postgres"
  engine_version          = "16.4"
  instance_class          = var.instance_class
  allocated_storage       = 50
  max_allocated_storage   = 200
  storage_type            = "gp3"
  storage_encrypted       = true

  username                = "coloos_admin"
  manage_master_user_password = true

  db_name                 = "coloos_ai"
  port                    = 5432
  vpc_security_group_ids  = [var.rds_sg_id]
  db_subnet_group_name    = aws_db_subnet_group.main.name
  parameter_group_name    = aws_db_parameter_group.main.name

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_days
  deletion_protection     = var.deletion_protection
  performance_insights_enabled = true
  monitoring_interval     = 60
  monitoring_role_arn     = aws_iam_role.rds_monitoring.arn

  apply_immediately = false
  skip_final_snapshot = var.env == "stg"
  final_snapshot_identifier = var.env == "prod" ? "coloos-prod-final-${formatdate("YYYYMMDDhhmm", timestamp())}" : null
}

output "endpoint"   { value = aws_db_instance.main.endpoint }
output "port"       { value = aws_db_instance.main.port }
output "secret_arn" { value = aws_db_instance.main.master_user_secret[0].secret_arn }
output "db_name"    { value = aws_db_instance.main.db_name }
```

### C. pgvector 初期化（一例：null_resource + Lambda）

```hcl
# 簡易案：DB起動後にLambdaで CREATE EXTENSION
resource "null_resource" "enable_pgvector" {
  depends_on = [aws_db_instance.main]

  provisioner "local-exec" {
    command = <<EOT
aws lambda invoke \
  --function-name ${aws_lambda_function.bootstrap_db.function_name} \
  --payload '{"action":"enable_pgvector"}' \
  /tmp/lambda_response.json
EOT
  }
}
```

> Phase 1 では Session Manager + psql で手動実行でも可。runbook に手順を記載。

### D. envs/stg/main.tf への組み込み

```hcl
module "vpc" {
  source                 = "../../modules/vpc"
  env                    = var.env
  cidr                   = "10.10.0.0/16"
  enable_dual_nat        = false  # STG は 1台
}

module "rds" {
  source                  = "../../modules/rds"
  env                     = var.env
  db_subnet_ids           = module.vpc.db_subnet_ids
  rds_sg_id               = module.vpc.rds_sg_id
  instance_class          = "db.t4g.medium"
  multi_az                = false
  backup_retention_days   = 7
  deletion_protection     = false
}
```

### E. Security Group の依存関係

```
internet --(443)--> alb-sg --(80/8000)--> ecs-sg --(5432)--> rds-sg
                                            ↑
                                         lambda-sg (egress) --(5432)--> rds-sg
```

---

## 想定テスト

| No | 観点 | 操作 | 期待結果 |
|---|---|---|---|
| 1 | terraform plan | `terraform plan` (stg) | エラーなし、リソース一覧が想定通り |
| 2 | terraform apply | apply | VPC / Subnets×6 / IGW / NAT / RT / SG / RDS 作成 |
| 3 | サブネット構成 | `aws ec2 describe-subnets` | public/private/db 各 2 AZ |
| 4 | NAT GW | EIP・状態 | 1 EIP、Available |
| 5 | RDS 起動 | `aws rds describe-db-instances` | available |
| 6 | Secrets | Master User Secret 生成 | Secrets Manager に自動作成 |
| 7 | psql 接続 | Session Manager 経由 | psql 接続成功 |
| 8 | pgvector | `\dx` で確認 | vector が一覧に出る |
| 9 | sample insert | `CREATE TABLE t (e vector(3));` `INSERT INTO t VALUES ('[1,2,3]');` | 成功 |
| 10 | flow logs | CloudWatch Logs | フローログが届いている |
| 11 | 監視 | Performance Insights | 有効 |
| 12 | SG 制限 | rds-sg に外部から psql | タイムアウトで拒否される |
| 13 | コスト | Cost Explorer で本日分 | NAT GW / RDS が想定額 |

---

## 関連リンク

- マスター設計書 §11 AWS構成 / §12 STG/Prod環境構成 / §15 監視・ログ
- STEP 0 詳細設計書 §7.1 / §7.2 / §17 Issue一覧（ST0-4）
- Memory機構 詳細設計書 §3 DB詳細（pgvector前提）
- ST0-3：Terraform スケルトン（依存）
- ST0-5：ECS / ALB（後続）
- ST0-13：Memory系テーブル＋pgvector index 追加（後続、本IssueでpgvectorがONになっている前提）
- CLAUDE.md §7.4 SQL/マイグレーション

---

## 優先度・期限

- 優先度：**最高**
- 期限：ST0-3 完了から3営業日以内

---

## 役割分担

| 担当 | タスク |
|---|---|
| **Claude Code** | VPC / RDS モジュール HCL、envs/stg 組み込み、`docs/runbook/database-setup.md` 作成 |
| **AIレビュー** | CIDR 設計、SG ルール、Encryption、Backup 設定、Engine version |
| **人間（宮本）** | STG での `terraform apply` 実走、Session Manager 経由の psql 接続確認、pgvector の `CREATE EXTENSION` 実行（Phase 1 は手動でも可）、PR 最終承認 |

---

## リスクと対応

| リスク | 影響 | 対応 |
|---|---|---|
| pgvector が RDS Engine バージョンで使えない | 致命 | Engine 16.4 で対応確認済み（AWS docs）。万一不可なら Aurora PostgreSQL Compatible へ切替検討 |
| CIDR 競合（社内既存VPCと） | 高 | STG `10.10.0.0/16` / Prod `10.20.0.0/16` を予約。社内ネットワーク管理者に事前確認 |
| NAT GW のコスト超過 | 中 | STG は1台のみ、Prod も最小2台。月次コスト監視を ST0-21 で実装 |
| RDS マスターパスワード漏洩 | 高 | `manage_master_user_password` で AWS 側に管理委譲、Terraform state には平文で残らない |
| Backup window と Maintenance window の重複 | 中 | 明示指定（backup 18:00-19:00 UTC、maintenance Sun 19:00-20:00 UTC） |
| pgvector 初期化忘れ | 高 | runbook に「STG apply 後に必ず psql で `\dx` 確認」を明記 |
| 削除保護なしで誤削除 | 致命（Prod） | Prod は `deletion_protection=true` 必須、`skip_final_snapshot=false` |

---

## 補足・注意事項

- **CIDR は社内ネットワークと重ならないか宮本さん側で要確認**。重なる場合は変数で上書き可能
- 本 Issue で作るのは STG のみ。Prod は別 Issue（ST0-25 のデプロイ Issue 完了後）で apply
- AZ は `ap-northeast-1a` / `ap-northeast-1c` を想定（1b は新規アカウントで使えないことが多い）
- Aurora Serverless v2 への将来移行余地は残す（VPC 構造は同じため切替容易）
- Read Replica は Phase 2 以降

---

**Cowork から Claude Code への申し送り**

VPC / RDS は **後から変更が難しいリソースが多い**ので、CIDR・AZ・Subnet マスク・SG ルールはレビューで特に厳しく見てもらってください（GPT/Gemini 両方推奨）。pgvector の `shared_preload_libraries` パラメータは再起動が必要なので、初回 apply 後に `\dx` で確認するまでが本 Issue の責任範囲です。

`manage_master_user_password = true` は **Terraform state にパスワードを残さない**ための重要な設定です。これを削除する変更は今後一切受け付けない方針で。
