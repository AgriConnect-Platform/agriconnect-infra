# ── AWS ───────────────────────────────────────────────────────────────────────
aws_region = "ap-south-1"

# ── Networking ────────────────────────────────────────────────────────────────
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
availability_zones   = ["ap-south-1a", "ap-south-1b"]

# ── RDS ───────────────────────────────────────────────────────────────────────
rds_db_name  = "agriconnect"
rds_username = "admin"
# rds_password → set via TF_VAR_rds_password (GitHub Secret)

# ── S3 ────────────────────────────────────────────────────────────────────────
s3_produce_images_bucket  = "agriconnect-produce-images-893431614084"
s3_delivery_proofs_bucket = "agriconnect-delivery-proofs-893431614084"

# ── JWT ───────────────────────────────────────────────────────────────────────
# jwt_secret → set via TF_VAR_jwt_secret (GitHub Secret)
jwt_expiry = "24h"

# ── SMTP ──────────────────────────────────────────────────────────────────────
smtp_host = "smtp.gmail.com"
smtp_port = 587
smtp_user = "asadchamp109@gmail.com"
# smtp_pass → set via TF_VAR_smtp_pass (GitHub Secret)
smtp_from = "AgriConnect <asadchamp109@gmail.com>"

# ── Notifications ─────────────────────────────────────────────────────────────
admin_email                 = "asadchamp109@gmail.com"
weather_schedule_expression = "rate(6 hours)"

# ── EKS ───────────────────────────────────────────────────────────────────────
eks_node_instance_type = "t3.medium"
eks_node_desired_size  = 2
eks_node_min_size      = 2
eks_node_max_size      = 4
eks_alb_dns_name       = "k8s-producti-agriconn-86a24bc09e-951364039.ap-south-1.elb.amazonaws.com"
