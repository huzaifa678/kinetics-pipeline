data "aws_caller_identity" "current" {}

locals {
  _mlflow_arn    = one(module.mlflow[*].tracking_server_arn)
  _mlflow_bucket = one(module.mlflow[*].artifact_bucket_name)
  _spa_url       = one(module.frontend[*].spa_url)
  _cognito_iss   = one(module.cognito[*].issuer)
  _cognito_spa   = one(module.cognito[*].spa_client_id)
  _cognito_mach  = one(module.cognito[*].machine_client_id)
  _waf_arn       = one(aws_wafv2_web_acl.inference_api[*].arn)
  _amp_url       = module.observability.amp_remote_write_url

  gitops_contract = {
    environment = var.environment
    region      = var.region
    account_id  = data.aws_caller_identity.current.account_id

    data_bucket                = module.storage.data_bucket_name
    checkpoint_bucket          = module.storage.checkpoint_bucket_name
    mlflow_artifact_bucket     = local._mlflow_bucket == null ? "" : local._mlflow_bucket
    mlflow_tracking_server_arn = local._mlflow_arn == null ? "" : local._mlflow_arn

    amp_remote_write_url = local._amp_url == null ? "" : local._amp_url

    inference_host        = var.inference_domain_name != "" ? var.inference_domain_name : ""
    inference_api_host    = var.api_domain_name != "" ? var.api_domain_name : ""
    inference_api_waf_arn = local._waf_arn == null ? "" : local._waf_arn
    spa_url               = local._spa_url == null ? "" : local._spa_url

    cognito_issuer            = local._cognito_iss == null ? "" : local._cognito_iss
    cognito_spa_client_id     = local._cognito_spa == null ? "" : local._cognito_spa
    cognito_machine_client_id = local._cognito_mach == null ? "" : local._cognito_mach
  }
}

resource "aws_ssm_parameter" "gitops_contract" {
  name = "/${var.project}/${var.environment}/gitops-contract"
  type = "String"

  value = jsonencode(local.gitops_contract)

  description = "Non-secret Terraform outputs consumed by the CD repo's values renderer. Machine-owned."
  tags        = local.common_tags
}

output "gitops_contract_parameter" {
  description = "SSM parameter the CD render-and-PR workflow reads to build values/generated/<env>.yaml."
  value       = aws_ssm_parameter.gitops_contract.name
}

output "gitops_contract" {
  description = "The same payload, for local inspection: `terraform output -json gitops_contract`."
  value       = local.gitops_contract
}
