output "cluster_name" { value = aws_eks_cluster.main.name }
output "cluster_endpoint" { value = aws_eks_cluster.main.endpoint }
output "cluster_ca" { value = aws_eks_cluster.main.certificate_authority[0].data }
output "oidc_provider_arn" { value = aws_iam_openid_connect_provider.eks.arn }
output "services_irsa_role_arn" { value = aws_iam_role.services.arn }
output "lb_controller_role_arn" { value = aws_iam_role.lb_controller.arn }
output "node_group_sg_id" { value = aws_eks_node_group.main.resources[0].remote_access_security_group_id }
output "ecr_registry" { value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com" }
