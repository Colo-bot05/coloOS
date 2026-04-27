# [ST0-2] GitHub テンプレ・ブランチ保護案・ラベル整備

> 親：Phase 1 STEP 0 詳細設計書 §2.3 / §13.3 / §17
> リポジトリ：https://github.com/Colo-bot05/coloOS
> ブランチ命名：`feature/ST0-2-github-templates-and-protection`
> 想定工数：0.5日
> 依存：ST0-1（リポジトリ初期化）

## 背景（なぜやるか）

ST0-1 でリポジトリ骨格は整ったが、Issue / PR テンプレ・ブランチ保護・ラベルが未整備。CLAUDE.md / AGENTS.md の規約を Issue / PR 単位で機械的に守らせるためには、**テンプレート＋ブランチ保護＋ラベル** の3点が揃って初めて機能する。Claude Code が次の Issue 以降を進める際に、これらが揃っていないと毎回手作業で規約を満たさせる必要があり、運用が崩れる。

## 目的

- Issue テンプレート（feature / bug / infra / docs）を整備する
- PR テンプレートを整備する（CLAUDE.md §5.4 / AGENTS.md §2.4 のフォーマットに準拠）
- ブランチ保護設定を「コード化された提案」として `docs/runbook/branch-protection.md` に記述する
- 標準ラベルセットを作成する（手動運用＋スクリプト両方を提供）
- ブランチ自動削除を OFF にする運用を README とドキュメントで明示する

## 受け入れ条件（Definition of Done）

- [ ] `.github/ISSUE_TEMPLATE/feature.yml` が存在し、CLAUDE.md §5.1 の項目（背景・目的・DoD・想定実装内容・想定テスト・関連リンク・優先度・期限）をフォームで含む
- [ ] `.github/ISSUE_TEMPLATE/bug.yml` が存在する（再現手順・期待結果・実際の結果・環境）
- [ ] `.github/ISSUE_TEMPLATE/infra.yml` が存在する（対象環境・変更内容・影響範囲・ロールバック手順）
- [ ] `.github/ISSUE_TEMPLATE/docs.yml` が存在する（対象ドキュメント・変更概要・影響）
- [ ] `.github/ISSUE_TEMPLATE/config.yml` で blank issues を無効化、Q&A は Discussions へ誘導
- [ ] `.github/PULL_REQUEST_TEMPLATE.md` が存在し、AGENTS.md §2.4 のフォーマットを完全に含む
- [ ] `docs/runbook/branch-protection.md` に以下の保護対象ブランチ・必須チェック・必須レビュアー・ブランチ自動削除OFFの設定が文書化されている
- [ ] `scripts/setup-labels.sh`（or `.ts`）で標準ラベルセットを作成できる
- [ ] 標準ラベル（後述）が GitHub 上に存在することを確認するチェックリストが README に追加
- [ ] `docs/runbook/branch-protection.md` の手順を実行し、`main` / `staging` / `release/stg` / `release/prod` のブランチ保護が有効化されていることをスクショで確認（PR本文に貼付）
- [ ] **リポジトリ Settings > General > Pull Requests > "Automatically delete head branches" が OFF** であることをスクショで確認（PR本文に貼付）
- [ ] CLAUDE.md §12.1（ブランチ削除禁止）と整合する運用が確認できる

## 想定実装内容（概要レベル）

### 1) Issue テンプレート（YAML フォーム形式）

**`.github/ISSUE_TEMPLATE/feature.yml`**

```yaml
name: 機能追加・改善
description: 新機能・機能改善のIssueを起票する
title: "[FEATURE] "
labels: ["type:feature", "status:triage"]
body:
  - type: textarea
    id: background
    attributes:
      label: 背景（なぜやるか）
      description: なぜこの機能が必要か。誰がどう困っているか
    validations: { required: true }
  - type: textarea
    id: goal
    attributes:
      label: 目的
      description: この Issue が完了したら何が達成されるか
    validations: { required: true }
  - type: textarea
    id: dod
    attributes:
      label: 受け入れ条件（Definition of Done）
      description: チェックリスト形式で
      placeholder: |
        - [ ] ...
        - [ ] ...
    validations: { required: true }
  - type: textarea
    id: implementation
    attributes:
      label: 想定実装内容（概要レベル）
      description: 主要なファイル/モジュール、APIエンドポイント、DB変更など
    validations: { required: true }
  - type: textarea
    id: tests
    attributes:
      label: 想定テスト（概要レベル）
      description: 単体・結合・E2E・受け入れの観点
    validations: { required: true }
  - type: textarea
    id: links
    attributes:
      label: 関連リンク
      description: 設計書・過去Issue・Slackスレッドなど
  - type: dropdown
    id: priority
    attributes:
      label: 優先度
      options: ["最高", "高", "中", "低"]
    validations: { required: true }
  - type: input
    id: deadline
    attributes:
      label: 期限（任意）
      placeholder: "YYYY-MM-DD"
```

**`.github/ISSUE_TEMPLATE/bug.yml`**

- 再現手順、期待結果、実際の結果、環境（OS / ブラウザ / コミットハッシュ）、ログ
- labels: `["type:bug", "status:triage"]`

**`.github/ISSUE_TEMPLATE/infra.yml`**

- 対象環境（local / stg / prod）、変更内容、影響範囲、ロールバック手順
- labels: `["type:infra", "status:triage"]`

**`.github/ISSUE_TEMPLATE/docs.yml`**

- 対象ドキュメント、変更概要、影響範囲
- labels: `["type:docs", "status:triage"]`

**`.github/ISSUE_TEMPLATE/config.yml`**

