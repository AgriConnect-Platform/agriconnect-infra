terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket       = "agriconnect-tfstate-978594443309"
    key          = "agriconnect/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
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
