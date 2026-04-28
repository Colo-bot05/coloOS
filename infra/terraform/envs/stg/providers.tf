provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project    = "coloos"
      Env        = var.env
      ManagedBy  = "terraform"
      Repository = "Colo-bot05/coloOS"
    }
  }
}
