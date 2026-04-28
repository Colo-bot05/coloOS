# Bootstrap

state バックエンド（S3 バケット + DynamoDB ロック）を **一度だけ** 作るための Terraform。

## 何を作るか

| リソース | 名前 | env | 補足 |
|---|---|---|---|
| S3 Bucket | `coloos-tfstate-{env}` | env 別 | Versioning ON / SSE-S3 / Public Access Block 全 ON / `prevent_destroy` |
| DynamoDB Table | `coloos-tflock` | env 共有 | `PAY_PER_REQUEST` / hash key `LockID` / `prevent_destroy` |

## State の置き場所

本モジュールは **backend.tf を持たない**（chicken-and-egg 問題回避）。**ローカル state** で apply する。

複数人運用に移行する場合は、bootstrap 完了後に `backend.tf` を後付けし `terraform init -migrate-state` で S3 へ移行する（手順は [`../../../docs/runbook/terraform-setup.md` §2.3](../../../docs/runbook/terraform-setup.md)）。

## Workspace の使い方

env ごとに workspace を切ること（state を分離するため）。

```bash
cd infra/terraform/bootstrap

# 初回 init
terraform init

# stg
terraform workspace new stg
terraform workspace select stg
terraform plan  -var env=stg
terraform apply -var env=stg
# → S3 バケット coloos-tfstate-stg + DynamoDB coloos-tflock 作成

# prod
terraform workspace new prod
terraform workspace select prod
terraform plan  -var env=prod -var create_lock_table=false
terraform apply -var env=prod -var create_lock_table=false
# → S3 バケット coloos-tfstate-prod のみ作成（DynamoDB は stg で作成済を共有）
```

## 禁止事項

- ❌ `terraform destroy` の実行（state バケットを失うとリカバリ困難。`prevent_destroy` 付き）
- ❌ S3 バケット versioning の OFF 化
- ❌ DynamoDB テーブルの削除（既存 state ロックが破壊される）
- ❌ `lifecycle { prevent_destroy }` を外す変更（必要なら別 Issue で議論）

## 関連

- 詳細手順: [`../../../docs/runbook/terraform-setup.md`](../../../docs/runbook/terraform-setup.md) §2
- ST0-3 Issue: `docs/issues/ISSUE_ST0-3_Terraformスケルトン.md`
