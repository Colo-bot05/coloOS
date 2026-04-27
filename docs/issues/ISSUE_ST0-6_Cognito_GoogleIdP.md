# [ST0-6] Cognito モジュール + Google Workspace IdP federation + Hosted UI + Lambda トリガー

> 親：マスター設計書 §8 / STEP 0 詳細設計書 §11 / §17
> リポジトリ：https://github.com/Colo-bot05/coloOS
> ブランチ命名：`infra/ST0-6-cognito-google-idp`
> 想定工数：1.5日（人間：0.5日 / Claude Code：1日）
> 依存：ST0-3（Terraform スケルトン）
> 後続：ST0-11（apps/web + apps/api での実装）

---

## 背景（なぜやるか）

Phase 1 の認証方針は「**社員ログインの入口は Google Workspace、内部の RBAC は Cognito グループ**」という federation 構成（マスター設計書 §8）。

これがないと apps/web のサインイン画面（ST0-11）と apps/api の JWT 検証（ST0-11）が動かず、その先のすべてのIssue（業務AI / Memory / RAG）が認証ガードを実装できないまま停滞する。**ST0-6 はインフラ系で最も後続をブロックする Issue**。

## 目的

- GCP コンソールで Google OAuth 2.0 クライアントを発行する（手動）
- Terraform で Cognito User Pool / Google IdP / User Pool Client / Hosted UI Domain / Groups を構築する
- 初回ログイン時に `users` テーブルに行を作って USER グループを自動付与する PostConfirmation Lambda を構築する
- `colobiz.co.jp` 以外の Google アカウントを拒否する Pre-Token Generation Lambda を構築する
- 構築結果を SSM Parameter Store にエクスポートし、ST0-11 から参照可能にする
- `docs/runbook/auth-setup.md` に手順とロールバックを文書化する

---

## 受け入れ条件（Definition of Done）

### A. GCP コンソール（人間オペレーター実施）

- [ ] GCP プロジェクト「colobiz-ai-workspace」（既存または新規）で OAuth 2.0 クライアントID（Webアプリ）を発行済み
- [ ] Authorized JavaScript origins / Authorized redirect URIs が Cognito Hosted UI ドメインに合っている
- [ ] クライアントID / クライアントシークレットを **AWS Secrets Manager の `cognito/google-oauth/stg` と `cognito/google-oauth/prod`** に保管（Terraform から参照）
- [ ] OAuth 同意画面の User Type は「Internal」（colobiz.co.jp ドメイン内限定）
- [ ] スコープは `openid` `email` `profile` のみ

### B. Terraform：Cognito モジュール (`infra/terraform/modules/cognito/`)

- [ ] User Pool 作成（`auto_verified_attributes = ["email"]`、パスワードポリシーは federation 用に最低水準）
- [ ] User Pool Identity Provider (Google) 作成、`provider_type = "Google"`、attribute_mapping（email/name/given_name/family_name/picture）
- [ ] User Pool Client 作成、`supported_identity_providers = ["Google"]`、`allowed_oauth_flows = ["code"]`、`allowed_oauth_scopes = ["openid","email","profile"]`、`callback_urls` / `logout_urls` 設定
- [ ] User Pool Domain（Cognito 提供ドメイン `coloos-stg` 等を prefix で使用、本番カスタムドメインは別Issueで対応）
- [ ] User Pool Groups：`USER`（precedence=30）、`APPROVER`（precedence=20）、`ADMIN`（precedence=10）作成
- [ ] PostConfirmation Lambda 作成・User Pool に登録
- [ ] Pre-Token Generation Lambda 作成・User Pool に登録（ドメイン制限）
- [ ] Lambda 用 IAM ロール（最小権限）作成
- [ ] User Pool 出力値（id / client_id / hosted_ui_domain）を `output` で公開
- [ ] SSM Parameter Store に書き出し（`/coloos/{env}/cognito/user_pool_id` 等）
- [ ] STG 環境にて `terraform plan` / `apply` 成功

