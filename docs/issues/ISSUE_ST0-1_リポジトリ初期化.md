# [ST0-1] リポジトリ初期化（モノレポ＋設定ファイル＋憲法配置）

> 親：Phase 1 STEP 0 詳細設計書 §2 / §3 / §4 / §15
> リポジトリ：https://github.com/Colo-bot05/coloOS
> ブランチ命名：`feature/ST0-1-init-monorepo`
> 想定工数：1日

## 背景（なぜやるか）

Colobiz AI Workspace Phase 1 を実装するための土台となるモノレポを初期化する。これがないと以降のすべての Issue（ST0-2 以降、Memory 系、業務AI系）を着手できない。CLAUDE.md / AGENTS.md という「実装AIの憲法」をリポジトリ直下に配置し、Claude Code が常に参照できる状態を作ることがゴール。

## 目的

- モノレポ（pnpm workspace + poetry）の最小骨格を作成する
- 主要な設定ファイル（`pnpm-workspace.yaml` / `package.json` / `.gitignore` / `.env.example` / `.pre-commit-config.yaml`）を配置する
- `apps/`、`packages/`、`infra/`、`.github/`、`docs/`、`scripts/` のディレクトリを切る
- `CLAUDE.md` / `AGENTS.md` をリポジトリ直下に配置する
- 初期 `README.md` で開発者がこのリポジトリの役割と次のステップを把握できる状態にする

## 受け入れ条件（Definition of Done）

- [ ] STEP 0 詳細設計書 §2.1 のディレクトリツリー通りに `apps/`, `packages/`, `infra/`, `.github/`, `docs/`, `scripts/` が存在する（中身は空でも `.gitkeep` 配置）
- [ ] `pnpm-workspace.yaml` で `apps/*` と `packages/*` がワークスペースに登録されている
- [ ] root `package.json` が存在し、`pnpm install` が成功する（依存ゼロでも可）
- [ ] root `package.json` に `lint` / `format` / `test` / `gen:api-types` のスクリプトが存在する（中身は雛形でも可）
- [ ] `.gitignore` が `node_modules/`, `.next/`, `__pycache__/`, `.venv/`, `.env*`, `dist/`, `build/`, `coverage/`, `.terraform/`, `*.tfstate*`, `.DS_Store` を含む
- [ ] `.env.example` が STEP 0 設計書 §14.3 のキーを最低限含む（値は空 or プレースホルダ）
- [ ] `CLAUDE.md` / `AGENTS.md` が outputs から取り込まれリポジトリ直下に配置されている
- [ ] `README.md` がプロジェクト概要・前提・初期セットアップ・関連ドキュメントへのリンクを含む
- [ ] `.pre-commit-config.yaml` 雛形が存在し、`detect-secrets` または `gitleaks` のフックが有効
- [ ] `docs/design/` に既存の3つの設計書（マスター・Memory・STEP0）の docx を配置するための `README.md` プレースホルダが置かれている
- [ ] `git commit` 時に pre-commit が走り、シークレット検出フックがヒットしないことをローカルで確認
- [ ] PR が `staging` 向きで作成されている（`main` 向きではない）
- [ ] PR テンプレートがまだ無い段階なので、PR 本文は CLAUDE.md §5.4 の項目を手動で埋める
- [ ] CLAUDE.md §12 の禁止事項に該当する記述・ファイルがない

## 想定実装内容（概要レベル）

### 作成するディレクトリ

```
coloOS/
├─ apps/
│   ├─ web/.gitkeep
│   └─ api/.gitkeep
├─ packages/
│   ├─ prompts/.gitkeep
│   └─ schemas/.gitkeep
├─ infra/
│   ├─ terraform/.gitkeep
│   └─ docker/.gitkeep
├─ .github/
│   ├─ workflows/.gitkeep
│   └─ ISSUE_TEMPLATE/.gitkeep
├─ docs/
│   ├─ design/README.md  # 設計書置き場の説明
│   └─ runbook/.gitkeep
├─ scripts/.gitkeep
├─ CLAUDE.md
├─ AGENTS.md
├─ README.md
├─ pnpm-workspace.yaml
├─ package.json
├─ .gitignore
├─ .env.example
└─ .pre-commit-config.yaml
```

### 主要ファイルの最小内容

**`pnpm-workspace.yaml`**

```yaml
packages:
  - "apps/*"
  - "packages/*"
```

**`package.json`（root）**

```json
{
  "name": "coloos",
  "version": "0.0.0",
  "private": true,
  "engines": { "node": ">=22", "pnpm": ">=9" },
  "scripts": {
    "lint": "echo 'Lint placeholder — implemented in ST0-9/ST0-22'",
    "format": "echo 'Format placeholder'",
    "test": "echo 'Test placeholder'",
    "gen:api-types": "echo 'Type generation placeholder — implemented in ST0-21'"
  }
}
```

