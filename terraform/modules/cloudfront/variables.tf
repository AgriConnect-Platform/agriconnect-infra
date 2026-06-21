variable "alb_dns_name" {
  description = "ALB DNS name (CloudFront origin for /api/*)"
  type        = string
}

variable "s3_website_endpoint" {
  description = "S3 website endpoint for frontend static files"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
