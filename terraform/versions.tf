terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket         = "agriconnect-tfstate-893431614084"
    key            = "agriconnect/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "agriconnect-tfstate-lock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}


# updated
# scan informational
# cleaned orphans
# retrigger
