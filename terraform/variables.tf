# ── Region & Naming ───────────────────────────────────────────────────────────
variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project_name" {
  type    = string
  default = "agriconnect"
}

# ── Networking ────────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "availability_zones" {
  type    = list(string)
  default = ["ap-south-1a", "ap-south-1b"]
}

# ── RDS ───────────────────────────────────────────────────────────────────────
variable "rds_db_name" {
  type    = string
  default = "agriconnect"
}

variable "rds_username" {
  type      = string
  sensitive = true
  default   = "admin"
}

variable "rds_password" {
  type      = string
  sensitive = true
}

# ── S3 ────────────────────────────────────────────────────────────────────────
variable "s3_produce_images_bucket" {
  type = string
}

variable "s3_delivery_proofs_bucket" {
  type = string
}

# ── FarmBot ───────────────────────────────────────────────────────────────────
variable "farmbot_logs_bucket" {
  type    = string
  default = "agriconnect-farmbot-logs"
}

# ── SMTP ──────────────────────────────────────────────────────────────────────
variable "smtp_host" {
  type    = string
  default = "smtp.gmail.com"
}

variable "smtp_port" {
  type    = number
  default = 587
}

variable "smtp_user" {
  type      = string
  default   = ""
  sensitive = true
}

variable "smtp_pass" {
  type      = string
  default   = ""
  sensitive = true
}

variable "smtp_from" {
  type    = string
  default = ""
}

# ── JWT ───────────────────────────────────────────────────────────────────────
variable "jwt_secret" {
  type      = string
  sensitive = true
}

variable "jwt_expiry" {
  type    = string
  default = "24h"
}

# ── Notifications ─────────────────────────────────────────────────────────────
variable "admin_email" {
  type    = string
  default = ""
}

variable "weather_schedule_expression" {
  type    = string
  default = "rate(6 hours)"
}

# ── EKS ───────────────────────────────────────────────────────────────────────
variable "eks_node_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "eks_node_desired_size" {
  type    = number
  default = 2
}

variable "eks_node_min_size" {
  type    = number
  default = 2
}

variable "eks_node_max_size" {
  type    = number
  default = 4
}

variable "eks_alb_dns_name" {
  description = "DNS name of the ALB created by the EKS AWS Load Balancer Controller (set after first bootstrap)"
  type        = string
  default     = ""
}
