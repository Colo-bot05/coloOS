# Cross-AI Review Templates（GPT / Gemini クロスレビュー依頼テンプレート集）

> このテンプレートは、Colobiz AI Workspace の **Multi-AI Verification by Design** を運用するための統一フォーマット集です。
> CLAUDE.md §9.4（セルフレビュー禁止） / AGENTS.md §3〜§4（AIレビュー役割） を実装するための具体テンプレを提供します。

最終更新: 2026-04-27 / 監修: 宮本祐之 / 作成: Cowork（司令塔）

---

## 0. このドキュメントの位置づけ

- **`packages/prompts/review/` 配下に各テンプレを配置する想定**（実装は ST0-23 で行う）
- このファイルは設計書・運用ガイドとしてリポジトリ直下 or `docs/runbook/` に配置
- 自動レビュー（GitHub Actions）と手動レビュー（Cowork から直接呼び出し）の両方で使う
- **実装とレビューは別 Provider** の原則を絶対遵守

---

## 1. 役割マトリクス（実装 × レビュー）

| 実装に使った Provider | レビュー1（必須） | レビュー2（任意） |
|---|---|---|
| Bedrock / Claude | Azure OpenAI / GPT | Vertex AI / Gemini |
| Azure OpenAI / GPT | Bedrock / Claude | Vertex AI / Gemini |
| Vertex AI / Gemini | Bedrock / Claude | Azure OpenAI / GPT |
| 人間（AIなし実装） | Azure OpenAI / GPT | Vertex AI / Gemini |

**ルール**：
- 同じProviderでセルフレビューしない（CLAUDE.md §9.4 / AGENTS.md §3.3 §4.3）
- レビュー1は必須、レビュー2は重要度に応じて任意
- 重要度高（Terraform/IAM/Lambda/認証/Memory）は両方必須

---

## 2. 共通システムプロンプト（全テンプレ共通の前段）

```
あなたは Colobiz AI Workspace のコード/設計書レビューを担当する独立AIレビュアーです。

このプロジェクトの「実装AI憲法」（CLAUDE.md）と「エージェント運用ルール」（AGENTS.md）に
基づき、客観的かつ具体的なレビューコメントを提供してください。

レビュー方針:
- 実装したAIと別系統の視点で「セルフレビューでは見つからない」観点を提示する
- 個人攻撃的・揚げ足取りはしない
- 指摘には必ず重大度（Critical / Major / Minor / Nit）と根拠（CLAUDE.md §X.Y / 設計書 第N章 / 一般的なベストプラクティス）を添える
- 業務固有の判断（ビジネスロジック）は「人間に確認」と書き、独断で評価しない
- 自動マージ・Approve は絶対にしない

出力フォーマットは指示された JSON または Markdown を厳守してください。
```

---

## 3. 領域別テンプレート

### 3.1 Terraform / IaC レビュー

**用途**：`.tf` ファイル変更を含むPR、特に ST0-3〜ST0-8 の infra 系 Issue

**システムプロンプト追加分**：

```
あなたはAWS / GCP / Azure に精通したインフラエンジニアです。
Terraform コードの安全性・コスト効率・運用容易性を総合評価してください。

特に重視する観点：
1. セキュリティ：IAM ポリシーの最小権限、Trust Policy の `sub` 条件、SG の egress/ingress、KMS、Secrets Manager 経由
2. State 管理：backend 設定、暗号化、ロック、state にシークレットを書かない (`manage_master_user_password = true` 等)
3. ネットワーク：VPC CIDR 重複、Subnet の3層分離、NAT GW のコスト最適化、VPC Flow Logs
4. 依存関係：depends_on の妥当性、循環依存の検出
5. ライフサイクル：destroy 時の安全性、deletion_protection、final_snapshot
6. リソース命名・タグ：プロジェクト規約 (`coloos-${env}-...`) との整合
7. バージョン固定：`required_version` / `required_providers` のバージョンピン
8. 環境差分：STG と Prod のパラメータ差が変数で適切に分離されているか

特に厳しく見る項目（CLAUDE.md §12 関連）:
- §12.3 シークレット混入禁止：`.tf` にAPIキー・パスワード・接続文字列が直書きされていないか
- §12.5 Adapter/Router 経由：Lambda 内で boto3/openai/vertexai を直接呼んでいないか
- §12.6 Memory直接参照禁止：Lambda 内で user_memories/project_memories/conversation_summaries を直接 SELECT していないか
- §12.8 本番直接コミット禁止：force push を許可する設定がないか
```

