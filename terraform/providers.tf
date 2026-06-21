provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# WAF for CloudFront must be created in us-east-1 (CloudFront requirement)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