### C. Lambda 実装

- [ ] `infra/terraform/modules/cognito/lambda/post_confirmation/` に Python 3.12 ランタイムの handler 実装
- [ ] handler ロジック：`event` から sub / email / name 取得 → DB に UPSERT（users.id = sub） → `cognito-idp:AdminAddUserToGroup` で USER グループ付与
- [ ] DB アクセスは VPC 経由（Lambda VPC 設定）+ Secrets Manager から接続情報取得
- [ ] `infra/terraform/modules/cognito/lambda/pre_token/` に Python 3.12 ランタイムの handler 実装
- [ ] handler ロジック：`event.request.userAttributes.email` が `@colobiz.co.jp` で終わるか検証 → 違反なら例外で拒否
- [ ] それぞれに pytest の単体テストを `apps/api/tests/lambda/` に追加
- [ ] CloudWatch Logs で Lambda 実行ログが出ることを確認

### D. `.env.example` / 設定反映

- [ ] root `.env.example` に Auth セクションを更新（マスター設計書 §14.3 / ST0-1 と整合）
- [ ] `LLM_ROUTES_FILE` セクションと並列で配置
- [ ] 値はプレースホルダ（実値は Secrets Manager と SSM）

### E. ドキュメント

- [ ] `docs/runbook/auth-setup.md` を新規作成し、以下を記述
  - GCP OAuth クライアント作成手順（スクショ込み、人間担当）
  - Cognito + IdP の構造図（簡易）
  - 初回ユーザー作成フローの説明
  - 既存ユーザーのロール昇格手順（コンソール / AWS CLI）
  - ロールバック手順（federation を一時停止する手順）
  - 退職者処理（Google Workspace で停止 → Cognito 側 `AdminUserGlobalSignOut`）
  - トラブルシューティング（よくある redirect URI ミス、属性マッピング不整合）
- [ ] `docs/runbook/auth-setup.md` へのリンクを root `README.md` に追加

### F. PR / 運用

- [ ] PR テンプレに従い、CLAUDE.md / AGENTS.md 規約に違反していないことをセルフチェック
- [ ] AIレビュー（GPT / Gemini）を必ず通す。**Bedrock/Claude で実装するなら、レビューは Azure OpenAI または Vertex AI のみ**（CLAUDE.md §9.4）
- [ ] `terraform plan` の出力を PR に貼る
- [ ] STG 環境での Hosted UI 動作確認のスクショを PR に貼る
- [ ] **マージ後ブランチを削除しない**（CLAUDE.md §12.1）

---

## 想定実装内容（概要レベル）

### A. GCP コンソール手順（人間担当）

1. https://console.cloud.google.com/ にログイン（Workspace 管理者アカウント）
2. プロジェクト「colobiz-ai-workspace」（または既存の社内プロジェクト）を選択
3. APIs & Services → OAuth consent screen
   - User Type: **Internal**
   - App name: `Colobiz AI Workspace (STG)` / `Colobiz AI Workspace`
   - Support email: 宮本さん or 管理用
   - Authorized domains: `colobiz.co.jp`
   - Developer contact: 管理用メール
   - Scopes: `openid` / `email` / `profile`
4. APIs & Services → Credentials → Create Credentials → **OAuth client ID**
   - Application type: **Web application**
   - Name: `Colobiz AI Workspace - STG` / `... - Prod`
   - Authorized JavaScript origins:
     - `https://coloos-stg.auth.ap-northeast-1.amazoncognito.com`（Hosted UI、Cognito provided）
   - Authorized redirect URIs:
     - `https://coloos-stg.auth.ap-northeast-1.amazoncognito.com/oauth2/idpresponse`
5. 発行された Client ID / Client Secret を AWS Secrets Manager に保存
   - シークレット名：`cognito/google-oauth/stg`（および `prod`）
   - 値：`{ "client_id": "...", "client_secret": "..." }`
6. STG / Prod は別の OAuth クライアントとして発行する（環境分離）

### B. Terraform モジュール構造

