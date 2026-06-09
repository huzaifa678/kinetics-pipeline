variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name, used as a prefix and tag on all resources."
  type        = string
  default     = "kinetics-pipeline"
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod)."
  type        = string
  default     = "dev"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to spread subnets across."
  type        = number
  default     = 2
}

# ---------------------------------------------------------------------------
# EKS
# ---------------------------------------------------------------------------
variable "kubernetes_version" {
  description = "EKS control-plane Kubernetes version."
  type        = string
  default     = "1.30"
}

variable "system_node_instance_type" {
  description = "Instance type for the small, always-on CPU system node group (controllers, ArgoCD, etc.)."
  type        = string
  default     = "m6i.large"
}

variable "system_node_desired_size" {
  description = "Desired size of the CPU system node group."
  type        = number
  default     = 2
}

variable "cluster_admin_principal_arns" {
  description = <<-EOT
    IAM principal ARNs granted EKS cluster-admin via access entries
    (AmazonEKSClusterAdminPolicy). The cluster-creator implicit admin grant is
    disabled, so set at least one admin principal here (e.g. your SSO admin role
    ARN) or no one will have kubectl admin on the cluster.
  EOT
  type        = list(string)
  default     = []
}

variable "enable_hyperpod_operator" {
  description = "Install the SageMaker HyperPod training operator EKS add-on. Set false for a minimal EKS-only test cluster."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = <<-EOT
    EXTRA CIDR blocks allowed to reach the public EKS API endpoint, on top of the
    VPC NAT gateway EIP (the AWS Client VPN egress) which is added automatically
    in main.tf. Leave empty to allow ONLY the VPN egress. Add CIDRs here for
    anything that runs `terraform apply` from outside the VPN, e.g. your CI
    runner's egress IP (["203.0.113.10/32"]). Network control only; IAM access
    entries still govern who can authenticate.
  EOT
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# AWS Client VPN (SAML / IAM Identity Center federated auth)
# ---------------------------------------------------------------------------
variable "enable_client_vpn" {
  description = <<-EOT
    Provision an AWS Client VPN into the VPC. Requires vpn_saml_metadata_file
    (the metadata XML of the Client VPN app you create in IAM Identity Center).
    Leave false until that SAML app exists.
  EOT
  type        = bool
  default     = false
}

variable "vpn_client_cidr_block" {
  description = "IPv4 CIDR for VPN clients. Must not overlap the VPC CIDR; min /22."
  type        = string
  default     = "10.100.0.0/22"
}

variable "vpn_saml_metadata_file" {
  description = <<-EOT
    Path to the SAML IdP metadata XML for the Client VPN app in IAM Identity
    Center (relative to the terraform/ dir). Required when enable_client_vpn.
  EOT
  type        = string
  default     = ""
}

variable "vpn_self_service_saml_metadata_file" {
  description = "Optional path to the self-service portal SAML metadata XML. Empty disables the portal."
  type        = string
  default     = ""
}

variable "vpn_saml_application_arn" {
  description = "IAM Identity Center custom SAML app ARN for the Client VPN. When set, the users/groups below are assigned to it (replaces manual assignment)."
  type        = string
  default     = ""
}

variable "vpn_saml_assignment_user_names" {
  description = "Identity Center usernames to assign to the Client VPN SAML app."
  type        = list(string)
  default     = []
}

variable "vpn_saml_assignment_group_display_names" {
  description = "Identity Center group display names to assign to the Client VPN SAML app."
  type        = list(string)
  default     = []
}

variable "vpn_split_tunnel" {
  description = "Split tunnel (true, recommended) vs full tunnel (all client traffic via the VPC NAT)."
  type        = bool
  default     = true
}

variable "vpn_authorize_internet" {
  description = "Route 0.0.0.0/0 through the VPC NAT for VPN clients (needed only for EKS *public* endpoint access over the VPN)."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# HyperPod GPU training cluster
# ---------------------------------------------------------------------------
variable "gpu_instance_type" {
  description = "GPU instance type for the HyperPod training instance group (e.g. ml.g5.12xlarge, ml.g6e.12xlarge, ml.p5.48xlarge)."
  type        = string
  default     = "ml.g5.12xlarge"
}

variable "gpu_instance_count" {
  description = <<-EOT
    Number of GPU nodes in the HyperPod training instance group.
    COST CONTROL: defaults to 0 (scale-to-zero) so you never pay for idle GPUs.
    Set to N only while a training run is active, then return to 0.
  EOT
  type        = number
  default     = 0
}

variable "gpu_threads_per_core" {
  description = "Threads per core for GPU nodes. Set to 1 to disable hyperthreading for training workloads."
  type        = number
  default     = 1
}

# ---------------------------------------------------------------------------
# Cost guardrails
# ---------------------------------------------------------------------------
variable "monthly_budget_usd" {
  description = "Hard monthly cost budget in USD. Alerts fire at 50/80/100% of this."
  type        = number
  default     = 100
}

variable "budget_alert_emails" {
  description = "Email addresses that receive budget + anomaly alerts."
  type        = list(string)
  default     = []
}

variable "auto_stop_idle_minutes" {
  description = "Scale GPU instance group to 0 after this many minutes with no active training job. 0 disables the auto-stop guard."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------
variable "fsx_storage_capacity_gb" {
  description = "FSx for Lustre capacity in GiB (provisioned, billed). Size to your working set; tear down when idle."
  type        = number
  default     = 1200
}

variable "checkpoint_retention_days" {
  description = "Days before old checkpoints transition to S3 Infrequent Access, then expire."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# Experiment tracking (SageMaker-managed MLflow)
# ---------------------------------------------------------------------------
variable "enable_mlflow" {
  description = <<-EOT
    Provision a SageMaker-managed MLflow tracking server + artifact bucket for
    experiment tracking. COST: the server bills hourly while running, so turn
    this off (or destroy module.mlflow) between experiment campaigns.
  EOT
  type        = bool
  default     = true
}

variable "mlflow_tracking_server_size" {
  description = "MLflow tracking server size: Small | Medium | Large. Small is cheapest."
  type        = string
  default     = "Small"
}

variable "mlflow_version" {
  description = "MLflow version for the managed tracking server. Verify the version is offered in your region before applying."
  type        = string
  default     = "2.16.2"
}

variable "mlflow_automatic_model_registration" {
  description = "Auto-register logged models into the SageMaker Model Registry."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# GitOps
# ---------------------------------------------------------------------------
variable "enable_argocd" {
  description = "Install ArgoCD and bootstrap the app-of-apps for GitOps-managed workloads."
  type        = bool
  default     = true
}

variable "gitops_repo_url" {
  description = "Git repository URL that ArgoCD watches for application manifests."
  type        = string
  default     = "https://github.com/huzaifa678/Kinetics-Continious-Delivery.git"
}

variable "gitops_repo_revision" {
  description = "Git revision (branch/tag) ArgoCD tracks."
  type        = string
  default     = "main"
}
