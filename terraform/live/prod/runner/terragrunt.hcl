include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/runner"
}

dependency "network" {
  config_path  = "../network"
  skip_outputs = true
}

inputs = local.env.inputs