```
infra/terraform/modules/cognito/
├─ main.tf              # User Pool / IdP / Client / Domain / Groups
├─ lambda.tf            # PostConfirmation / PreTokenGen
├─ iam.tf               # Lambda 用 IAM ロール
├─ outputs.tf
├─ variables.tf
├─ ssm.tf               # SSM Parameter 書き出し
└─ lambda/
    ├─ post_confirmation/
    │   ├─ handler.py
    │   └─ requirements.txt
    └─ pre_token/
        ├─ handler.py
        └─ requirements.txt
```

### C. Terraform 主要リソース（抜粋）

```hcl
resource "aws_cognito_user_pool" "main" {
  name = "coloos-${var.env}"
  auto_verified_attributes = ["email"]

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  lambda_config {
    post_confirmation     = aws_lambda_function.post_confirmation.arn
    pre_token_generation  = aws_lambda_function.pre_token.arn
  }

  account_recovery_setting {
    recovery_mechanism { name = "verified_email" priority = 1 }
  }
}

resource "aws_cognito_identity_provider" "google" {
  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id        = jsondecode(data.aws_secretsmanager_secret_version.google.secret_string)["client_id"]
    client_secret    = jsondecode(data.aws_secretsmanager_secret_version.google.secret_string)["client_secret"]
    authorize_scopes = "openid email profile"
  }

  attribute_mapping = {
    email       = "email"
    name        = "name"
    given_name  = "given_name"
    family_name = "family_name"
    picture     = "picture"
    username    = "sub"
  }
}

resource "aws_cognito_user_pool_client" "web" {
  user_pool_id  = aws_cognito_user_pool.main.id
  name          = "coloos-${var.env}-web"

  generate_secret              = false
  callback_urls                = var.callback_urls
  logout_urls                  = var.logout_urls
  allowed_oauth_flows          = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes         = ["openid", "email", "profile"]
  supported_identity_providers = ["Google"]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]
  prevent_user_existence_errors = "ENABLED"

  depends_on = [aws_cognito_identity_provider.google]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "coloos-${var.env}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_group" "user" {
  name         = "USER"
  user_pool_id = aws_cognito_user_pool.main.id
  precedence   = 30
}

resource "aws_cognito_user_group" "approver" {
  name         = "APPROVER"
  user_pool_id = aws_cognito_user_pool.main.id
  precedence   = 20
}

resource "aws_cognito_user_group" "admin" {
  name         = "ADMIN"
  user_pool_id = aws_cognito_user_pool.main.id
  precedence   = 10
}
```

### D. PostConfirmation Lambda（handler.py）

```python
import json
import os
import boto3
import psycopg
from psycopg.rows import dict_row

cognito = boto3.client("cognito-idp")
secrets = boto3.client("secretsmanager")

def _db_url() -> str:
    sec = secrets.get_secret_value(SecretId=os.environ["DB_SECRET_ARN"])
    creds = json.loads(sec["SecretString"])
    return f"postgresql://{creds['username']}:{creds['password']}@{creds['host']}:{creds['port']}/{creds['dbname']}"

def handler(event, context):
    user_pool_id = event["userPoolId"]
    sub = event["request"]["userAttributes"]["sub"]
    email = event["request"]["userAttributes"]["email"]
    name = event["request"]["userAttributes"].get("name", email.split("@")[0])

    with psycopg.connect(_db_url(), row_factory=dict_row) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO users (id, email, name, role, is_active, created_at, updated_at)
                VALUES (%s, %s, %s, 'USER', TRUE, now(), now())
                ON CONFLICT (id) DO UPDATE SET email=EXCLUDED.email, name=EXCLUDED.name, updated_at=now()
                """,
                (sub, email, name),
            )

    cognito.admin_add_user_to_group(
        UserPoolId=user_pool_id,
        Username=event["userName"],
        GroupName="USER",
    )
    return event
```

### E. Pre-Token Generation Lambda（handler.py）

