# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  AgriConnect — Root Terraform Configuration (EKS)                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ── Lambda package (weather alert) ───────────────────────────────────────────
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda/weather-alert-processor/index.js"
  output_path = "${path.module}/lambda_package.zip"
}

# ── Modules ───────────────────────────────────────────────────────────────────

module "networking" {
  source               = "./modules/networking"
  name_prefix          = local.name_prefix
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

module "security" {
  source = "./modules/security"
  vpc_id = module.networking.vpc_id
}

module "rds" {
  source             = "./modules/rds"
  name_prefix        = local.name_prefix
  private_subnet_ids = module.networking.private_subnet_ids
  common_sg_id       = module.security.common_sg_id
  rds_instance_class = local.config.rds_instance_class
  allocated_storage  = local.config.rds_allocated_storage
  db_name            = var.rds_db_name
  db_username        = var.rds_username
  db_password        = var.rds_password
}

module "s3" {
  source                 = "./modules/s3"
  produce_images_bucket  = var.s3_produce_images_bucket
  delivery_proofs_bucket = var.s3_delivery_proofs_bucket
}

module "eks" {
  source                = "./modules/eks"
  name_prefix           = local.name_prefix
  vpc_id                = module.networking.vpc_id
  public_subnet_ids     = module.networking.public_subnet_ids
  private_subnet_ids    = module.networking.private_subnet_ids
  node_instance_type    = var.eks_node_instance_type
  node_desired_size     = var.eks_node_desired_size
  node_min_size         = var.eks_node_min_size
  node_max_size         = var.eks_node_max_size
  rds_security_group_id = module.security.common_sg_id
}

# ── Frontend S3 Bucket ────────────────────────────────────────────────────────

resource "aws_s3_bucket" "frontend" {
  bucket        = "agriconnect-frontend-${local.account_id}"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  index_document { suffix = "index.html" }
  error_document { key = "index.html" }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket     = aws_s3_bucket.frontend.id
  depends_on = [aws_s3_bucket_public_access_block.frontend]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicRead"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
    }]
  })
}

module "cloudfront" {
  source = "./modules/cloudfront"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  alb_dns_name        = var.eks_alb_dns_name
  s3_website_endpoint = aws_s3_bucket_website_configuration.frontend.website_endpoint
  tags                = local.common_tags
}

# ── Secrets Manager ───────────────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "database" {
  name                    = "agriconnect/${local.workspace_env}/database"
  description             = "RDS MySQL credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "database" {
  secret_id = aws_secretsmanager_secret.database.id
  secret_string = jsonencode({
    host     = module.rds.endpoint
    port     = 3306
    database = var.rds_db_name
    username = var.rds_username
    password = var.rds_password
  })
}

resource "aws_secretsmanager_secret" "jwt" {
  name                    = "agriconnect/${local.workspace_env}/jwt"
  description             = "JWT signing secret"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id = aws_secretsmanager_secret.jwt.id
  secret_string = jsonencode({
    jwt_secret = var.jwt_secret
    jwt_expiry = var.jwt_expiry
  })
}

resource "aws_secretsmanager_secret" "aws_creds" {
  name                    = "agriconnect/${local.workspace_env}/aws"
  description             = "AWS credentials — pods use IRSA, no keys needed"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "aws_creds" {
  secret_id = aws_secretsmanager_secret.aws_creds.id
  secret_string = jsonencode({
    access_key = "USE_IRSA"
    secret_key = "USE_IRSA"
    region     = var.aws_region
  })
}

resource "aws_secretsmanager_secret" "email" {
  name                    = "agriconnect/${local.workspace_env}/email"
  description             = "SMTP email credentials for notifications"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "email" {
  secret_id = aws_secretsmanager_secret.email.id
  secret_string = jsonencode({
    host = var.smtp_host
    port = var.smtp_port
    user = var.smtp_user
    pass = var.smtp_pass
    from = var.smtp_from != "" ? var.smtp_from : var.smtp_user
  })
}

resource "aws_secretsmanager_secret" "s3" {
  name                    = "agriconnect/${local.workspace_env}/s3"
  description             = "S3 bucket names for media uploads"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "s3" {
  secret_id = aws_secretsmanager_secret.s3.id
  secret_string = jsonencode({
    produce_bucket  = var.s3_produce_images_bucket
    delivery_bucket = var.s3_delivery_proofs_bucket
    region          = var.aws_region
  })
}

# ── SNS Topics ────────────────────────────────────────────────────────────────

resource "aws_sns_topic" "weather_alerts" {
  name = "AgriConnect-WeatherAlerts"
}

resource "aws_sns_topic" "events" {
  name = "AgriConnect-Events"
}

# ── SQS Queues ────────────────────────────────────────────────────────────────

resource "aws_sqs_queue" "notifications_dlq" {
  name                      = "AgriConnect-Notifications-DLQ"
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "notifications" {
  name                       = "AgriConnect-Notifications-Queue"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.notifications_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue_policy" "notifications" {
  queue_url = aws_sqs_queue.notifications.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowSNSPublish"
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.notifications.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_sns_topic.events.arn }
      }
    }]
  })
}

