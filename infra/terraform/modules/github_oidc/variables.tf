variable "env" {
  type        = string
  description = "対象環境（stg / prod）。IAM Role 名 coloos-gha-deploy-{env} と SSM パラメータ /coloos/{env}/gha/role_arn に展開される"

  validation {
    condition     = contains(["stg", "prod"], var.env)
    error_message = "env must be stg or prod"
  }
}

variable "github_org" {
  type        = string
  description = "GitHub の組織またはユーザー名（例: Colo-bot05）。Trust Policy の sub 条件に使用"
}

variable "repo_name" {
  type        = string
  description = "GitHub リポジトリ名（例: coloOS）。Trust Policy の sub 条件に使用"
}

variable "create_oidc_provider" {
  type        = bool
  default     = true
  description = "新規に GitHub OIDC Provider を作成するか。AWS アカウント内で1つだけ存在できるので、最初の env（stg 想定）では true、以降は false にして既存 Provider を data source で参照する"
}

variable "protected_branches" {
  type        = list(string)
  default     = ["main", "staging", "release/stg", "release/prod"]
  description = "AssumeRole を許可する GitHub ブランチ名（リスト要素 b は refs/heads/<b> の形に展開して Trust Policy の sub 条件に固定値で並べる）。これを広げる変更（例: 末尾に 'feature/*' を追加）は CLAUDE.md / AGENTS.md 規約上禁止。GPT クロスレビュー F-009 厳格化の対象。"

  validation {
    condition     = length(var.protected_branches) > 0
    error_message = "protected_branches must contain at least one branch"
  }
}
