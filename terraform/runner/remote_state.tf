# The runner just needs the VPC (vpc_id + private subnets) from the infra layer.
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
}
