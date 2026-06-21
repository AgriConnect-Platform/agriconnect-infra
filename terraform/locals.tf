data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  workspace_env = terraform.workspace == "default" ? "dev" : terraform.workspace

  workspace_config = {
    dev = {
      rds_instance_class    = "db.t3.micro"
      rds_allocated_storage = 20
    }
    prod = {
      rds_instance_class    = "db.t3.small"
      rds_allocated_storage = 50
    }
  }

  config = local.workspace_config[local.workspace_env]

  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.name
  name_prefix = "${var.project_name}-${local.workspace_env}"

  common_tags = {
    Project     = var.project_name
    Environment = local.workspace_env
    ManagedBy   = "Terraform"
    Owner       = "asadchamp109@gmail.com"
  }
}