```yaml
blank_issues_enabled: false
contact_links:
  - name: 質問・議論
    url: https://github.com/Colo-bot05/coloOS/discussions
    about: Issueにする前の質問・相談はこちら
```

### 2) PR テンプレート

**`.github/PULL_REQUEST_TEMPLATE.md`**

```markdown
## 関連Issue
Closes #

## 変更内容
-

## 動作確認
- 手元での確認手順:
- ステージングでの確認観点:

## 使ったAI / プロンプト要旨
- Provider:
- 主なプロンプト:

## セルフチェック
- [ ] テスト追加・既存テスト全パス
- [ ] ドキュメント更新（必要なもの）
- [ ] シークレット混入なし
- [ ] 不要な依存追加なし
- [ ] ブランチ削除しない（CLAUDE.md §12.1）
- [ ] CLAUDE.md / AGENTS.md に違反なし

## レビュー観点（必要なら指定）
-

## 補足
- 設計書からの逸脱・判断ポイントがあれば記載
```

### 3) ブランチ保護ドキュメント

**`docs/runbook/branch-protection.md`**

リポジトリ管理者が Settings から実施する手順を文書化。コード化（Terraform GitHub Provider 等）は STEP 0 後半で別Issueにて検討。

最低限の記述項目：

- 保護対象ブランチ：`main`, `staging`, `release/stg`, `release/prod`
- 各ブランチの設定：
  - Require a pull request before merging（必須）
  - Required approvals: 1（Phase 1初期）
  - Dismiss stale pull request approvals when new commits are pushed
  - Require status checks to pass before merging:
    - `ci`（ST0-22で追加）
    - `ai-review`（ST0-23で追加）
  - Require branches to be up to date before merging
  - Require conversation resolution before merging
  - Restrict who can push（main / release/* は管理者のみ）
  - Allow force pushes：**禁止**
  - Allow deletions：**禁止**
- リポジトリ設定：
  - Settings > General > Pull Requests > **Automatically delete head branches: OFF**（厳守）
  - Default branch: `main`

### 4) 標準ラベルセット

**`scripts/setup-labels.sh`**（gh CLI使用例）

```bash
#!/usr/bin/env bash
set -euo pipefail
REPO="Colo-bot05/coloOS"

create() {
  gh label create "$1" --color "$2" --description "$3" --repo "$REPO" || \
  gh label edit "$1" --color "$2" --description "$3" --repo "$REPO"
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
```

実行コマンドは README に記載：

```
gh auth login
bash scripts/setup-labels.sh
```

### 5) README への追記

- セクション「ラベル運用」：標準ラベルの説明と setup-labels.sh の実行方法
- セクション「ブランチ保護」：`docs/runbook/branch-protection.md` へのリンク
- セクション「ブランチ保全」：CLAUDE.md §12.1 を再掲し、設定を絶対変更しない旨

## 想定テスト（概要レベル）

| No | 観点 | 操作 | 期待結果 |
|---|---|---|---|
| 1 | Issue テンプレ | GitHub UI で New Issue | Feature / Bug / Infra / Docs の4テンプレが選択可能 |
| 2 | Issue テンプレ | feature.yml を選んで起票 | 必須項目が全て表示・バリデーション有効 |
| 3 | Issue Blank | New Issue から空Issue作成 | 不可になっている、Discussionsに誘導 |
| 4 | PR テンプレ | feature ブランチからPR作成 | テンプレ本文が自動表示される |
| 5 | ラベル | `gh label list --repo Colo-bot05/coloOS` | 上記ラベルが全て存在 |
| 6 | ブランチ保護 | `main` に直接 push | 拒否される |
| 7 | ブランチ保護 | force push を試す | 拒否される |
| 8 | 自動削除 | PR をマージ | ブランチが remote に残る |
| 9 | ドキュメント | `docs/runbook/branch-protection.md` 確認 | 全保護対象ブランチの設定手順が網羅 |

## 関連リンク

- ST0-1: リポジトリ初期化
- マスター設計書 §16-§19（GitHub運用）
- マスター設計書 §17（ブランチ保全ルール）
- STEP 0 詳細設計書 §2.3 / §13.3
- CLAUDE.md §5 / §6 / §12.1
- AGENTS.md §2.4 / §6.3

## 優先度・期限

- 優先度：**最高**（ST0-3以降の運用に必要）
- 期限：ST0-1完了から1営業日以内

## 補足・注意事項

- 本Issueの一部はリポジトリ管理者のみが実行可能（ブランチ保護・ラベル作成）
- Claude Code が触れるのは `.github/`、`docs/runbook/`、`scripts/`、`README.md` まで
- ブランチ保護とラベル作成は人間オペレーター（宮本）が実行
- 完了確認のスクショは PR 本文に貼付
- 「Automatically delete head branches: OFF」は **CLAUDE.md §12.1 違反防止のための最重要設定**。これを ON にする変更は今後一切受け付けない

---

**Cowork から Claude Code への申し送り**

このIssueは Claude Code（実装側）と人間オペレーター（管理者操作）の協働Issueです。

- Claude Code が担当：`.github/ISSUE_TEMPLATE/*.yml`、`.github/PULL_REQUEST_TEMPLATE.md`、`docs/runbook/branch-protection.md`、`scripts/setup-labels.sh`、`README.md`への追記
- 人間（宮本）が担当：GitHub Settings からのブランチ保護有効化、`scripts/setup-labels.sh` 実行、Automatic delete head branches OFF の確認

PR本文には人間オペレーターが完了したことを示すスクショを貼ってください。スクショ未添付ではマージしないでください。
