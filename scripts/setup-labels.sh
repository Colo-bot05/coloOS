#!/usr/bin/env bash
# =============================================================================
# Colobiz AI Workspace — 標準ラベル整備スクリプト
# =============================================================================
# 用途: GitHub リポジトリの標準ラベル（type:* / status:* / priority:* / step:* /
#       area:* / agent:* / needs:*）を一括で作成または更新する。
# 実行: bash scripts/setup-labels.sh
# 前提: gh CLI がインストール・認証済（repo スコープ以上）
# 規約: CLAUDE.md §13 / AGENTS.md / ISSUE_ST0-2 §4
# =============================================================================
set -euo pipefail

REPO="${REPO:-Colo-bot05/coloOS}"

create() {
  gh label create "$1" --color "$2" --description "$3" --repo "$REPO" 2>/dev/null \
    || gh label edit "$1" --color "$2" --description "$3" --repo "$REPO"
}

# Type
create "type:feature"  "1f883d" "新機能・改善"
create "type:bug"      "d73a4a" "バグ修正"
create "type:infra"    "5319e7" "インフラ変更"
create "type:docs"     "0075ca" "ドキュメント"
create "type:refactor" "fbca04" "リファクタリング"
create "type:hotfix"   "b60205" "緊急修正"

# Status
create "status:triage"      "ededed" "確認待ち"
create "status:ready"       "0e8a16" "着手可能"
create "status:in-progress" "fbca04" "実装中"
create "status:blocked"     "d93f0b" "ブロック中"
create "status:review"      "1d76db" "レビュー中"

# Priority
create "priority:highest" "b60205" "最高"
create "priority:high"    "d93f0b" "高"
create "priority:medium"  "fbca04" "中"
create "priority:low"     "0e8a16" "低"

# Phase / Step
create "step:0"  "5319e7" "STEP 0（土台）"
create "step:1"  "5319e7" "STEP 1（認証）"
create "step:2"  "5319e7" "STEP 2（通常チャットMVP）"

# Memory
create "area:memory" "8b5cf6" "Memory機構"

# Areas
create "area:web"        "c5def5" "apps/web"
create "area:api"        "c5def5" "apps/api"
create "area:infra"      "c5def5" "infra/"
create "area:llm"        "c5def5" "LLM Adapter/Router"
create "area:auth"       "c5def5" "認証"
create "area:ci-cd"      "c5def5" "CI/CD"

# Agent operation
create "agent:autorun"  "ff6b6b" "将来の自動実装エージェント対象（Phase 2以降）"

# Special
create "needs:design"   "ededed" "設計書が必要"
create "needs:human"    "ededed" "人間判断が必要"

echo "---"
echo "Done. ラベル一覧:"
gh label list --repo "$REPO" --limit 100
