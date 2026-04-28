# Terraform Setup Runbook

Colobiz AI Workspace の Terraform 管理運用ドキュメント（マスター設計書 §11 / STEP 0 詳細設計書 §7 / ISSUE_ST0-3 §H 準拠）。

## 1. 前提環境

| ツール | バージョン | 備考 |
|---|---|---|
| Terraform | **1.9.x**（`.terraform-version` で固定） | tfenv 経由で取得推奨 |
| AWS CLI | 2.x | プロファイル設定済み（`aws configure`） |
| jq | 任意 | plan / state の整形に便利 |
| tfenv | 3.2+ | Terraform バージョン切替 |

### tfenv の落とし穴（**必読**）

> ⚠️ **tfenv 3.2.0（Homebrew）は `~/.config/tfenv` の親ディレクトリを自前で作成しないため、初回 `tfenv install` 時に lock 取得失敗ループに陥る。事前に以下を実行してから `tfenv install` を行うこと**：
>
> ```bash
> mkdir -p ~/.config/tfenv/versions
> tfenv install 1.9.8
> tfenv use 1.9.8
> ```
>
> ST0-3 フェーズA でも実際に発生した既知の問題。

## 2. 初回セットアップ（bootstrap 実行手順）

state バックエンドが存在しない最初の一回だけ、以下を実行する。

### 2.1 bootstrap apply（STG 用）

```bash
cd infra/terraform/bootstrap

# 初回 init（local state）
terraform init

# stg 用ワークスペース作成
terraform workspace new stg
terraform workspace select stg

# plan / apply
terraform plan  -var env=stg
terraform apply -var env=stg
# → S3 バケット coloos-tfstate-stg + DynamoDB coloos-tflock 作成
```

### 2.2 bootstrap apply（PROD 用）

DynamoDB は env をまたいで共有するため、prod では作成抑止する。

```bash
# prod 用ワークスペース作成
terraform workspace new prod
terraform workspace select prod

# DynamoDB は stg で共有作成済なので変数で抑止
terraform plan  -var env=prod -var create_lock_table=false
terraform apply -var env=prod -var create_lock_table=false
# → S3 バケット coloos-tfstate-prod のみ作成
```

### 2.3 (オプション) bootstrap state を S3 へ移行

ローカル state のままでも実用上問題ないが、複数人運用に備えて S3 移行を推奨する。

```bash
# infra/terraform/bootstrap/backend.tf を作成して以下を記述
cat > infra/terraform/bootstrap/backend.tf <<'BACKEND'
terraform {
  backend "s3" {
    bucket         = "coloos-tfstate-stg"
    key            = "bootstrap/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "coloos-tflock"
    encrypt        = true
  }
}
BACKEND

# 既存ローカル state を S3 にコピー
terraform init -migrate-state
# → "Do you want to copy existing state to the new backend?" に yes
```

移行後、ローカルの `terraform.tfstate*` ファイルは削除する（CLAUDE.md §11 に準拠、機密相当として扱う）。

## 3. 通常運用（init / plan / apply）

```bash
cd infra/terraform/envs/stg

# 初回または backend 変更時
terraform init

# 差分確認（必ず人間がレビュー）
terraform plan

# 適用（PR レビュー後、人間判断で実行）
terraform apply
```

> **`terraform apply` を CI から自動化しない**（CLAUDE.md §6 / ST0-3 ISSUE）。CI（`terraform-ci.yml`）は `fmt` / `validate` / `plan` のみ実行し、PR にコメントを残す。

## 4. 環境別の切り替え方

env ごとにディレクトリを切り、それぞれが独立した state を持つ。

```bash
cd infra/terraform/envs/stg   # stg を操作
cd infra/terraform/envs/prod  # prod を操作
```

> 同じ env ディレクトリ内で `terraform workspace select` を切り替える運用はしない（state ファイルが分散して混乱するため）。

## 5. State ロックトラブル対処

DynamoDB の `coloos-tflock` テーブルにロックレコードが残ってデプロイがハングした場合：

```bash
# ロックの内容を確認
aws dynamodb scan --table-name coloos-tflock --region ap-northeast-1

# ロック ID を確認したうえで強制解除
terraform force-unlock <LOCK_ID>
```

> ⚠️ `force-unlock` は他のユーザーが進行中の `apply` を破壊する可能性がある。実行前に必ずチームに確認（Slack #infra）。

## 6. Drift 検知の運用

週次手動 plan（または将来は GitHub Actions の cron 化）で drift（外部変更との差分）を検知する。

```bash
cd infra/terraform/envs/stg
terraform plan -refresh=true
# → Changes: 0 が期待値。差分があれば AWS 側で手動変更があったことを意味する
```

差分があった場合の判断手順：

1. 誰がどこで変更したかを CloudTrail で確認（ログ保存先は ST0-7 / ST0-22 で整備）
2. 設計上正当な変更なら HCL に取り込んで PR を立てる
3. 不正な変更ならロールバック（§7）

