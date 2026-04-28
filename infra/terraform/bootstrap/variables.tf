variable "env" {
  type        = string
  description = "対象環境（stg / prod）。S3 バケット名 coloos-tfstate-{env} に展開される"
  validation {
    condition     = contains(["stg", "prod"], var.env)
    error_message = "env must be stg or prod"
  }
}

variable "create_lock_table" {
  type        = bool
  default     = true
  description = "DynamoDB ロックテーブル coloos-tflock を作成するか。stg apply で true（初回作成）、prod apply で false（共有のため作成不要）"
}
