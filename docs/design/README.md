# 設計書置き場

Colobiz AI Workspace Phase 1 の設計書（docx）を格納するディレクトリ。

## 配置済み設計書

| ファイル | 内容 | 主な参照箇所 |
|---|---|---|
| `Colobiz_AI_Workspace_Phase1_開発設計書.docx` | マスター設計書（Phase 1 全体の開発設計兼手順書） | CLAUDE.md §16 / 全 Issue |
| `Colobiz_AI_Workspace_Phase1_Memory機構_詳細設計書.docx` | Memory 機構の詳細設計（user/project memories, conversation_summaries, build_context() 等） | CLAUDE.md §10 |
| `Colobiz_AI_Workspace_Phase1_STEP0_詳細設計書.docx` | STEP 0（基盤整備：ST0-1 〜 ST0-26）の詳細設計 | ST0-1 〜 ST0-6 Issue |
| `Colobiz_AI_Workspace_Phase1_DecisionEngine_詳細設計書.docx` | Colobiz Decision Engine（思考OS：判断軸 / 3視点レビュー / 逆算順算 / 3要素評価 / 再現性チェック）の詳細設計 | CLAUDE.md §10 / §12.10 |

## 取り扱いルール

- 本ディレクトリは「正の仕様（Single Source of Truth）」を保管する場所。CLAUDE.md と矛盾した場合は、勝手にどちらか優先せず宮本に確認する（CLAUDE.md §0）。
- docx 本体の改定は別途「改定 Issue」を立て、CLAUDE.md §17 / AGENTS.md §10 に従って PR 化する。
- 各 Issue・PR から本書の参照箇所を `§N.M` 形式で必ずリンクする。
- 本ディレクトリに新規設計書を追加した場合は、本 README.md の表も更新すること。

## 関連ドキュメント

- [../../CLAUDE.md](../../CLAUDE.md) — 実装AI憲法
- [../../AGENTS.md](../../AGENTS.md) — エージェント別運用ルール
- [../issues/](../issues) — Issue ドラフト（ST0-1 〜 ST0-6）
