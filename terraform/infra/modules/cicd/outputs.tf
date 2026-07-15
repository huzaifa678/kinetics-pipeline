output "oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN."
  value       = local.provider_arn
}

output "ecr_push_role_arn" {
  description = "Role ARN for docker-build.yml (AWS_ROLE_ECR_PUSH secret/var)."
  value       = aws_iam_role.ecr_push.arn
}

output "terraform_plan_role_arn" {
  description = "Role ARN for terraform-plan.yml (AWS_ROLE_TF_PLAN)."
  value       = aws_iam_role.tf_plan.arn
}

output "terraform_apply_role_arn" {
  description = "Role ARN for terraform-apply.yml (AWS_ROLE_TF_APPLY)."
  value       = aws_iam_role.tf_apply.arn
}

output "frontend_deploy_role_arn" {
  description = "Role ARN for frontend-deploy.yml (AWS_ROLE_FRONTEND_DEPLOY); null when the frontend isn't enabled."
  value       = var.frontend_bucket_arn != "" ? aws_iam_role.frontend_deploy[0].arn : null
}

output "cluster_bootstrap_role_arn" {
  description = "Role ARN for cluster-bootstrap.yml (AWS_ROLE_CLUSTER_BOOTSTRAP). Gated to the protected environment; the ONLY principal granted a cluster-admin EKS access entry."
  value       = aws_iam_role.cluster_bootstrap.arn
}

output "gitops_contract_read_role_arn" {
  description = "Role ARN for gitops-values.yml (AWS_ROLE_GITOPS_CONTRACT_READ). Read-only on /*/gitops-contract."
  value       = aws_iam_role.gitops_contract_read.arn
}