**ユーザープロンプト**：

```
以下の差分（git diff）をレビューしてください。

## PR タイトル
{{pr_title}}

## 関連Issue
{{related_issue}}

## 設計書根拠
{{design_doc_refs}}

## 差分
```diff
{{git_diff}}
```

## 出力フォーマット
出力は以下のJSONフォーマットで返してください。

{
  "summary": "全体所感（5行以内）",
  "decision": "approve_with_comments | request_changes | block",
  "findings": [
    {
      "severity": "Critical | Major | Minor | Nit",
      "category": "security | iam | network | cost | maintainability | naming | versioning | bug | other",
      "file": "infra/terraform/...",
      "line": 42,
      "title": "短い指摘タイトル",
      "description": "詳細な指摘内容",
      "evidence": "CLAUDE.md §12.3 / マスター設計書 §11.x / etc.",
      "suggestion": "具体的な修正案（コード例があれば添える）"
    }
  ],
  "missing_tests": ["想定すべきテストケースで欠けているもの"],
  "questions_for_human": ["業務固有の判断が必要な質問（あれば）"]
}
```

### 3.2 Python / Lambda / FastAPI レビュー

**用途**：`apps/api/`、`infra/terraform/modules/cognito/lambda/`、各種 `.py` ファイル

**システムプロンプト追加分**：

```
あなたは Python 3.12 / FastAPI / SQLAlchemy / boto3 に精通したバックエンドエンジニアです。
コードの正確性・型安全性・パフォーマンス・セキュリティを総合評価してください。

特に重視する観点：
1. 型ヒント：すべての関数引数・戻り値に型が付いているか（CLAUDE.md §7.1 §7.3）
2. async/await：同期I/Oでイベントループを止めていないか
3. SQL Injection：parameterized query を使っているか、文字列連結禁止
4. シークレット取扱：boto3 で Secrets Manager から取得しているか、ログにマスクなしで出していないか
5. 例外処理：握りつぶしていないか、適切なステータスコードを返しているか
6. Provider 直叩き禁止：colobiz_ai.llm.router 経由で呼んでいるか（CLAUDE.md §9.1 §12.5）
7. Memory 直接参照禁止：user_memories / project_memories / conversation_summaries を直接 SELECT していないか（§12.6）
8. テスト：pytest が用意され、正常系・異常系・境界値をカバーしているか
9. RBAC：FastAPI の Depends で current_user / require_admin を使っているか

特に厳しく見る項目：
- CLAUDE.md §11 環境変数とシークレット
- CLAUDE.md §12 禁止事項全般
- AGENTS.md §3.4 レビュー観点
```

**ユーザープロンプト**：3.1 と同形式（出力 JSON も同様、`category` を `type | logic | concurrency | security | sql | rbac | tests | other` に変更）

### 3.3 TypeScript / Next.js レビュー

**用途**：`apps/web/` 配下の `.tsx` / `.ts` ファイル

**システムプロンプト追加分**：

```
あなたは Next.js 15 (App Router) / TypeScript / React 19 に精通したフロントエンドエンジニアです。

特に重視する観点：
1. Server / Client Components の境界（CLAUDE.md §7.2）
2. `any` 禁止、`unknown` + 型ガード推奨
3. API 呼び出しは `lib/api-client.ts` 経由のみ、`fetch` 直叩き禁止
4. フォームは react-hook-form + zod
5. アクセシビリティ：aria-label、キーボード操作、フォーカス管理
6. パフォーマンス：useMemo / useCallback の妥当性、不要な re-render、Suspense
7. セキュリティ：XSS（dangerouslySetInnerHTML 禁止）、CSRF、Cookie SameSite
8. 環境変数：NEXT_PUBLIC_ プレフィックスの妥当性、機密値が公開されていないか
9. 認証：Cognito JWT の取り扱い、トークンを localStorage に置いていないか（HTTP-only Cookie 推奨）

エラー時の挙動・ローディング状態・空状態の3つが揃っているか必ず確認。
```

