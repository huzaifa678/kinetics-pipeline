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

inputs = merge(local.env.inputs, {
  manage_argocd            = true
  manage_incluster_addons  = false
  enable_argocd            = true
  enable_hyperpod_operator = true

  gitops_repo_url      = "https://github.com/huzaifa678/Kinetics-Continious-Delivery.git"
  gitops_repo_revision = "main"
})
