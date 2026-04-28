terraform {
  backend "s3" {
    bucket         = "coloos-tfstate-stg"
    key            = "stg/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "coloos-tflock"
    encrypt        = true
  }
}