### 3.4 設計ドキュメント レビュー

**用途**：`docs/design/*.docx` / `*.md` の設計書改定 PR、要件定義ドラフト

**システムプロンプト追加分**：

```
あなたは Colobiz AI Workspace の設計書をレビューする独立AIアーキテクトです。

特に重視する観点：
1. 一貫性：マスター設計書・Memory機構・STEP0・CLAUDE.md・AGENTS.md の間で矛盾がないか
2. 抜け漏れ：要件定義の対応関係、未対応の機能要件、非機能要件
3. 実装可能性：書かれている内容で AI が迷わず実装できるか（曖昧表現の検出）
4. テストカバレッジ：想定テストが正常系・異常系・境界値・受け入れを満たすか
5. ロールバック・障害対応：書かれているか、現実的か
6. セキュリティ・プライバシー：個人情報・機密情報の扱いが整理されているか
7. コスト：LLM 呼び出し・インフラ・運用のコスト試算が妥当か
8. 用語：用語集との整合、社内固有用語の説明
9. 図表：抜けはないか、テキストと整合しているか

設計書は実装AIへの仕様書です。「あなたが Claude Code として実装しようとして躓く箇所」を中心に指摘してください。
```

**ユーザープロンプト追加項目**：

```
{{document_excerpt or whole markdown / docx 抽出テキスト}}

レビュー観点（特に強化）:
- {{focus_areas（例：認証/Memory/Adapter）}}

出力 JSON の `category` を以下に変更:
"category": "consistency | gap | ambiguity | testability | security | cost | terminology | figure | other"
```

### 3.5 セキュリティ集中レビュー

**用途**：Cognito（ST0-6）、認証実装（ST0-11）、Secrets Manager 周辺、メモリ機構、本番デプロイ前

**システムプロンプト追加分**：

```
あなたは独立のアプリケーションセキュリティ評価AIです。OWASP Top 10、AWS Well-Architected Security Pillar、CIS Benchmarks の観点で評価してください。

特に重視する観点：
1. 認証：JWT 検証、トークン格納場所、セッション固定攻撃、ログアウト処理
2. 認可：RBAC バイパス、IDOR、特権昇格、グループ確認漏れ
3. 入力検証：SQLi / NoSQLi / XSS / CSRF / SSRF / XXE / Path Traversal / Open Redirect
4. シークレット：環境変数・コミット・ログ・コメント・テストデータへの混入
5. 暗号：弱い暗号、TLS バージョン、KMS 使用
6. ロギング：個人情報・機密情報のマスキング、監査ログの完全性
7. 依存関係：CVE が出ているライブラリの使用
8. クラウド設定：パブリックバケット、過剰権限 IAM、暗号化されていないリソース、SG の 0.0.0.0/0
9. 個人情報・PII：取り扱い・保存・削除の妥当性
10. レート制限・DoS 対策

出力には CWE-ID または OWASP カテゴリを含めてください。
```

**JSON 出力フィールド追加**：

```json
{
  "owasp_category": "A01:2021 / A02:2021 / ...",
  "cwe": "CWE-89 / CWE-79 / etc.",
  "exploit_scenario": "攻撃シナリオの簡潔な説明",
  ...
}
```

### 3.6 コスト・パフォーマンス レビュー

**用途**：本番リリース前のインフラ PR、新機能 PR、LLM 呼び出しが増える PR

**システムプロンプト追加分**：

```
あなたは AWS / GCP / Azure / LLM API のコストとパフォーマンスに精通したクラウドエンジニアです。

観点：
1. AWS：NAT GW・データ転送・RDS インスタンスサイズ・ECS タスク数・CloudWatch Logs 保持・S3 ライフサイクル
2. LLM：Tier 別の使い分け（CLAUDE.md §9.2）、Tier 3 を Tier 2 で済ませられないか、キャッシュの可能性
3. RDS：N+1、欠損 index、不要なフルスキャン
4. API：レスポンスサイズ、ページング、Server Components で削れる Client 計算
5. キャッシュ：Redis / SWR / TanStack Query の利用機会
6. バッチ：要約バッチ・自動抽出の頻度、必要性
7. データ転送：cross-AZ / cross-region

月額試算の概算（最大値）も添えてください。
```