resource "aws_sns_topic_subscription" "events_to_sqs" {
  topic_arn = aws_sns_topic.events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.notifications.arn
}

resource "aws_sns_topic_subscription" "admin_weather_alerts" {
  count     = var.admin_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.weather_alerts.arn
  protocol  = "email"
  endpoint  = var.admin_email
}

resource "aws_sns_topic_subscription" "admin_farmbot_critical" {
  count     = var.admin_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.farmbot_critical.arn
  protocol  = "email"
  endpoint  = var.admin_email
}

# ── Weather Alert Lambda ───────────────────────────────────────────────────────

resource "aws_lambda_function" "weather_alert" {
  function_name    = "weather-alert-processor"
  role             = module.security.lambda_role_arn
  handler          = "index.handler"
  runtime          = "nodejs18.x"
  timeout          = 60
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN    = aws_sns_topic.weather_alerts.arn
      EVENTS_TOPIC_ARN = aws_sns_topic.events.arn
    }
  }
}

resource "aws_lambda_permission" "scheduler_invoke" {
  statement_id  = "AllowSchedulerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.weather_alert.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = "arn:aws:scheduler:${var.aws_region}:${local.account_id}:schedule/default/agriconnect-weather-check"
}

# ── EventBridge Scheduler ─────────────────────────────────────────────────────

resource "aws_scheduler_schedule" "weather_check" {
  name       = "agriconnect-weather-check"
  group_name = "default"
  state      = "ENABLED"

  flexible_time_window { mode = "OFF" }

  schedule_expression          = var.weather_schedule_expression
  schedule_expression_timezone = "Asia/Kolkata"

  target {
    arn      = aws_lambda_function.weather_alert.arn
    role_arn = module.security.scheduler_role_arn
  }

  depends_on = [aws_lambda_permission.scheduler_invoke]
}

# ── FarmBot Lambda + API Gateway ──────────────────────────────────────────────

data "archive_file" "farmbot" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/farmbot"
  output_path = "${path.module}/farmbot_package.zip"
}

resource "aws_s3_bucket" "farmbot_logs" {
  bucket        = var.farmbot_logs_bucket
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "farmbot_logs" {
  bucket                  = aws_s3_bucket.farmbot_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_sns_topic" "farmbot_critical" {
  name = "farmbot-critical-alerts"
}

resource "aws_iam_role" "farmbot_lambda" {
  name = "${local.name_prefix}-farmbot-lambda-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "farmbot_lambda" {
  name = "${local.name_prefix}-farmbot-lambda-policy"
  role = aws_iam_role.farmbot_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["bedrock:InvokeModel", "bedrock:Converse"], Resource = "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-lite-v1:0" },
      { Effect = "Allow", Action = ["s3:PutObject", "s3:GetObject"], Resource = "${aws_s3_bucket.farmbot_logs.arn}/*" },
      { Effect = "Allow", Action = ["sns:Publish"], Resource = aws_sns_topic.farmbot_critical.arn },
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "arn:aws:logs:*:*:*" }
    ]
  })
}

resource "aws_lambda_function" "farmbot" {
  function_name    = "farmbot-chatbot"
  role             = aws_iam_role.farmbot_lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.farmbot.output_path
  source_code_hash = data.archive_file.farmbot.output_base64sha256

  environment {
    variables = {
      BEDROCK_REGION    = "us-east-1"
      MODEL_ID          = "amazon.nova-lite-v1:0"
      S3_BUCKET_NAME    = aws_s3_bucket.farmbot_logs.bucket
      SNS_TOPIC_ARN     = aws_sns_topic.farmbot_critical.arn
      MAX_IMAGE_SIZE_MB = "5"
    }
  }
}

