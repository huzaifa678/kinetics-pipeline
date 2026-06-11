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