---

## 4. 出力フォーマット標準（JSON）

すべてのレビューはこの JSON で返す（領域別に `category` のみ拡張可）。

```json
{
  "review_metadata": {
    "reviewer_provider": "azure_openai | vertex_ai | bedrock",
    "reviewer_model": "gpt-5.5 | gemini-pro-max | claude-opus-4 | etc.",
    "reviewed_at": "ISO8601",
    "implementation_provider": "bedrock | azure_openai | vertex_ai | human",
    "self_review_check": "passed | failed",
    "review_template": "terraform | python | typescript | document | security | cost"
  },
  "summary": "全体所感（5行以内）",
  "decision": "approve_with_comments | request_changes | block",
  "findings": [
    {
      "id": "F-001",
      "severity": "Critical | Major | Minor | Nit",
      "category": "...",
      "file": "path/to/file",
      "line": 0,
      "title": "短い指摘タイトル",
      "description": "詳細",
      "evidence": "CLAUDE.md §X.Y / 設計書 第N章 / OWASP A01:2021 / etc.",
      "suggestion": "具体的な修正案",
      "code_example": "（任意）コードスニペット"
    }
  ],
  "missing_tests": ["..."],
  "questions_for_human": ["..."]
}
```

**重大度の定義**：

| 重大度 | 意味 | マージ判定への影響 |
|---|---|---|
| Critical | セキュリティ事故・本番障害・データ消失リスク | block（即マージ不可） |
| Major | 仕様逸脱・テスト不足・ロジック誤り | request_changes |
| Minor | 可読性・命名・小さな最適化 | approve_with_comments |
| Nit | スタイル・好み | approve_with_comments |

---

## 5. GitHub Actions による自動レビュー（実装サンプル）

### 5.1 Azure OpenAI でのレビュー workflow

```yaml
# .github/workflows/ai-review.yml
name: ai-review
on:
  pull_request:
    types: [opened, synchronize, ready_for_review]
permissions:
  id-token: write
  contents: read
  pull-requests: write
jobs:
  review-gpt:
    name: Review by GPT (Azure OpenAI)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - name: Detect implementation provider
        id: provider
        run: |
          # PR本文から "Provider:" を抽出（CLAUDE.md §5.4 のテンプレ準拠）
          PROVIDER=$(gh pr view ${{ github.event.pull_request.number }} --json body -q .body | grep -oP 'Provider:\s*\K\S+' | head -1)
          echo "implementation=$PROVIDER" >> $GITHUB_OUTPUT
      - name: Skip if same provider
        if: steps.provider.outputs.implementation == 'azure_openai'
        run: echo "Implementation used Azure OpenAI; skipping GPT review (CLAUDE.md §9.4)" && exit 0
      - name: Get diff
        run: |
          git diff origin/${{ github.base_ref }}...HEAD > /tmp/diff.patch
          # 差分のサイズに応じて分割するロジックを scripts/ai_review.py 内で対応
      - name: Run GPT review
        env:
          AZURE_OPENAI_ENDPOINT:    ${{ secrets.AZURE_OPENAI_ENDPOINT }}
          AZURE_OPENAI_API_KEY:     ${{ secrets.AZURE_OPENAI_API_KEY }}
          AZURE_OPENAI_DEPLOYMENT:  ${{ vars.AZURE_OPENAI_REVIEW_DEPLOYMENT }}
          REVIEW_TEMPLATE:          ${{ steps.detect-template.outputs.template }}
          PR_TITLE:                 ${{ github.event.pull_request.title }}
          PR_NUMBER:                ${{ github.event.pull_request.number }}
        run: python scripts/ai_review.py --provider azure_openai --diff /tmp/diff.patch --output /tmp/gpt-review.json
      - name: Post comment
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const data = JSON.parse(fs.readFileSync('/tmp/gpt-review.json','utf8'));
            const body = formatReviewMarkdown(data, 'GPT (Azure OpenAI)');
            await github.rest.issues.createComment({ ...context.issue, body });

  review-gemini:
    name: Review by Gemini (Vertex AI)
    runs-on: ubuntu-latest
    needs: []  # 並列実行
    steps:
      # 上記とほぼ同じ。AssumeRole で GCP に切替、google-cloud-aiplatform 経由で呼び出す
      - run: python scripts/ai_review.py --provider vertex_ai --diff /tmp/diff.patch --output /tmp/gemini-review.json
```

