# Getting Started

新しい開発者・新しいエージェントが Colobiz AI Workspace のリポジトリに最初に触れるときの手順。

## 0. 前提

- macOS / Linux 想定（Windows は WSL2 推奨）
- Homebrew（macOS）または apt 等のパッケージマネージャ
- Git / GitHub アカウント（Colobiz ドメインのメールアドレスで紐付け）

## 1. 必須ツールのインストール

| ツール | 推奨インストール |
|---|---|
| Node.js 22 以上 | `brew install node` |
| Corepack（pnpm 取得用） | `brew install corepack` |
| Python 3.12.x | `brew install pyenv && pyenv install 3.12.7 && pyenv global 3.12.7` |
| Poetry 1.8 以上 | `curl -sSL https://install.python-poetry.org \| python3 -` |
| Docker / Docker Compose | Docker Desktop |
| pre-commit | `brew install pre-commit` または `pip install pre-commit` |
| GitHub CLI（gh） | `brew install gh` |

> ⚠️ Node を Homebrew で入れた場合、corepack は別パッケージ（`brew install corepack`）。Node 同梱とは限らないので注意（ST0-1 で実際に発生）。

## 2. リポジトリの取得

```bash
# GitHub CLI 認証（初回のみ）
gh auth login

# クローン
gh repo clone Colo-bot05/coloOS
cd coloOS
```

## 3. git identity の初回設定（**必須**）

ST0-1 の Bootstrap commit が無記名の自動値で記録された経緯から、リポジトリで作業する前に必ず identity を設定する。これを怠ると commit が GitHub アカウントに紐付かず「Unverified」表示になる。

```bash
# グローバル設定（推奨）
git config --global user.name "あなたの本名"
git config --global user.email "your.name@colobiz.co.jp"

# このリポジトリだけに別 identity を使いたい場合（オプション）
git config user.name "..."
git config user.email "..."
```

確認：

```bash
git log -1 --format='%an <%ae>'
# → "Yusuke Miyamoto <m.miyamoto@colobiz.co.jp>" のような形になればOK
```

## 4. ローカルブランチへの upstream tracking 設定（**重要**）

`staging` / `release/stg` / `release/prod` を**初めてローカルにチェックアウトする際**は、必ず origin との tracking を設定する。これを怠ると `git pull` が「remote 不明」エラーになる（ST0-1→ST0-2 移行時に実際に発生）。

```bash
git fetch origin

# 推奨: -b で作成と同時に origin/* を tracking
git checkout -b staging      origin/staging
git checkout -b release/stg  origin/release/stg
git checkout -b release/prod origin/release/prod

# 既にローカルにブランチが存在し、tracking が無い場合
git branch --set-upstream-to=origin/staging      staging
git branch --set-upstream-to=origin/release/stg  release/stg
git branch --set-upstream-to=origin/release/prod release/prod
```

確認：

```bash
git branch -vv
# → ブランチ名の右に [origin/<branch>] が表示されれば tracking 済み
```

## 5. 初回セットアップ

```bash
# pnpm を Corepack 経由で取得（リポ固定バージョン）
corepack enable
corepack prepare pnpm@9 --activate

# 依存インストール
pnpm install

# pre-commit フックを有効化（gitleaks 等のシークレット検出）
pre-commit install

# 一度全フックを走らせて緑になることを確認
pre-commit run --all-files
```

`apps/web` / `apps/api` の起動・DB マイグレーション等は ST0-9 / ST0-10 の実装後に追記される。

## 6. Issue 起点の作業フロー

```bash
# 1. 作業 Issue を立てる（GitHub UI または gh issue create）
gh issue create --label "type:feature,priority:medium,area:api"
# → 出力された Issue 番号を控える

# 2. staging を最新化して feature ブランチを切る
git checkout staging
git pull --ff-only
git checkout -b feature/ISSUE番号-概要

# 3. 実装＋テスト＋小粒コミット
# 4. push
git push -u origin feature/ISSUE番号-概要

# 5. PR 作成（base=staging）
gh pr create --base staging
```

詳細は [CLAUDE.md §5・§6](../../CLAUDE.md) を参照。

## 7. Claude Code との作業

- Claude Code を起動すると `CLAUDE.md` / `AGENTS.md` / 直下のドキュメントを自動読み込みする
- **Issue 起点で作業を依頼する**（Issue が無いと CLAUDE.md §12.2 違反）
- 重要なフェーズ境界（Issue→ブランチ作成→実装→PR→マージ）では立ち止まり、人間の確認を求める運用を推奨
- 完了時に PR が `staging` 向きで作成されているか必ず確認

## 8. 困ったときの参照先

| トピック | ドキュメント |
|---|---|
| 全体規約 | [../../CLAUDE.md](../../CLAUDE.md) |
| エージェント運用 | [../../AGENTS.md](../../AGENTS.md) |
| クロスAIレビュー | [../../CROSS_REVIEW_TEMPLATES.md](../../CROSS_REVIEW_TEMPLATES.md) |
| ブランチ保護 | [./branch-protection.md](./branch-protection.md) |
| 設計書 | [../design/](../design/) |
| Issue ドラフト | [../issues/](../issues/) |
| ラベル運用 | `scripts/setup-labels.sh` の実行結果 / [README.md](../../README.md) のラベル運用セクション |

## 9. よくある詰まり

| 症状 | 原因 / 対処 |
|---|---|
| `corepack: command not found` | Homebrew Node 同梱でない場合がある。`brew install corepack` を実行 |
| `git pull` が "no tracking information" | 共有ブランチで `--set-upstream-to=origin/...` を設定（§4 参照） |
| `pnpm: command not found` | `corepack enable && corepack prepare pnpm@9 --activate` を実行 |
| pre-commit の deprecated stage names 警告 | `pre-commit autoupdate` を実行（ST0-2 で実施済み。今後は `autoupdate` を定期的に） |
| commit が "Unverified" 表示 | git identity（特に email）が GitHub アカウントと不一致。§3 参照 |
| PR を staging 以外に作ってしまった | `gh pr edit <番号> --base staging` で base 変更可能 |