## 7. ロールバック（state バックアップから復旧）

S3 バケットは Versioning ON なので、過去の state ファイルをいつでも復元できる。

```bash
# 過去のバージョン一覧
aws s3api list-object-versions --bucket coloos-tfstate-stg --prefix stg/terraform.tfstate

# 特定バージョンを取得
aws s3api get-object --bucket coloos-tfstate-stg \
  --key stg/terraform.tfstate \
  --version-id <VERSION_ID> \
  /tmp/terraform.tfstate.bak

# 確認後、state を上書き（必ず作業中の人がいないことを確認）
aws s3 cp /tmp/terraform.tfstate.bak s3://coloos-tfstate-stg/stg/terraform.tfstate
```

> ⚠️ state の手動復旧は最終手段。実行前に必ずチームに通知。CLAUDE.md §22（ロールバック）も参照。

## 8. 命名規則・タグ規約

| 種別 | 命名 | 例 |
|---|---|---|
| S3 バケット (state) | `coloos-tfstate-{env}` | `coloos-tfstate-stg` / `coloos-tfstate-prod` |
| DynamoDB (lock) | `coloos-tflock` | （env 共通） |
| IAM Role (GitHub Actions) | `coloos-gha-deploy-{env}` | `coloos-gha-deploy-stg` |
| SSM Parameter | `/coloos/{env}/<カテゴリ>/<キー>` | `/coloos/stg/gha/role_arn` |

`provider "aws" { default_tags { tags = { Project = "coloos", Env = var.env, ManagedBy = "terraform", Repository = "Colo-bot05/coloOS" } } }` で全リソースに自動タグ付与（`envs/*/providers.tf` に記載済）。

## 9. CI/CD との関係

`.github/workflows/terraform-ci.yml` は **二段構造**で動作する。

### 9.1 PR 時：static validation のみ（AWS 非接触）

- トリガー: `pull_request` で `infra/terraform/**` または同 workflow ファイルが変更された PR
- 実行内容：
  - `terraform fmt -check -recursive infra/terraform`
  - 各 root module（bootstrap / envs/stg / envs/prod）で `terraform init -backend=false` + `terraform validate`
- **AWS OIDC AssumeRole は使わない**
- **terraform plan は実行しない**
- 結果サマリを PR コメントに自動投稿（"Terraform static validation result"）

### 9.2 protected branch push / workflow_dispatch 時：real plan（AWS OIDC）

- トリガー: `main` / `staging` / `release/stg` / `release/prod` への push、または `workflow_dispatch`
- 実行内容：
  - OIDC AssumeRole で `coloos-gha-deploy-{env}` を Assume
  - `terraform -chdir=infra/terraform/envs/{env} init -reconfigure`
  - `terraform plan`
- 必須 GitHub Secret: `AWS_ACCOUNT_ID`（`gh secret set AWS_ACCOUNT_ID -b "977399288419"`）
- **`terraform apply` は CI から自動実行しない**（人間判断、CLAUDE.md §6）

### 9.3 なぜ二段構造か（F-009 対応）

GitHub Actions の OIDC token の `sub` クレームは、トリガー種別で異なる：

| トリガー | `sub` クレーム |
|---|---|
| push to `main` | `repo:Colo-bot05/coloOS:ref:refs/heads/main` |
| push to `staging` | `repo:Colo-bot05/coloOS:ref:refs/heads/staging` |
| pull_request from `feature/*` | `repo:Colo-bot05/coloOS:pull_request` |
| pull_request from forked PR | `repo:<fork>/coloOS:pull_request` |

現在の `coloos-gha-deploy-{env}` Role の Trust Policy は **protected branch 4 本（`ref:refs/heads/{main,staging,release/stg,release/prod}`）に厳密に限定**している（GPT クロスレビュー F-009）。`pull_request` 形の sub は意図的に除外しており、**feature branch / PR / fork PR から AWS Role を AssumeRole することは構造的に不可**。

PR 時の利便性のために `pull_request` を Trust Policy に追加することは、F-009 で潰した穴を再度開けるため**禁止**。代わりに `-backend=false` + `validate` + `fmt` で AWS 非接触の構文チェックのみ実行する設計とした。

### 9.4 feature PR で real plan を走らせたい将来要件

`feature/*` PR から real plan を実行する Role が必要になった場合は、本 Role を緩めるのではなく、**ST0-33（GitHub Actions / IaC 権限分離）で plan-only Role として別途設計する**：

- 専用の plan-only Role（例：`coloos-gha-plan-feature`）を作成
- Trust Policy は `pull_request` 系の sub を許可
- 添付ポリシーは `ReadOnlyAccess` 相当のみ（write 権限なし）
- 現 `coloos-gha-deploy-{env}` Role には影響しない

これは ST0-3 のスコープ外。本 Issue では二段構造で運用を確立するに留める。

## GitHub Actions Role の暫定運用について（重要）