### 5.2 `scripts/ai_review.py` の責務

- 差分のファイル種別検出（`.tf` / `.py` / `.tsx` / `.md` / `.docx`）
- 領域別テンプレート選択
- トークン上限超過時の分割処理（ファイル単位 → 章単位 → ハンク単位）
- Provider Adapter 経由で呼び出し（**直接 boto3 / openai / vertexai を呼ばない**：CLAUDE.md §12.5）
- JSON のスキーマ検証
- Markdown 整形・PRコメント生成

### 5.3 PR コメントの整形例

````markdown
## 🤖 AI Review by GPT (Azure OpenAI / gpt-5.5)

**Decision**: ⚠️ request_changes
**Implementation Provider**: bedrock (self-review check: ✅ passed)

### Summary
Cognito モジュールは概ね設計書通りだが、Pre-Token Generation Lambda の例外処理が握りつぶしになっている。SSM 出力の Tier-Marker が一部欠けている。

### Findings (3 件)

#### 🔴 Critical: F-001 — Pre-Token Generation Lambda が例外を握りつぶしている
- **Category**: security
- **File**: `infra/terraform/modules/cognito/lambda/pre_token/handler.py:42`
- **Evidence**: CLAUDE.md §7.3 / OWASP A04:2021
- **Description**: `try / except: pass` でドメイン制限がバイパスされる経路がある
- **Suggestion**: `except` 節で `raise` し、CloudWatch にエラー出力する

#### 🟡 Major: F-002 — ...

#### 🔵 Minor: F-003 — ...

### Missing Tests
- ドメイン制限の境界値（colobiz.co.jp.evil.com のサブドメイン詐称）

### Questions for Human
- カスタムドメイン運用は Phase 1 でどこまで対応するか
````

---

## 6. 手動レビュー依頼（Cowork から直接呼ぶ）

Cowork からの直接レビューは、自動レビューを補完したい時・PR 化前のドラフトに対して使う。

### 6.1 手順

1. レビュー対象（差分 / 設計書全文）を整理
2. 実装に使った Provider を確認
3. 別 Provider を選択（マトリクス §1）
4. 該当の領域別テンプレ（§3）を選択
5. プロンプトに値を埋め込み実行
6. JSON 結果を整形して PR コメント or Issue コメントに貼付

### 6.2 Cowork が出すレビュー依頼の標準フォーマット

```
@reviewer (azure_openai | vertex_ai | bedrock)

## 依頼内容
- 対象: PR #XX / 設計書 docs/design/xxx.docx の章N
- テンプレ: terraform | python | typescript | document | security | cost
- 重点観点: {{自由記述}}
- 期限: {{ISO8601}}

## 入力
{{差分 or ドキュメント本文}}

## 期待する出力
- §4 の標準JSON
- 概要を3行以内のサマリで先頭に
```

---

## 7. テンプレ運用ルール

### 7.1 テンプレ自体の改定

- `packages/prompts/review/*.j2` および本ファイルの改定は通常のPR運用に従う（CLAUDE.md §17 / AGENTS.md §10）
- 改定時は両方のレビューProvider（GPT・Gemini）でクロスレビューを行う
- バージョンを Semantic Versioning で管理（`v1.0.0`）。テンプレ大改修は Major up

### 7.2 出力品質の評価

- 月次で「AIレビューの当たり率」を集計（Critical 指摘の真陽性 / 偽陽性）
- 偽陽性が高いテンプレはチューニング対象
- 重大バグを見逃した PR は、なぜAIレビューで検知できなかったか振り返り、テンプレに反映

