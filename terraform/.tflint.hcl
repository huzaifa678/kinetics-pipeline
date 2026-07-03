config {
  # "local" so tflint lints our ./modules/* but doesn't try to load the external
  # terraform-aws-modules wrappers (vpc/eks), which would need a per-dir init.
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Child modules inherit Terraform + provider version pins from the root stack
# (versions.tf); re-declaring them in every module is noise, not safety.
rule "terraform_required_version" {
  enabled = false
}

rule "terraform_required_providers" {
  enabled = false
}

plugin "aws" {
  enabled = true
  version = "0.37.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
