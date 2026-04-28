# Terraform Configuration

`infra/terraform/` は Colobiz AI Workspace の AWS インフラを管理する。

## 配置

```
infra/terraform/
├─ bootstrap/                state バケット・ロックテーブルを作る一度きり用
│   ├─ main.tf
│   ├─ variables.tf
│   └─ README.md
├─ envs/
│   ├─ stg/                  STG 環境の Terraform エントリ
│   │   ├─ main.tf           terraform {} ブロック・モジュール呼び出し
│   │   ├─ providers.tf      provider "aws"（default_tags 付）
│   │   ├─ backend.tf        S3 backend 設定
│   │   ├─ variables.tf      region / env など
│   │   ├─ outputs.tf        モジュール出力
│   │   └─ terraform.tfvars.example
│   └─ prod/                 PROD 環境（同構成）
└─ modules/                  再利用モジュール
    ├─ github_oidc/          GitHub Actions AssumeRole（IAM Role + OIDC Provider）
    ├─ vpc/                  （ST0-4 で実装）
    ├─ rds/                  （ST0-4 で実装）
    ├─ ecs/                  （ST0-5 で実装）
    ├─ cognito/              （ST0-6 で実装）
    ├─ secrets/              （ST0-7 で実装）
    ├─ observability/        （後続）
    ├─ bedrock/              （ST0-8 で実装）
    ├─ s3/                   （後続）
    └─ dns_acm/              （後続）
```

## 運用ルール

1. **`terraform apply` は plan を必ずレビュー**：CI / Claude Code いずれも自動 apply 禁止（CLAUDE.md §6・本 Issue ST0-3）
2. **state バケット・ロックテーブルは destroy 厳禁**：bootstrap 完了後は触らない（CLAUDE.md §12.9）
3. **シークレットを HCL に書かない**：SSM Parameter Store / Secrets Manager 経由（CLAUDE.md §11 / §12.3）
4. **モジュール内の Trust Policy は厳密に**：`repo:Colo-bot05/coloOS:*` で限定（広げる変更は別 Issue 必須）
5. **backend.tf を直接書き換えない**：マイグレーションが必要な場合は別 Issue で議論
6. **モデル ID / Provider ID をハードコードしない**：将来 LLM 設定をここに置く場合は `infra/config/llm_routes.yaml` 経由（CLAUDE.md §9.3）

## 詳細手順

[../../docs/runbook/terraform-setup.md](../../docs/runbook/terraform-setup.md) を参照。

## バージョン固定

| 対象 | バージョン | 固定方法 |
|---|---|---|
| Terraform | **1.9.x** | `.terraform-version`（リポジトリ直下、tfenv が読む） |
| AWS Provider | `~> 5.0` | `envs/*/main.tf` の `required_providers` |
| TLS Provider | `~> 4.0` | 同上（OIDC 用） |
