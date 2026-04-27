# Branch Protection Runbook

Colobiz AI Workspace の保護対象ブランチと設定ルール、適用手順、変更履歴を記録する。

## 保護対象ブランチ

| ブランチ | 役割 | デプロイ先 |
|---|---|---|
| `main` | 本番のメイン。リリース確定済み | 直接デプロイなし |
| `staging` | 次回リリース候補。`feature/*` のマージ先 | 直接デプロイなし |
| `release/stg` | STG デプロイブランチ | STG ECS（自動・ST0-5 以降） |
| `release/prod` | 本番デプロイブランチ | 本番 ECS（手動承認） |

## 必須設定（Phase 1 暫定）

各保護対象ブランチに**同一構造**で以下を適用する。

| 設定 | 値 | 根拠 |
|---|---|---|
| Require a pull request before merging | ON | CLAUDE.md §5 / §12.8 |
| Required approvals | **1** | Phase 1 初期。Phase 2 以降で 2 に引き上げ予定 |
| Dismiss stale pull request approvals when new commits are pushed | ON | コード変更後の旧 approval を無効化 |
| Require code owner reviews | OFF | CODEOWNERS は ST0-22 以降で整備 |
| Require status checks to pass before merging | OFF（暫定） | `ci` / `ai-review` は ST0-22 / ST0-23 で追加後に ON |
| Require branches to be up to date before merging | OFF（暫定） | 上記と連動 |
| Require conversation resolution before merging | ON | レビュー指摘の取りこぼし防止 |
| Allow force pushes | **OFF** | CLAUDE.md §12.8 |
| Allow deletions | **OFF** | CLAUDE.md §12.1 |
| Restrict who can push（restrictions） | （未設定） | Organization 化後に teams 単位で設定 |
| enforce_admins | **OFF（Phase 1 暫定）** | 後述「Phase 1 暫定運用：enforce_admins=false」節参照。Phase 1.5 で ON に戻す |

## リポジトリ設定

| 設定 | 値 | 根拠 |
|---|---|---|
| Default branch | `main` | デフォルト |
| **Automatically delete head branches** | **OFF（厳守）** | CLAUDE.md §12.1 — マージ後 feature ブランチを自動削除しない |

> ⚠️ **Automatically delete head branches を ON に変更することは今後一切受け付けない。** これは CLAUDE.md §12.1 違反防止の最重要設定。

## Phase 1 暫定運用：enforce_admins=false

理由：単独運用では PR 作成者（Colo-bot05）が自分の PR を Approve できない GitHub 標準仕様により、PR が承認待ちでブロックされる。Phase 1.5 で複数人運用に移行した際に true に戻す。

ただし以下の §12 規約は技術的バイパス可能でも厳守する：
- §12.1 ブランチ削除禁止
- §12.8 Force push 禁止 / 本番直接コミット禁止

これらの違反は技術的にではなく、CLAUDE.md / AGENTS.md の規約で禁じる。

復活タイミング：別の人間レビュアーが参加した時点で、上記の運用を見直し enforce_admins=true へ戻す（Phase 1.5 想定）。

## 適用手順（gh CLI）

各ブランチに対して以下を実行：

```bash
REPO=Colo-bot05/coloOS

for BRANCH in main staging release/stg release/prod; do
  gh api "repos/${REPO}/branches/${BRANCH}/protection" --method PUT --input - <<'JSON'
{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
JSON
done
```

`release/stg` / `release/prod` のように `/` を含むブランチ名は URL エンコード不要（gh api が処理）。

## 確認手順

```bash
REPO=Colo-bot05/coloOS

for BRANCH in main staging release/stg release/prod; do
  echo "=== ${BRANCH} ==="
  gh api "repos/${REPO}/branches/${BRANCH}/protection" --jq '{
    enforce_admins: .enforce_admins.enabled,
    required_pr_reviews: .required_pull_request_reviews.required_approving_review_count,
    allow_force_pushes: .allow_force_pushes.enabled,
    allow_deletions: .allow_deletions.enabled,
    required_conversation_resolution: .required_conversation_resolution.enabled
  }'
done

# 自動削除 OFF の確認
gh api "repos/${REPO}" --jq '.delete_branch_on_merge'
```

すべて `enforce_admins: false`（Phase 1 暫定）、`allow_force_pushes: false`、`allow_deletions: false`、`required_conversation_resolution: true` で揃っていれば OK。`delete_branch_on_merge` は `false`。

## 変更時の注意事項

- `gh api ... --method PUT` は branch protection の **全項目を上書き**する（PATCH 的に部分更新しない）。一部項目だけ変更したいときも、本書の JSON を全部入れて差分箇所だけ書き換えること。
- 設定変更は必ず本書の「設定変更履歴」に追記する。GitHub UI から手動で変更した場合も含めて記録する。
- `enforce_admins` を OFF にする変更は**禁止**（管理者バイパスの抜け穴になる）。
- `allow_deletions` を ON にする変更は**禁止**（CLAUDE.md §12.1 違反）。

## 設定変更履歴

| 日付 | 変更内容 | Issue / PR | 実施者 |
|---|---|---|---|
| 2026-04-27 | 初回適用（4 ブランチ、enforce_admins=true） | #3 | Claude Code（`Colo-bot05` 認証） |
| 2026-04-28 | enforce_admins を true → false へ変更（Phase 1 暫定。単独運用で PR 作成者が self-approve できない GitHub 仕様の回避） | #3 | Claude Code（`Colo-bot05` 認証） |

> 設定変更があれば必ず本表に追記する。

## 関連ドキュメント

- [CLAUDE.md §6](../../CLAUDE.md) — ブランチ運用とデプロイフロー
- [CLAUDE.md §12](../../CLAUDE.md) — 禁止事項
- [AGENTS.md §6.3](../../AGENTS.md) — エージェント別禁止事項
- [getting-started.md](./getting-started.md) — 初回セットアップ手順
