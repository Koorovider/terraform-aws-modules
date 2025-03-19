terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
    project_map_tag = {
        map-migrated = "terraform"
    }
}

provider "aws" {  # 아시아태평양 (서울) -> seoul
    role_arn    = ""
    alias       = "seoul"
    region      = "ap-northeast-2"
}