variable "region" {
  type        = string
  default     = "ap-northeast-1"
  description = "AWS リージョン"
}

variable "env" {
  type        = string
  default     = "prod"
  description = "対象環境（stg / prod）"

  validation {
    condition     = contains(["stg", "prod"], var.env)
    error_message = "env must be stg or prod"
  }
}
