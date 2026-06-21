# ── CloudWatch Log Groups ─────────────────────────────────────────────────────

# EKS Container Insights — application and dataplane logs
resource "aws_cloudwatch_log_group" "eks_application" {
  name              = "/aws/containerinsights/${module.eks.cluster_name}/application"
  retention_in_days = 30
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "eks_dataplane" {
  name              = "/aws/containerinsights/${module.eks.cluster_name}/dataplane"
  retention_in_days = 30
  tags              = local.common_tags
}

# Lambda function logs — explicit groups with retention (prevents unbounded growth)
resource "aws_cloudwatch_log_group" "lambda_weather_alert" {
  name              = "/aws/lambda/weather-alert-processor"
  retention_in_days = 30
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "lambda_farmbot" {
  name              = "/aws/lambda/farmbot-chatbot"
  retention_in_days = 30
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "lambda_buyerbot" {
  name              = "/aws/lambda/buyerbot-chatbot"
  retention_in_days = 30
  tags              = local.common_tags
}
