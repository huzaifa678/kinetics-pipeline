include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/cluster"
}

dependency "infra" {
  config_path  = "../infra"
  skip_outputs = true
}

inputs = local.env.inputs