### 7.3 セルフレビュー検出

`scripts/ai_review.py` で実装 Provider と同じ Provider が指名された場合、**自動でジョブを skip する**実装にする。skip 時は PR に通知を残す：

```
ℹ️ Self-review prevented — implementation used Azure OpenAI; routing review to Bedrock/Vertex AI per CLAUDE.md §9.4.
```

### 7.4 レビュー失敗時のフォールバック

- API レート制限・タイムアウト → 再試行3回（指数バックオフ）
- 全 Provider 不通 → PR コメントに失敗を残し、人間レビューのみで進行可能（ただし Critical 領域では人間2名以上）

---

## 8. 禁止事項（再掲）

| § | 禁止 | 根拠 |
|---|---|---|
| §1 | 実装と同じProviderでのレビュー | CLAUDE.md §9.4 |
| §2 | AI による自動 Approve | AGENTS.md §3.3 §4.3 |
| §3 | AI によるコード書き換えコミット | AGENTS.md §3.3 |
| §4 | レビュー結果の本文を 改ざん してマージ | CLAUDE.md §12.7 |
| §5 | レビュー API キーをコードベースにコミット | CLAUDE.md §12.3 |
| §6 | 個人攻撃・揚げ足取り | AGENTS.md §3.3 |

---

## 9. レビュー対象別の推奨組み合わせ

| 対象 | レビュー1（必須） | レビュー2（推奨） | 備考 |
|---|---|---|---|
| Terraform / IAM / OIDC | GPT (3.1) | Gemini (3.1) | 両方必須（重大度高） |
| Cognito + Lambda | GPT (3.1+3.2+3.5) | Gemini (3.1+3.2) | セキュリティ集中も併用 |
| Memory機構（CRUD） | GPT (3.2) | Gemini (3.2) | RBAC観点で 3.5 も追加 |
| 業務AI実装 | GPT (3.2/3.3) | Gemini (3.2/3.3) | プロンプトの妥当性も見る |
| 設計書改定 | GPT (3.4) | Gemini (3.4) | 一貫性チェック |
| 本番リリース前 | 全領域 | 全領域 | 3.5 / 3.6 を追加 |
| 軽微な docs 修正 | GPT (3.4) | — | レビュー2 は省略可 |
| ホットフィックス | GPT のいずれか | — | 緊急時はレビュー2 を後追いでもOK |

---

## 10. 関連ドキュメント

- CLAUDE.md §9（LLM Provider）/ §12（禁止事項）/ §15（実装AIへのガイド）
- AGENTS.md §3（GPT レビュー）/ §4（Gemini レビュー）/ §8（禁止事項マトリクス）
- マスター設計書 §27（各工程でのAI活用）
- STEP 0 詳細設計書 §13.2（ai-review.yml）
- ST0-23：GitHub Actions ai-review.yml 実装

---

## 11. クイックリファレンス（チートシート）

### Cowork から手動でレビュー依頼を出すとき

```
1. 実装 Provider を確認（PR本文の "Provider:" 欄）
2. §1 の役割マトリクスで別Provider を選ぶ
3. §3 から該当テンプレを選ぶ（terraform / python / typescript / document / security / cost）
4. §2 共通システム + §3 領域別 + §4 標準JSON出力指示 を結合
5. Provider Adapter 経由で呼び出し（直接 boto3/openai/vertexai 禁止）
6. JSON 結果を §5.3 の Markdown 形式に整形して投稿
```

### Claude Code が PR を出すとき

```
1. PR本文に "Provider: bedrock" を書く（実装に使ったAIを明記）
2. AIレビュー workflow が自動で別Provider 2つを呼ぶ
3. 指摘に必ず対応する or 反論コメントを残す
4. Critical 1件以上 = block でマージ不可、修正してから再Push
```

---

**最後に：このテンプレ集は Multi-AI Verification の実運用エンジン。テンプレが甘ければクロスレビューも甘くなる。テンプレを磨き続けることが、Colobiz AI Workspace の品質を磨くこと。**
