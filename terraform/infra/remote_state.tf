data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "kinetics-pipeline-bucket-ec371a2a"
    key    = "kinetics-pipeline-bucket/network.tfstate"
    region = "us-east-1"
  }
}

locals {
  # TEARDOWN OVERRIDE (temporary): the network layer's state was partially
  # destroyed out of order — its outputs were emptied while these VPC resources
  # still exist in AWS — which left local.network empty and blocked
  # `terragrunt destroy` on infra ("local.network is object with no attributes").
  # Hardcode the real values so infra can evaluate its config and destroy every
  # resource by its own state ID. REVERT this block (back to
  # data.terraform_remote_state.network.outputs) once the teardown is done.
  network = {
    vpc_id             = "vpc-07385106becfce474"
    vpc_cidr           = "10.0.0.0/16"
    private_subnet_ids = ["subnet-02f98b3e02494f9e6", "subnet-08b0390ffe299da8c"]
    nat_public_ips     = ["13.217.157.123"]
  }
}