現在の `coloos-gha-deploy-{env}` Role には以下の権限のみアタッチされています：

1. **`ReadOnlyAccess`** 管理ポリシー（attached managed policy）
2. **`tflock-state-lock-rw`** インラインポリシー（ST0-3.1 で追加）
   - 許可 Action: `dynamodb:GetItem` / `dynamodb:PutItem` / `dynamodb:DeleteItem`
   - 対象 Resource: `coloos-tflock` テーブル **1 つのみ**

これは Phase 1 の terraform plan 専用の **暫定** Role です。

### なぜ tflock 専用 R/W が必要か

`ReadOnlyAccess` は `dynamodb:GetItem` は許可しますが、`dynamodb:PutItem` / `DeleteItem` は許可しません。一方、`terraform plan`（および apply）は実行前に S3 backend の state lock を取得するため、DynamoDB の `coloos-tflock` テーブルに **PutItem でロックレコードを書き込む**必要があります（plan 完了時に DeleteItem で解放）。

ReadOnlyAccess 単体では plan 自体が `Error: Error acquiring the state lock` で失敗するため、`coloos-tflock` 1 リソースに限定した最小書き込み権限を `aws_iam_role_policy.tflock` インラインポリシーで追加しています。

### 何ができて、何ができないか

- ✅ plan / fmt / validate に必要な読み取り権限
- ✅ `coloos-tflock` テーブルでの state lock 取得・解放（GetItem / PutItem / DeleteItem の 3 種、対象は coloos-tflock 1 つのみ）
- ❌ apply に必要な汎用書き込み権限（`s3:Put*` / `ec2:Modify*` / `iam:Create*` / `dynamodb:*` on 他テーブル等）は付いていない
- ❌ deploy（ECS 更新等）には使えない

apply 用 Role や deploy 用 Role は、後続 Issue「**ST0-33: GitHub Actions / IaC 権限分離**」で最小権限として別途設計します。

**禁止事項**：

- 本 Role に**書き込み権限**を追加して deploy role として使い回さない（`s3:Put*` / `ec2:Modify*` / `ecs:Update*` 等の追加禁止）
- `AdministratorAccess` 等の強権限を本 Role にアタッチしない
- **`tflock-state-lock-rw` policy の対象を広げない**（`coloos-tflock` 以外への拡張、`dynamodb:*` への Action 拡張は禁止）
- `repo:*` 等の広い Trust Policy への変更も禁止（CLAUDE.md §12.5 に準ずる。`var.protected_branches` を広げない）

## 10. トラブルシューティング

| 症状 | 原因 | 対処 |
|---|---|---|
| `terraform init` で backend エラー | bootstrap 未実行 | §2 の bootstrap apply を先に実行 |
| `BucketAlreadyExists` | S3 バケット名が global namespace で衝突 | 命名変更を Issue で起票（`coloos-tfstate-{env}` → `<別名>`） |
| `EntityAlreadyExists: openid_connect_provider` | 同 AWS Account に既に GitHub OIDC Provider が存在 | `module "github_oidc"` の `create_oidc_provider = false` を指定（envs/prod は既定で false） |
| `ConditionalCheckFailedException`（DynamoDB） | 古いロックが残存 | §5 の `force-unlock` 手順 |
| `tfenv install` で lock 取得失敗ループ | `~/.config/tfenv` 親ディレクトリ未作成 | §1 の `mkdir -p ~/.config/tfenv/versions` |
| `brew Cellar/tfenv/.../versions/` に古い 87MB 残骸 | 過去の直接 libexec 経由インストールの残骸 | 無害。気になる場合は `brew uninstall tfenv && brew install tfenv` で再構築 |
| GitHub Actions OIDC の thumbprint エラー | GitHub 側証明書ローテーション | `modules/github_oidc/main.tf` の `thumbprint_list` を最新値に更新（GitHub の Actions OIDC ドキュメント参照） |
| `Error: state lock` | force-unlock が必要、または他の人が apply 中 | §5 |
| `terraform plan` 実行に AWS 認証エラー | `aws sts get-caller-identity` で確認、`aws configure` 再設定 | ローカル開発の `~/.aws/credentials` 確認 |

## 11. 関連ドキュメント

- [CLAUDE.md §6](../../CLAUDE.md) — ブランチ運用とデプロイフロー
- [CLAUDE.md §11](../../CLAUDE.md) — 環境変数とシークレット
- [CLAUDE.md §12](../../CLAUDE.md) — 禁止事項（特に §12.3 / §12.8 / §12.9）
- [docs/runbook/branch-protection.md](./branch-protection.md) — ブランチ保護
- [docs/runbook/getting-started.md](./getting-started.md) — 初回セットアップ
- [infra/terraform/README.md](../../infra/terraform/README.md) — Terraform 配置と運用ルール
- [infra/terraform/bootstrap/README.md](../../infra/terraform/bootstrap/README.md) — bootstrap モジュール詳細
