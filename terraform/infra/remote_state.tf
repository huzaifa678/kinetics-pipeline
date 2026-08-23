data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "kinetics-pipeline-bucket-ec371a2a"
    key    = "kinetics-pipeline-bucket/network.tfstate"
    region = "us-east-1"
  }
}

locals {
  network = data.terraform_remote_state.network.outputs
}
