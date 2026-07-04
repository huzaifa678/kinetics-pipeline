# Read the INFRA layer's state for cluster connection + IAM role ARNs + the flags
# that gate both layers. Same bucket, the infra key.
data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "kinetics-pipeline-bucket-ec371a2a"
    key    = "kinetics-pipeline-bucket/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  infra = data.terraform_remote_state.infra.outputs

  common_tags = {
    Project     = var.project
    Environment = local.infra.environment
    ManagedBy   = "terraform"
  }
}
