# ── App URL ───────────────────────────────────────────────────────────────────
output "cloudfront_url" {
  description = "Primary app URL (HTTPS + WAF)"
  value       = module.cloudfront.cloudfront_url
}

output "frontend_bucket" {
  description = "S3 bucket for frontend static files"
  value       = aws_s3_bucket.frontend.bucket
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (for cache invalidation)"
  value       = module.cloudfront.distribution_id
}

# ── EKS ───────────────────────────────────────────────────────────────────────
output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

output "eks_services_irsa_role_arn" {
  value = module.eks.services_irsa_role_arn
}

output "eks_lb_controller_role_arn" {
  value = module.eks.lb_controller_role_arn
}

output "eks_ecr_registry" {
  value = module.eks.ecr_registry
}

output "eks_alb_dns_name" {
  description = "EKS ALB DNS (managed by K8s LB controller — update eks_alb_dns_name in tfvars after bootstrap)"
  value       = var.eks_alb_dns_name
}

# ── RDS ───────────────────────────────────────────────────────────────────────
output "rds_endpoint" {
  value     = module.rds.endpoint
  sensitive = true
}

# ── SNS / SQS ─────────────────────────────────────────────────────────────────
output "sns_events_arn" {
  value = aws_sns_topic.events.arn
}

output "sqs_notifications_url" {
  value = aws_sqs_queue.notifications.url
}

# ── Chatbots ──────────────────────────────────────────────────────────────────
output "farmbot_api_url" {
  description = "FarmBot POST endpoint — set as VITE_FARMBOT_API_URL in frontend build"
  value       = "${trimsuffix(aws_apigatewayv2_stage.farmbot.invoke_url, "/")}/chat"
}

output "buyerbot_api_url" {
  description = "BuyerBot POST endpoint — set as VITE_BUYERBOT_API_URL in frontend build"
  value       = "${trimsuffix(aws_apigatewayv2_stage.buyerbot.invoke_url, "/")}/chat"
}

# ── Secrets ───────────────────────────────────────────────────────────────────
output "secret_database_arn" {
  value = aws_secretsmanager_secret.database.arn
}

# ── Cost Estimation ────────────────────────────────────────────────────────────
output "cost_estimation" {
  description = "Approximate monthly cost breakdown for deployed resources (ap-south-1, USD)"
  value = {
    eks_nodes         = "${var.eks_node_desired_size}x ${var.eks_node_instance_type} nodes = ~$${var.eks_node_desired_size * 15}/mo"
    eks_control_plane = "EKS cluster fee = ~$72/mo"
    rds               = "db.t3.micro 20 GB PostgreSQL = ~$15/mo"
    nat_gateway       = "1x NAT Gateway + data transfer = ~$33+/mo"
    alb               = "1x Application Load Balancer = ~$18/mo"
    cloudfront        = "CloudFront CDN (low traffic) = ~$1-5/mo"
    s3                = "S3 buckets (images + frontend + tfstate) = ~$2-5/mo"
    lambda_fns        = "3x Lambda (pay-per-request) = ~$0-2/mo"
    sns_sqs           = "SNS + SQS event pipeline = ~$0-1/mo"
    secrets_manager   = "1 secret = ~$0.40/mo"
    cloudwatch        = "5 log groups (30-day retention) = ~$1-3/mo"
    total_estimate    = "~$160-175/month (EKS nodes + NAT Gateway = ~70% of cost)"
    optimization_tip  = "Add VPC endpoints for S3 and SQS to cut NAT Gateway data charges"
  }
}
