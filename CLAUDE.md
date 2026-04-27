# CLAUDE.md

> このリポジトリで Claude Code（および将来の閉域開発エージェント）が必ず守るべき「実装AIの憲法」です。
> 読むのは人間と AI の両方。**疑問が出たらまずこのファイルを最新の正解として扱ってください。**

最終更新: 2026-04-27 / 監修: 宮本祐之 / 作成: Cowork（司令塔）

---

## 0. このドキュメントの位置づけ

- **CLAUDE.md = 実装の憲法**：本ドキュメントの記述と他の指示が矛盾した場合、本ドキュメントを優先する
- **AGENTS.md = エージェント別の運用ルール**：Claude Code / AIレビュー / 開発エージェント それぞれの動き方を補足
- **設計書（docs/design/*.docx）= 仕様の出典**：要件・設計・テスト観点はこれを正とする

> 設計書と本書が矛盾していたら、まず人間（宮本）に確認する。勝手にどちらか優先しない。

---

## 1. プロジェクト概要

**Colobiz AI Workspace** — Colobiz社員のための社内AI共通基盤。Phase 1で「まずAIに相談する」状態を作る。

主要機能（Phase 1）：

- 通常チャット（相談・壁打ち）
- 要件定義AI / 資料作成AI / 見積り補助AI
- Backlog タスク化AI
- レビューAI（4観点）
- 社内RAG（簡易版）
- 管理ダッシュボード（簡易版）
- **横断基盤：Memory機構（業務記憶を持つAI基盤）**
- **横断基盤：Colobiz Decision Engine（思考OS：判断軸 / 3視点レビュー / 逆算順算 / 3要素評価 / 再現性チェック）**

**設計思想：Spec-Driven × Multi-AI Verification by Design**

Bedrock(Claude) / Azure OpenAI(GPT) / Vertex AI(Gemini) の3 Provider を初期から使い分け、機能ごとに最適なProvider/Tier を割り当てる。実装と同じProviderでセルフレビューしない。

---

## 2. 技術スタック（バージョン固定）

| カテゴリ | 技術 |
|---|---|
| Frontend | Next.js 15 (App Router) / TypeScript 5.x (strict) / Tailwind CSS / shadcn/ui |
| Backend | Python 3.12 / FastAPI 0.115+ / SQLAlchemy 2.x / Alembic / Pydantic v2 |
| DB | Amazon RDS for PostgreSQL 16 + pgvector |
| Cache | Redis 7 |
| Auth | Amazon Cognito (User Pool + Groups) ＋ Google Workspace IdP federation（社員ログインはGoogle、内部RBACはCognitoグループ） |
| Container | Docker / Amazon ECS Fargate |
| LLM | Bedrock(Claude) / Azure OpenAI(GPT) / Vertex AI(Gemini) |
| Embeddings | Bedrock Titan Embed v2（Phase 1既定） |
| Secrets | AWS Secrets Manager / SSM Parameter Store |
| CI/CD | GitHub Actions |
| MCP | Backlog MCP Server |
| Monitoring | CloudWatch / Sentry |
| Package | pnpm 9.x（フロント・モノレポ） / poetry 1.8.x（バックエンド） |
| Lint/Format | ESLint / Prettier / ruff / mypy |
| Test | Vitest / pytest / Playwright（E2E） |

**バージョン変更が必要な場合**：必ず Issue を立てて、依存影響を整理してからPR。Claude Code が独断で `package.json` / `pyproject.toml` のバージョンを上げないこと。

---

## 3. ディレクトリ構成

```
colobiz-ai-workspace/
├─ apps/
│   ├─ web/                Next.js (App Router)
│   └─ api/                FastAPI
├─ packages/
│   ├─ prompts/            共通プロンプト・役割別プロンプト（YAML/Jinja2）
│   └─ schemas/            OpenAPI生成型 / 共通型
├─ infra/
│   ├─ terraform/          envs/{stg,prod}/ + modules/
│   └─ docker/             Dockerfile + docker-compose.yml
├─ .github/
│   ├─ workflows/          CI/CD
│   ├─ ISSUE_TEMPLATE/
│   └─ PULL_REQUEST_TEMPLATE.md
├─ docs/
│   ├─ design/             機能別設計書
│   └─ runbook/            運用手順書
├─ scripts/                開発補助
├─ CLAUDE.md               ← 本ファイル
├─ AGENTS.md
├─ README.md
└─ .gitignore
```

**新規ファイルを置くときは必ず上記の階層に従う。** 階層を逸脱したい場合は Issue で提案する。

---

## 4. 命名規則

### 4.1 ブランチ

形式：`<種別>/<Issue番号>-<英小文字ハイフン区切りの概要>`

| 種別 | プレフィックス | 例 |
|---|---|---|
| 新機能 | `feature/` | `feature/ISSUE-12-chat-streaming` |
| バグ修正 | `fix/` | `fix/ISSUE-34-conversation-load-error` |
| 緊急修正 | `hotfix/` | `hotfix/ISSUE-78-prod-500-error` |
| リファクタ | `refactor/` | `refactor/ISSUE-45-extract-prompt-loader` |
| ドキュメント | `docs/` | `docs/ISSUE-90-api-readme` |
| インフラ | `infra/` | `infra/ISSUE-22-bedrock-iam` |

### 4.2 ファイル・コード

- **TypeScript**：ファイル名は `kebab-case`、React コンポーネントは `PascalCase`、変数・関数は `camelCase`、定数は `UPPER_SNAKE_CASE`
- **Python**：ファイル名・関数名は `snake_case`、クラス名は `PascalCase`、定数は `UPPER_SNAKE_CASE`
- **テスト**：`*.test.ts` / `*.spec.ts` / `test_*.py` のいずれか、対象と1対1対応

### 4.3 PR タイトル

`[ISSUE-xx] 簡潔な変更内容（30字以内）`

---

## 5. 開発ワークフロー（Issue起点）

**実装は必ず Issue から始める。Issue なしでブランチを切らない。**

```
Issue作成 → ブランチ → 実装＋テスト → PR → AIレビュー → 人間レビュー → STGマージ → STGデプロイ → STGテスト → 本番マージ
```

### 5.1 Issue を作る

Issueテンプレを使い、以下を必ず埋める：

- 背景（なぜやるか）
- 目的
- 受け入れ条件（Definition of Done）
- 想定実装内容（概要レベル）
- 想定テスト（概要レベル）
- 関連リンク（要件定義書・設計書・過去Issue・Slackスレッド）
- 優先度・期限

### 5.2 ブランチを切る

- 必ず `staging` から派生（`hotfix/` のみ `main` から）
- 命名規則を遵守
- マージ後も**絶対にブランチを削除しない**（後述）

### 5.3 実装

- **Issue と設計書を読み切ってから書き始める**。読まずに着手して仕様ズレを起こさない
- TDD推奨：先にテストを書き、実装で通す
- コミットは小粒に（1コミット = 1論理変更）
- コミットメッセージは `[ISSUE-xx] 何をしたか` の形式

### 5.4 PR

- PRテンプレを使う
- 関連Issueを `Closes #xx` で必ず紐付け
- 動作確認の方法（手元 / ステージング）を書く
- スクショまたは動画があれば貼る
- 使ったAIと主要なプロンプトを記載（再現性のため）
- セルフチェックリストを全て満たす：
  - [ ] テスト追加・既存テスト全パス
  - [ ] ドキュメント更新（必要なもの）
  - [ ] シークレット混入なし
  - [ ] 不要な依存追加なし
  - [ ] ブランチ削除はしない
  - [ ] CLAUDE.md / AGENTS.md の規約に違反していない

### 5.5 レビュー

1. **AIレビュー（自動）**：PR作成時に GitHub Actions が Azure OpenAI または Vertex AI に差分を渡し、コメント投稿。**実装と同じ Provider でレビューはしない**
2. **人間レビュー**：AIレビューを踏まえて宮本（または委任先）が確認
3. 最低1名のApprove必須。AIレビューはRequired status checksに組み込み、必ず通す

### 5.6 マージ後

- ブランチを**削除しない**（GitHubのDelete branchボタンは押さない）
- リポジトリ設定 `Automatically delete head branches = OFF` を維持
- マージしたらSTG / 本番の所定フローに乗せる

---

## 6. ブランチ運用とデプロイフロー

```
feature/* ─→ staging ─→ release/stg ─→ STG ECS
                                ↓
                             STGテスト
                                ↓
            staging ─→ main ─→ release/prod ─→ 本番 ECS（手動承認）
```

| ブランチ | 用途 | デプロイ先 |
|---|---|---|
| `main` | 本番のメイン。リリース確定済み | 直接デプロイしない |
| `release/prod` | 本番デプロイブランチ | 本番ECS |
| `staging` | 次回リリース候補 | 直接デプロイしない |
| `release/stg` | STGデプロイブランチ | STG ECS |
| `feature/*` `fix/*` | 機能・バグ修正開発 | （CI実行のみ） |
| `hotfix/*` | 緊急修正（mainから派生） | 緊急時のみ別ルート |

**本番デプロイブランチへのマージは権限者のみが実行する。Claude Code は絶対にマージしない。**

---

## 7. コーディング規約

### 7.1 共通

- 型を必ず付ける（TS strict、Python type hints）
- 関数は短く（理想は20行以内、最大50行）
- 早期 return を使い、ネストを浅く
- マジックナンバー禁止：定数化または設定ファイル化
- コメントは「なぜ」を書く。「何を」はコードで読めるように
- 例外は握りつぶさず、構造化ログ＋適切なステータスコードで返す

### 7.2 TypeScript / Next.js

- ESLint + Prettier に従う
- `any` は禁止（やむを得ない場合は `unknown` + 型ガード）
- Server Components 優先。Client Components は必要な範囲のみ `"use client"`
- フォームは react-hook-form + zod
- API呼び出しは `lib/api-client.ts` 経由のみ。`fetch` 直叩き禁止

### 7.3 Python / FastAPI

- ruff + mypy に従う
- async/await を使用（同期I/Oでイベントループを止めない）
- 依存関係注入は FastAPI の `Depends` を活用
- ORMモデルとスキーマ（Pydantic）は分離
- 例外は `colobiz_ai/exceptions.py` の共通階層を使う

### 7.4 SQL / マイグレーション

- Alembic で管理。手書きSQL直叩きでDBを変更しない
- マイグレは小粒に（1ファイル = 1論理変更）
- 破壊的変更は2リリースに分ける（追加 → 切替 → 削除）
- カラム削除は1リリースで決定しない（必ず段階的）

---

## 8. テスト方針

### 8.1 ピラミッド

- 単体 70% / 結合 20% / E2E 10% を目安
- 実装と同時にテストを書く（後回しにしない）
- AIに「あなたが見落としそうな境界値を10個挙げて」と問わせ、テストケースを補強

### 8.2 何をテストするか

- **API**：認証・正常系・異常系・境界値・DB保存・外部API失敗
- **フロント**：コンポーネント単体（Vitest）、フォーム動作、E2Eシナリオ（Playwright）
- **AI出力品質**：プロンプトのスナップショットテスト＋人手評価セット（後続Phase）

### 8.3 PRごとの最低基準

- 新規コード：単体テスト必須
- バグ修正：再現テスト先行（赤→緑のサイクル）
- リファクタ：既存テストが全部通ることを確認

---

## 9. LLM Provider の扱い方

### 9.1 必ず Adapter / Router 経由で呼ぶ

**直接 boto3 / openai SDK / google-cloud-aiplatform を業務コードから叩かない。** すべて `colobiz_ai.llm.router.LLMRouter` 経由。

```python
# OK
response = await router.invoke(role="chat.default", messages=messages)

# NG
import boto3
client = boto3.client("bedrock-runtime")
client.converse(...)  # 業務コードからの直接呼び出し禁止
```

### 9.2 Tiered Model Design

| Tier | 用途 | 代表モデル |
|---|---|---|
| Tier 1（軽量・高速） | 通常チャット軽い相談・即レス・下書き | GPT-5 mini / Claude Haiku / Gemini Flash |
| Tier 2（標準） | 資料作成・要件定義中間・営業トーク・Backlog分解 | GPT-5.x / Claude Sonnet / Gemini Pro |
| Tier 3（重い・高精度） | 最終アウトプット・見積り・重要判断・レビュー | GPT-5.5 / Claude Opus / Gemini Pro Max |

**最上位モデルを既定にしない。** Tier 3 は仕上げ役だけに当てる。

### 9.3 役割と Provider のマッピング

`infra/config/llm_routes.yaml` で集約管理。コード内に直接モデル名を書かない。

| 役割 | 既定 Provider |
|---|---|
| `chat.default` | Azure OpenAI / GPT-5 mini |
| `chat.deep` | Bedrock / Claude Sonnet |
| `requirements.final` | Bedrock / Claude Opus |
| `docs.final` | Azure OpenAI / GPT-5.5 |
| `estimate` | Azure OpenAI / GPT-5.5 |
| `backlog` | Bedrock / Claude Sonnet |
| `decision.judge` | Bedrock / Claude Sonnet |
| `decision.simulate` | Bedrock / Claude Opus |
| `decision.feasibility` | Azure OpenAI / GPT-5.5 |
| `decision.reproduce` | Bedrock / Claude Sonnet |
| `review.miyamoto` | Bedrock / Claude Opus（宮本視点：逆算ロジック） |
| `review.yoshida` | Azure OpenAI / GPT-5.5（吉田視点：技術的正当性） |
| `review.kashiwabara` | Vertex AI / Gemini Pro Max（柏原視点：運用イメージ） |
| `review.colobiz` | Bedrock / Claude Opus（3視点を集約した総評） |
| `code_review` | Azure OpenAI / GPT-5.5 |
| `embeddings.default` | Bedrock / Titan Embed v2 |

### 9.4 セルフレビュー禁止

実装に使ったのと同じ Provider でレビューしない。**Bedrock/Claude で実装したら、レビューは Azure OpenAI または Vertex AI で行う。** Multi-AI Verification は本基盤の中核思想。

---

## 10. Memory機構の扱い方

### 10.1 直接DBを参照しない

業務AIは `user_memories` / `project_memories` / `conversation_summaries` を**直接読まない**。Memory機構が提供する API またはサービス層を経由する。

### 10.2 build_context() に統一する（将来必須）

各業務AIは LLM 呼び出し直前に `MemoryService.build_context()` を呼んで、コンテキストパッケージを取得すること。生のメッセージ配列だけで LLM に投げる実装は禁止。

`build_context()` は内部で **Decision Engine の判断軸（Colobiz共通プロンプト9項目・要件定義ヒアリングロジック・3要素評価・3視点レビュー前提）** も注入する。業務AIは追加で個別プロンプトを書く必要はない（書くと判断軸が分散して整合性が崩れる）。

```python
ctx = await memory_service.build_context(
    user_id=user.id,
    conversation_id=conv.id,
    project_key=project_key,
    user_message=incoming.content,
    token_budget=8000,
    include_decision_axes=True,  # 既定で True、明示的に切る場合のみ False
)
response = await router.invoke(role="chat.default", messages=ctx.assemble())
```

### 10.3 Memory への書き込みは候補→承認の2段階

- 自動抽出は**候補**として記録するだけ
- ユーザー承認後に `user_memories` / `project_memories` に保存
- これを飛ばして直接INSERTしない

### 10.4 個人情報・機密情報のフィルタ

メモリ抽出処理には除外フィルタを必ず通す（電話番号・住所・契約金額・パスワード・APIキー等）。フィルタロジックは `colobiz_ai.memory.filters` に集約。

---

## 11. 環境変数とシークレット

### 11.1 シークレットを書かない

**コードベース・テストデータ・ドキュメント・コメントのいずれにも、APIキーや認証情報を書かない。**

- `.env.local` は `.gitignore` 済みであることを必ず確認
- 本番のシークレットはAWS Secrets Manager
- ローカル開発で必要なAPIキーは `.env.local` に置き、絶対にコミットしない
- pre-commit フックで `git-secrets` がシークレットを検出する設定を維持

### 11.2 環境変数の追加

新しい環境変数を増やす場合：

1. `.env.example` に追加（コメント付きで用途を書く）
2. `apps/api/src/colobiz_ai/config.py` のSettingsクラスに追加（型・デフォルト・バリデーション）
3. `apps/web/lib/env.ts` に追加（NEXT_PUBLIC_ プレフィックス必要なら付ける）
4. Terraform の Secrets/SSM 定義に追加
5. CLAUDE.md および設計書付録Cの環境変数表を更新

---

## 12. 禁止事項（憲法）

以下は**例外なく禁止**。違反したPRは即マージ不可。

### 12.1 ブランチ削除禁止

- マージ後もブランチを残す
- GitHub PR画面の「Delete branch」を押さない
- リポジトリ設定の「Automatically delete head branches」を ON にしない

### 12.2 Issue起点開発の徹底

- Issue なしでブランチを切らない
- Issue なしでPRを作らない
- 既存Issueの目的を勝手に拡大しない（必要なら新Issueを立てる）

### 12.3 シークレット混入禁止

- APIキー・パスワード・接続文字列をコードに書かない
- ログに認証情報を出さない（マスク必須）
- スクショやエラーメッセージに認証情報が含まれていないか確認してからPRに貼る

### 12.4 外部AIへの社内コード貼付禁止

- 社外公開の ChatGPT Web版 / Gemini Web版 / Copilot Web版 等に、本リポジトリのコードや顧客情報を貼らない
- Claude Code（社内Bedrock経由）/ Azure OpenAI / Vertex AI のように、契約上データが学習に使われない経路のみ使用
- 個人アカウントのAIサービスに業務コードを貼ることも禁止

### 12.5 LLM Adapter / Router を迂回しない

- 業務コードから boto3 / openai / vertexai を直接呼ばない
- モデルIDをハードコードしない（`infra/config/llm_routes.yaml` を経由）
- 同じProviderでセルフレビューしない

### 12.6 Memory直接参照禁止

- `user_memories` / `project_memories` / `conversation_summaries` を業務AIから直接 SELECT しない
- 必ず Memory サービス層 / build_context() 経由

### 12.7 PRに対する義務

- テストなしマージ禁止
- AIレビューを意図的にスキップしない（required status check）
- セルフチェックリストを通さずマージ依頼しない

### 12.8 本番への直接コミット禁止

- `main` / `release/prod` への直push禁止
- Branch protection ルールを意図的に外さない
- Force push 禁止
- Allow deletions 禁止

### 12.9 破壊的DB変更を1段で行わない

- カラム削除・型変更・名前変更は段階リリース（追加→切替→削除）
- ロールバック不可なマイグレを単独で出さない

### 12.10 Decision Engine を迂回しない

- 業務AI（要件定義 / 資料 / 見積り / Backlog / レビュー / 通常チャット）は、Colobizの判断軸を独自プロンプトで再実装しない
- 必ず `build_context(include_decision_axes=True)` 経由で Decision Engine の判断軸を取り込む
- 3視点レビュー（宮本・吉田・柏原）を業務AI側で勝手に実装しない。`review.miyamoto / yoshida / kashiwabara` ロール経由のみ
- 3要素評価（実現可能性 / 収益性 / リスク）は `decision.feasibility` ロール経由のみ
- Decision Engine のプロンプト（`packages/prompts/decision/*` および `packages/prompts/review/*`）に対する変更は、改定 Issue を立てて AI レビュー＋人間レビュー必須（CLAUDE.md §17）

理由：判断軸を業務AIごとに書き散らかすと、整合性維持コストが跳ね上がり、Colobizらしさが時間とともに分散する。Decision Engine を Single Source of Truth として運用する。

---

## 13. CI/CD と AI レビュー

### 13.1 PR時の必須チェック

- `ci.yml`：Lint / Type check / 単体テスト
- `ai-review.yml`：AIレビューコメント自動投稿（Azure OpenAI または Vertex AI）

これらが grees にならない限りマージ不可。

### 13.2 AIレビューを通したい時

- AIレビューが指摘した内容に必ず**対応またはコメントで反論**する
- 「AIが言ってるから」と盲目的に従わない。判断は人間
- 「AIが見落としそうな点」を意識して人間レビューを補強

### 13.3 自動デプロイ

- `release/stg` への push → STG ECS デプロイ（自動）
- `release/prod` への push → 本番 ECS デプロイ（**手動承認必須**）

---

## 14. トラブル時の動き方

### 14.1 仕様が分からない

1. まず本書 → AGENTS.md → 設計書（docs/design/）を順に読む
2. それでも解決しない場合は Issue で質問（Slackで宮本にメンションも可）
3. 推測でコードを書かない

### 14.2 テストが落ちる

1. ローカルで再現
2. 落ちている根本原因を特定（症状ではなく原因）
3. テストを修正するのではなくコードを修正するのが原則
4. テスト自体に問題があれば、その理由をPRに書く

### 14.3 本番で問題が起きた

1. まずロールバックを検討（マスター設計書 22.1〜22.3）
2. ロールバック手順は `docs/runbook/` を参照
3. Hotfix ブランチを `main` から切る
4. 修正後、staging にも反映してフロー上の差分を消す

### 14.4 セキュリティインシデント

- シークレット漏洩を発見：即時 Slack #alert チャンネル＋宮本にDM、該当キーをローテーション
- Bedrock/Azure/Vertex への過剰アクセスを検知：CloudWatch アラームから誰がいつ何を呼んだかを確認

---

## 15. AIレビュー・実装AIへの追加ガイド

Claude Code が PR を作るときの心得：

1. **Issue の DoD を満たしているか必ず最後に再確認する**
2. **テストを必ず書く**：単体は最低、結合は影響があれば
3. **PRに「使ったプロンプトの要旨」を書く**：再現性のため
4. **設計書とのズレを発見したら、コードを書く前にIssueでコメント**
5. **本書の禁止事項に触れる依頼が来たら、実装する前に拒否する**：「CLAUDE.md §12 の規定により実行できません」と回答
6. **不明点は推測しない**：人間に聞く

---

## 16. 参考ドキュメント

- `docs/design/Colobiz_AI_Workspace_Phase1_開発設計書.docx` — マスター設計書
- `docs/design/Colobiz_AI_Workspace_Phase1_Memory機構_詳細設計書.docx`
- `docs/design/Colobiz_AI_Workspace_Phase1_STEP0_詳細設計書.docx`
- `docs/design/Colobiz_AI_Workspace_Phase1_DecisionEngine_詳細設計書.docx`
- `AGENTS.md` — エージェント別の運用ルール
- `CROSS_REVIEW_TEMPLATES.md` — クロスAIレビューのテンプレ集
- `infra/config/llm_routes.yaml` — LLM ルーティング設定
- `packages/prompts/` — プロンプトテンプレート（common / decision / review / 業務別）

---

## 17. 改定ルール

本書の改定は次の手順を取る：

1. 改定提案 Issue を立てる（理由・影響範囲を明記）
2. PR で本書を編集
3. **`code_review` ロール経由のAIレビュー＋人間レビュー（最低1名）必須**
4. 改定が承認されたら、コミットメッセージに `[CLAUDE.md] 何を変えたか` を明記
5. 既存のIssue・PRに影響する改定はSlack#announceに通知

---

**最後に：このリポジトリは『Colobizの業務記憶を持つAI基盤』を目指す。コード一行・PR一本・コメント一言が、その基盤の質を決める。慎重に、でも止まらず進めよう。**
