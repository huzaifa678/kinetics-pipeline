locals {
  state_bucket = "kinetics-pipeline-bucket-ec371a2a"
  region       = "us-east-1"

  # Leaf directory name == layer name (live/infra -> "infra").
  layer = basename(get_terragrunt_dir())

  # EXACT existing keys — do not change or you fork the state.
  state_keys = {
    network = "kinetics-pipeline-bucket/network.tfstate"
    infra   = "kinetics-pipeline-bucket/terraform.tfstate" # historical name, kept
    cluster = "kinetics-pipeline-bucket/cluster.tfstate"
    runner  = "kinetics-pipeline-bucket/runner.tfstate"
  }
  state_key = local.state_keys[local.layer]
}

# Generates backend.tf into each unit — replaces the inline `backend "s3"` block
# in every layer's versions.tf.
remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket       = local.state_bucket
    key          = local.state_key
    region       = local.region
    use_lockfile = true
    encrypt      = true
  }
}

# Generates the base aws provider for the layers where it is byte-identical:
# network + infra (region = var.region, tags = local.common_tags). It is DISABLED
# for cluster + runner, whose aws provider differs and stays inline:
#   - cluster: region = local.infra.region (from the infra remote_state), and it
#     also declares kubernetes/helm/kubectl providers wired to infra outputs.
#   - runner: an inline default_tags map keyed off local.network.environment, and
#     it has no var.region-based common_tags local.
# Both keep their own provider block; here we only strip their backend block.
generate "provider_aws" {
  path      = "provider_aws.tf"
  if_exists = "overwrite_terragrunt"
  disable   = contains(["cluster", "runner"], local.layer)
  contents  = <<-EOF
    provider "aws" {
      region = var.region
      default_tags {
        tags = local.common_tags
      }
    }
  EOF
}
