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
