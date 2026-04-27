# Colobiz AI Workspace

Colobiz 社員のための社内 AI 共通基盤（Phase 1）。

## 概要

通常チャット・要件定義AI・資料作成AI・見積り補助AI・Backlog タスク化AI・レビューAI・社内 RAG・管理ダッシュボードを、**Memory 機構**と **Colobiz Decision Engine（思考OS）** を横断基盤として上に乗せる構成。

実装思想は **Spec-Driven × Multi-AI Verification by Design**：Bedrock(Claude) / Azure OpenAI(GPT) / Vertex AI(Gemini) を機能ごとに使い分け、実装と同じ Provider ではセルフレビューしない（CLAUDE.md §9.4）。

## 開発前に必ず読むドキュメント

実装に着手する前に、以下を **上から順に** 読んでください。

| ファイル | 役割 |
|---|---|
| [CLAUDE.md](./CLAUDE.md) | **実装AIの憲法**（最優先・全AI対象） |
| [AGENTS.md](./AGENTS.md) | エージェント別の運用ルール |
| [CROSS_REVIEW_TEMPLATES.md](./CROSS_REVIEW_TEMPLATES.md) | クロス AI レビューのテンプレート |
| [docs/runbook/getting-started.md](./docs/runbook/getting-started.md) | **初回セットアップ手順**（環境構築・git config・upstream tracking） |
| [docs/runbook/branch-protection.md](./docs/runbook/branch-protection.md) | ブランチ保護ルールと適用手順 |
| [docs/design/](./docs/design) | 機能別設計書（マスター / Memory / STEP0 / DecisionEngine の docx） |
| [docs/issues/](./docs/issues) | Issue ドラフト（ST0-1 〜 ST0-6） |

矛盾した指示が出たら、**CLAUDE.md > AGENTS.md > 設計書 > 個別の指示** の優先順位（AGENTS.md §0）。

## 前提環境

| カテゴリ | バージョン | 備考 |
|---|---|---|
| Node.js | **22 以上** | Next.js 15 / pnpm が要求 |
| pnpm | **9.x**（**Corepack 経由**で取得） | 後述の手順を参照 |
| Python | **3.12.x 必須** | 3.13 / 3.14 では未検証。**ST0-4 / ST0-10 等のバックエンド系 Issue 着手前に** pyenv で 3.12 を導入し、リポジトリ内で `pyenv local 3.12.x` を設定 |
| Poetry | **1.8 以上** | 同上、バックエンド系 Issue 着手前に導入 |
| Docker / Compose | 最新 | ローカル DB / Redis 起動用（ST0-3 以降） |
| pre-commit | 最新 | `pip install pre-commit` または `brew install pre-commit` |
| git | 任意 | identity（user.name / user.email）を Colobiz アカウントで設定済みであること（[getting-started.md §3](./docs/runbook/getting-started.md) 参照） |

> ⚠️ **Python バージョン警告**：`python3 --version` が 3.12 系でない場合、ST0-4 / ST0-10 などのバックエンド系 Issue は実装着手しないでください。CLAUDE.md §2 の固定バージョンを満たさないと環境差で詰まります。

## 初期セットアップ（短縮版）

```bash
# 1. Corepack を有効化し、リポジトリ固定バージョンの pnpm を取得
corepack enable
corepack prepare pnpm@9 --activate

# 2. ワークスペース全体の依存をインストール
pnpm install

# 3. pre-commit フックを有効化（gitleaks によるシークレット検出 + 標準フック）
pre-commit install
```

`apps/web` / `apps/api` のサーバ起動・DB マイグレーション等は ST0-9 / ST0-10 の実装後に追記される（現時点では空骨格のみ）。

> **初回セットアップで困ったら** [docs/runbook/getting-started.md](./docs/runbook/getting-started.md) を読んでください。git identity の設定、共有ブランチの upstream tracking、よくある詰まりを網羅しています。

## ディレクトリ構成