```python
import os

ALLOWED_DOMAIN = os.environ.get("ALLOWED_EMAIL_DOMAIN", "colobiz.co.jp")

def handler(event, context):
    email = event["request"]["userAttributes"].get("email", "")
    if not email.endswith(f"@{ALLOWED_DOMAIN}"):
        raise Exception(f"Sign-in restricted to @{ALLOWED_DOMAIN}")
    # 必要に応じて claims を override（Phase 1ではそのまま素通し）
    return event
```

### F. SSM Parameter 書き出し

```hcl
resource "aws_ssm_parameter" "user_pool_id" {
  name  = "/coloos/${var.env}/cognito/user_pool_id"
  type  = "String"
  value = aws_cognito_user_pool.main.id
}
resource "aws_ssm_parameter" "client_id" {
  name  = "/coloos/${var.env}/cognito/client_id"
  type  = "String"
  value = aws_cognito_user_pool_client.web.id
}
resource "aws_ssm_parameter" "hosted_ui_domain" {
  name  = "/coloos/${var.env}/cognito/hosted_ui_domain"
  type  = "String"
  value = "${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com"
}
```

### G. `.env.example` 更新内容

```env
# Auth (Cognito + Google Workspace IdP)
COGNITO_REGION=ap-northeast-1
COGNITO_USER_POOL_ID=...                     # SSMから読み込み可（/coloos/{env}/cognito/user_pool_id）
COGNITO_CLIENT_ID=...                        # 同上 /coloos/{env}/cognito/client_id
COGNITO_HOSTED_UI_DOMAIN=https://coloos-stg.auth.ap-northeast-1.amazoncognito.com
COGNITO_OAUTH_REDIRECT_SIGNIN=http://localhost:3000/api/auth/callback/cognito
COGNITO_OAUTH_REDIRECT_SIGNOUT=http://localhost:3000/

# Google IdP（Cognito 側で参照、Local 開発で必要なケースのみ）
GOOGLE_OAUTH_CLIENT_ID=...                   # GCP コンソールで発行
GOOGLE_OAUTH_CLIENT_SECRET=...               # Secrets Manager 推奨

# ドメイン制限
ALLOWED_EMAIL_DOMAIN=colobiz.co.jp
```

### H. `docs/runbook/auth-setup.md` の章立て

1. 構成概要（図）
2. 事前準備（GCP プロジェクト・AWS アカウントの権限）
3. GCP OAuth クライアント作成手順（手動）
4. Secrets Manager への投入
5. Terraform 適用手順
6. 動作確認
7. ユーザーのロール昇格手順
8. 退職者処理
9. ロールバック
10. トラブルシューティング

---

## 想定テスト

| No | 観点 | 操作 | 期待結果 |
|---|---|---|---|
| 1 | Terraform plan | `terraform plan` (envs/stg) | 差分のみ、エラーなし |
| 2 | Terraform apply | `terraform apply` | User Pool / IdP / Client / Domain / Groups / Lambda 全て作成 |
| 3 | Hosted UI 表示 | Hosted UIの URL にブラウザでアクセス | Google ログインボタンのみ表示、メール+パスワードのフォームは出ない |
| 4 | サインイン正常系 | `xx@colobiz.co.jp` でサインイン | 成功、IDトークン発行 |
| 5 | DB INSERT | サインイン後 `users` テーブル確認 | sub / email / name が登録され、role='USER' |
| 6 | グループ付与 | サインイン後 IDトークン decode | `cognito:groups` に `USER` が含まれる |
| 7 | ドメイン制限 | `xx@gmail.com` でサインイン試行 | Pre-Token Generation Lambda が拒否し、Hosted UI にエラー表示 |
| 8 | ロール昇格 | AWS CLI で `admin-add-user-to-group ADMIN` | 次のサインイン or リフレッシュ後、`cognito:groups` に `ADMIN` が追加 |
| 9 | サインアウト | apps/web ログアウト → `/oauth2/logout` リダイレクト | セッションが切れる |
| 10 | Lambda 単体 | `pytest apps/api/tests/lambda/` | PostConfirmation / PreTokenGeneration の単体テストパス |
| 11 | CloudTrail | サインインを CloudTrail で確認 | Cognito イベントが記録 |
| 12 | SSM 出力 | `aws ssm get-parameter --name /coloos/stg/cognito/user_pool_id` | 値が返る |
| 13 | 退職者処理 | Workspace で対象アカウント停止 → サインイン試行 | エラーで拒否される |
| 14 | 監査 | PostConfirmation Lambda のログを CloudWatch で確認 | INSERT / AddUserToGroup が記録 |