resource "aws_apigatewayv2_api" "farmbot" {
  name          = "farmbot-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_integration" "farmbot" {
  api_id                 = aws_apigatewayv2_api.farmbot.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.farmbot.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "farmbot" {
  api_id    = aws_apigatewayv2_api.farmbot.id
  route_key = "POST /chat"
  target    = "integrations/${aws_apigatewayv2_integration.farmbot.id}"
}

resource "aws_apigatewayv2_stage" "farmbot" {
  api_id      = aws_apigatewayv2_api.farmbot.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "farmbot_api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.farmbot.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.farmbot.execution_arn}/*/*"
}

# ── BuyerBot Lambda + API Gateway ─────────────────────────────────────────────

data "archive_file" "buyerbot" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/buyerbot"
  output_path = "${path.module}/buyerbot_package.zip"
}

resource "aws_iam_role" "buyerbot_lambda" {
  name = "${local.name_prefix}-buyerbot-lambda-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "buyerbot_lambda" {
  name = "${local.name_prefix}-buyerbot-lambda-policy"
  role = aws_iam_role.buyerbot_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["bedrock:InvokeModel", "bedrock:Converse"], Resource = "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-lite-v1:0" },
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "arn:aws:logs:*:*:*" }
    ]
  })
}

resource "aws_lambda_function" "buyerbot" {
  function_name    = "buyerbot-chatbot"
  role             = aws_iam_role.buyerbot_lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60
  filename         = data.archive_file.buyerbot.output_path
  source_code_hash = data.archive_file.buyerbot.output_base64sha256

  environment {
    variables = {
      BEDROCK_REGION = "us-east-1"
      MODEL_ID       = "amazon.nova-lite-v1:0"
      ALB_URL        = var.eks_alb_dns_name
    }
  }
}

resource "aws_apigatewayv2_api" "buyerbot" {
  name          = "buyerbot-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_integration" "buyerbot" {
  api_id                 = aws_apigatewayv2_api.buyerbot.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.buyerbot.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "buyerbot" {
  api_id    = aws_apigatewayv2_api.buyerbot.id
  route_key = "POST /chat"
  target    = "integrations/${aws_apigatewayv2_integration.buyerbot.id}"
}

resource "aws_apigatewayv2_stage" "buyerbot" {
  api_id      = aws_apigatewayv2_api.buyerbot.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "buyerbot_api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.buyerbot.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.buyerbot.execution_arn}/*/*"
}

# ── SSM Parameters (read by CI/CD pipelines — no hardcoding needed) ──────────

resource "aws_ssm_parameter" "farmbot_api_url" {
  name  = "/agriconnect/farmbot-api-url"
  type  = "String"
  value = "${trimsuffix(aws_apigatewayv2_stage.farmbot.invoke_url, "/")}/chat"
}

resource "aws_ssm_parameter" "buyerbot_api_url" {
  name  = "/agriconnect/buyerbot-api-url"
  type  = "String"
  value = "${trimsuffix(aws_apigatewayv2_stage.buyerbot.invoke_url, "/")}/chat"
}

resource "aws_ssm_parameter" "cloudfront_distribution_id" {
  name  = "/agriconnect/cloudfront-distribution-id"
  type  = "String"
  value = module.cloudfront.distribution_id
}

resource "aws_ssm_parameter" "eks_cluster_name" {
  name  = "/agriconnect/eks-cluster-name"
  type  = "String"
  value = module.eks.cluster_name
}

resource "aws_ssm_parameter" "eks_services_irsa_role_arn" {
  name  = "/agriconnect/eks-services-irsa-role-arn"
  type  = "String"
  value = module.eks.services_irsa_role_arn
}

resource "aws_ssm_parameter" "eks_lb_controller_role_arn" {
  name  = "/agriconnect/eks-lb-controller-role-arn"
  type  = "String"
  value = module.eks.lb_controller_role_arn
}

resource "aws_ssm_parameter" "public_subnet_ids" {
  name  = "/agriconnect/public-subnet-ids"
  type  = "String"
  value = join(",", module.networking.public_subnet_ids)
}