**`.gitignore`**

```
# Node / pnpm
node_modules/
.pnpm-store/
.next/
dist/
build/
coverage/

# Python
__pycache__/
*.py[cod]
.venv/
.pytest_cache/
.mypy_cache/
.ruff_cache/

# Env
.env
.env.local
.env.*.local

# Terraform
.terraform/
*.tfstate
*.tfstate.*
*.tfplan

# IDE / OS
.DS_Store
.vscode/*
!.vscode/settings.example.json
.idea/

# Misc
*.log
```

**`.env.example`**

STEP 0 設計書 §14.3 の内容をコピーして配置（値はプレースホルダ）。
具体キー：

- 共通: `ENV` / `LOG_LEVEL`
- DB: `DATABASE_URL` / `REDIS_URL`
- Auth (Cognito + Google IdP): `COGNITO_REGION` / `COGNITO_USER_POOL_ID` / `COGNITO_CLIENT_ID` / `COGNITO_HOSTED_UI_DOMAIN` / `COGNITO_OAUTH_REDIRECT_SIGNIN` / `COGNITO_OAUTH_REDIRECT_SIGNOUT` / `GOOGLE_OAUTH_CLIENT_ID` / `GOOGLE_OAUTH_CLIENT_SECRET`（本番はSecrets Manager） / `ALLOWED_EMAIL_DOMAIN=colobiz.co.jp`
- LLM: `BEDROCK_REGION` / `AZURE_OPENAI_ENDPOINT` / `AZURE_OPENAI_API_KEY` / `AZURE_OPENAI_API_VERSION` / `GCP_PROJECT_ID` / `VERTEX_LOCATION` / `LLM_ROUTES_FILE`

**`.pre-commit-config.yaml`**

```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
        args: ["--maxkb=1024"]
```

**`README.md`**

最低限の内容：

- プロジェクト名・概要（Colobiz AI Workspace Phase 1）
- 開発前に読むドキュメント（CLAUDE.md / AGENTS.md / docs/design/）
- 前提（Node 22 / pnpm 9 / Python 3.12 / poetry 1.8 / Docker）
- 初期セットアップ手順（`pnpm install` まで。`apps/web` / `apps/api` の起動は ST0-9 / ST0-10 で実装後に追記）
- ライセンス（社内利用、無断公開禁止）

**`CLAUDE.md` / `AGENTS.md`**

`outputs/CLAUDE.md` / `outputs/AGENTS.md` をそのまま配置。文言の改変はしない（変更は別Issueで）。

**`docs/design/README.md`**

設計書置き場であること、ファイル一覧（マスター設計書 / Memory機構 詳細 / STEP 0 詳細）の予定を記載。docx本体の配置は ST0-26 で行うため、ここではプレースホルダ。

## 想定テスト（概要レベル）

| No | 観点 | 操作 | 期待結果 |
|---|---|---|---|
| 1 | 構成 | `tree -L 2` で確認 | DoD のディレクトリ構成と一致 |
| 2 | 依存解決 | `pnpm install` | エラーなしで完了 |
| 3 | スクリプト | `pnpm run lint` / `format` / `test` | プレースホルダ出力で成功 |
| 4 | gitignore | `.env.local` 作成→`git status` | 表示されない |
| 5 | pre-commit | サンプル AWS キー文字列を含むファイルを add → commit | gitleaksがブロック |
| 6 | 憲法配置 | リポジトリ直下に `CLAUDE.md` `AGENTS.md` 存在 | 内容が outputs と完全一致 |
| 7 | README | 開発者が初見で次のステップを把握可能 | リンク・前提・セットアップが明記 |

## 関連リンク

- マスター設計書（Phase 1 開発設計書 兼 手順書）
- STEP 0 詳細設計書 §2 / §3 / §4 / §15
- CLAUDE.md
- AGENTS.md

## 優先度・期限

- 優先度：**最高**（後続のST0-2以降をブロックする）
- 期限：着手から1営業日以内

## 補足・注意事項

- このIssueは「土台のみ」。`apps/web` / `apps/api` の中身は別Issue（ST0-9 / ST0-10）で実装する
- Terraform / Dockerfile も別Issue（ST0-3 以降）
- **マージ後ブランチを削除しない**（CLAUDE.md §12.1）
- PR向き先は `staging`（`main` ではない）
- pre-commit を有効化したら `pre-commit install` をローカルで実行する手順を README に書く

---

**Cowork から Claude Code への申し送り**

CLAUDE.md と AGENTS.md は本リポジトリにとって最重要ドキュメントです。配置時に **絶対に文言を改変しないでください**（誤字修正含む）。修正が必要と感じた場合は本 Issue 内ではなく、別 Issue を立ててPRしてください（CLAUDE.md §17・AGENTS.md §10 の改定ルール）。