---

## 関連リンク

- マスター設計書 §8 認証・認可設計
- STEP 0 詳細設計書 §11 認証基盤 / §17 Issue一覧（ST0-6）
- ST0-3：Terraform スケルトン（依存）
- ST0-11：apps/web + apps/api での実装（後続）
- CLAUDE.md §9（Adapter経由）/ §12（禁止事項）
- AGENTS.md §2（Claude Code 担当範囲）

---

## 優先度・期限

- 優先度：**最高**（後続のST0-11、業務AI、Memory全般をブロック）
- 期限：ST0-3 完了から3営業日以内

---

## 役割分担（Claude Code × 人間オペレーター）

| 担当 | タスク |
|---|---|
| **人間（宮本）** | A. GCP コンソールでの OAuth クライアント発行、Secrets Manager への登録、OAuth 同意画面の Internal 設定 |
| **Claude Code** | B〜E. Terraform モジュール / Lambda / SSM / `.env.example` 更新 / `docs/runbook/auth-setup.md` 作成 |
| **AIレビュー（GPT / Gemini）** | Terraform / Lambda / handler ロジックのクロスレビュー |
| **人間（宮本）** | STG での動作確認（実サインイン）、PR の最終承認 |

---

## リスクと対応

| リスク | 影響 | 対応 |
|---|---|---|
| GCP OAuth 同意画面の Internal 設定が外れる | 高 | レビュー時に必ず確認、`runbook` に明記 |
| Cognito Hosted UI の redirect URI ミスでループ | 中 | STG では `http://localhost:3000` も追加し、ローカル開発もテスト可能に |
| Pre-Token Generation Lambda が落ちると全員サインイン不可 | 高 | dead letter queue 設定、デプロイ前に必ず単体テスト |
| PostConfirmation Lambda の DB INSERT が失敗 | 中 | リトライ・冪等性（ON CONFLICT DO UPDATE）で対処、CloudWatch alarmで検知 |
| Google OAuth Client Secret 漏洩 | 高 | Secrets Manager のローテーション、Terraform state 暗号化 |
| 属性マッピングの不一致でユーザー識別不能 | 中 | `username = sub` を厳守、デバッグログを Pre-Token Generation で出す |

---

## 補足・注意事項

- カスタムドメイン（例 `auth.colobiz-aiws.example`）の利用は別Issueで対応。Phase 1 では Cognito 提供ドメインで開始する
- WAF を Hosted UI 前に置くかは別Issue（STG では不要、Prod 対応時に検討）
- `prevent_user_existence_errors = "ENABLED"` を設定し、ユーザー列挙攻撃を回避
- ローカル開発で federation をフル動作させたい場合は localhost を redirect URI に追加（`runbook` に手順記載）
- Phase 1 では MFA は federation 側（Google Workspace）で担保する。Cognito 側の MFA は無効でOK

---

**Cowork から Claude Code への申し送り**

このIssueは **Multi-AI Verificationが効くケース** です。Terraform / Lambda の組み合わせはハルシネーションが起きやすい領域なので、必ず GPT または Gemini のレビューを通してください。Claude Code 自身のセルフレビューだけで PR を上げないでください（CLAUDE.md §9.4）。

GCP 側の作業は宮本さんが先に終わらせ、Secrets Manager に値を入れてから Terraform apply の流れで進めます。GCP 作業の証跡はスクショで PR に添付してください。