```
coloOS/
├─ apps/
│   ├─ web/        Next.js 15 (App Router) ← ST0-9 で実装
│   └─ api/        FastAPI ← ST0-10 で実装
├─ packages/
│   ├─ prompts/    共通プロンプト（YAML/Jinja2）
│   └─ schemas/    OpenAPI 生成型 / 共通型
├─ infra/
│   ├─ terraform/  ← ST0-3 〜
│   └─ docker/     ← ST0-3 〜
├─ .github/
│   ├─ workflows/  GitHub Actions（CI/CD・AIレビュー）
│   ├─ ISSUE_TEMPLATE/
│   └─ PULL_REQUEST_TEMPLATE.md
├─ docs/
│   ├─ design/     機能別設計書（docx）
│   ├─ issues/     Issue ドラフト
│   └─ runbook/    運用手順書（branch-protection / getting-started 等）
├─ scripts/        開発補助スクリプト（setup-labels.sh 等）
├─ CLAUDE.md       実装AI憲法
├─ AGENTS.md       エージェント別運用ルール
├─ CROSS_REVIEW_TEMPLATES.md  クロスAIレビューテンプレ
└─ README.md       ← 本ファイル
```

## 開発フロー（要約）

```
Issue 作成 → feature/* ブランチ（staging から派生） → 実装＋テスト
  → PR (向き先: staging) → AIレビュー（GPT/Gemini 並列）→ 人間レビュー
  → staging マージ → release/stg → STG ECS デプロイ → STG テスト
  → main → release/prod → 本番 ECS デプロイ（手動承認）
```

詳細は [CLAUDE.md §5・§6](./CLAUDE.md) を参照。

## ラベル運用

GitHub Issue / PR には**標準ラベル**（`type:*` / `status:*` / `priority:*` / `step:*` / `area:*` / `agent:*` / `needs:*`）を付ける運用です。標準ラベル一覧と作成スクリプトは [scripts/setup-labels.sh](./scripts/setup-labels.sh) にあります。

```bash
# リポジトリにラベルを一括作成（既存ラベルは色・説明を上書き更新）
bash scripts/setup-labels.sh

# 確認
gh label list --repo Colo-bot05/coloOS --limit 100
```

| カテゴリ | 例 | 用途 |
|---|---|---|
| `type:*` | `type:feature` / `type:bug` / `type:infra` / `type:docs` / `type:refactor` / `type:hotfix` | Issue / PR の種別 |
| `status:*` | `status:triage` / `status:ready` / `status:in-progress` / `status:blocked` / `status:review` | 進捗状態 |
| `priority:*` | `priority:highest` / `priority:high` / `priority:medium` / `priority:low` | 優先度 |
| `step:*` | `step:0` / `step:1` / `step:2` | Phase 1 STEP の対応 |
| `area:*` | `area:web` / `area:api` / `area:llm` / `area:auth` / `area:infra` / `area:ci-cd` / `area:memory` | 影響領域 |
| `agent:*` | `agent:autorun` | 自動実装エージェント対象（Phase 2 以降） |
| `needs:*` | `needs:design` / `needs:human` | 追加判断・追加成果物が必要 |

ラベルの追加・変更は [scripts/setup-labels.sh](./scripts/setup-labels.sh) を編集して PR を立ててください。

## ブランチ保護

`main` / `staging` / `release/stg` / `release/prod` の 4 ブランチに、**Required PR review = 1 / force push 禁止 / deletions 禁止 / enforce_admins=true** を適用しています。詳細・適用手順・変更履歴は [docs/runbook/branch-protection.md](./docs/runbook/branch-protection.md) を参照。

## ブランチ保全（CLAUDE.md §12.1 再掲）

- **マージ後も feature ブランチを削除しない**（local も remote も）
- リポジトリ設定 `Automatically delete head branches` は **OFF** を維持。ON にする変更は受け付けない
- ブランチ保護の `Allow deletions` は **OFF** で固定

## 主要な禁止事項（抜粋）

- マージ後にブランチを削除しない（CLAUDE.md §12.1）
- Issue なしでブランチ・PR を作らない（§12.2）
- シークレットをコードに書かない（§12.3）
- 外部 AI に社内コードを貼らない（§12.4）
- LLM Adapter / Memory / Decision Engine を迂回しない（§12.5 / §12.6 / §12.10）
- main / release/prod に直接 push しない・force push しない（§12.8）

完全なリストは [CLAUDE.md §12](./CLAUDE.md) を参照。

## ライセンス

社内利用に限る。**無断での公開・社外配布を禁止する。**

---

最終更新: 2026-04-27
