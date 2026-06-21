output "common_sg_id" { value = aws_security_group.common.id }
output "lambda_role_arn" { value = aws_iam_role.lambda.arn }
output "scheduler_role_arn" { value = aws_iam_role.scheduler.arn }
