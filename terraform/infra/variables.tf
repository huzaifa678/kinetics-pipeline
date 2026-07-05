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
  description = "EKS control-plane Kubernetes version. Keep on a STANDARD-support release ($0.10/hr); extended support (e.g. 1.30 after 2025-07) is $0.60/hr."
  type        = string
  default     = "1.34"
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

variable "cluster_deployer_principal_arns" {
  description = <<-EOT
    IAM principal ARNs (e.g. the CI apply role) granted a NON-admin EKS access
    entry mapped to the k8s group `kinetics:ci-deployers`. Authorization comes
    from the out-of-band `ci-deployer` ClusterRole bound to that group
    (terraform/rbac/ci-deployer.yaml) — the least privilege that can still
    `helm install` argocd for manage_argocd, without cluster-admin.
  EOT
  type        = list(string)
  default     = []
}

variable "cluster_viewer_principal_arns" {
  description = <<-EOT
    IAM principal ARNs (e.g. the CI plan role) granted a read-only EKS access
    entry (AmazonEKSAdminViewPolicy). Lets `terraform plan` refresh in-cluster
    resources without cluster-admin or write access.
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

# ---------------------------------------------------------------------------
# MSK (Kafka) — only needed for Seldon Core v2 Pipelines / async dataflow. The
# sync Model + A/B Experiment path does not use Kafka, so this defaults off.
# ---------------------------------------------------------------------------
variable "enable_msk" {
  description = <<-EOT
    Provision an Amazon MSK (Kafka) cluster for Seldon Core v2 Pipelines. Adds
    ~$0.10-0.13/hr (2x kafka.t3.small) — leave false unless you need Pipelines.
    When true, feed terraform output msk_bootstrap_brokers_tls into the CD repo's
    seldon-core-v2-runtime values.
  EOT
  type        = bool
  default     = false
}

variable "kafka_version" {
  description = "Apache Kafka version for the MSK cluster."
  type        = string
  default     = "3.6.0"
}

variable "msk_broker_instance_type" {
  description = "MSK broker instance type. kafka.t3.small is the dev cost floor."
  type        = string
  default     = "kafka.t3.small"
}

variable "msk_broker_ebs_volume_size" {
  description = "Per-broker EBS volume size in GiB."
  type        = number
  default     = 20
}

variable "msk_client_authentication" {
  description = "MSK client auth: unauthenticated (dev) | sasl_scram (prod) | iam. TLS in-transit is always on. tfvars.prod sets sasl_scram."
  type        = string
  default     = "unauthenticated"
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
# ---------------------------------------------------------------------------
# Container registry + CI/CD (GitHub Actions OIDC)
# ---------------------------------------------------------------------------
variable "ecr_repository_name" {
  description = "ECR repository name for the training image."
  type        = string
  default     = "kinetics-training"
}

variable "enable_self_hosted_runner" {
  description = "Create a self-hosted GitHub Actions runner in the VPC so CI can reach the VPN-locked EKS API (needed for manage_argocd). Requires github_owner/github_repo."
  type        = bool
  default     = false
}

# The OIDC provider + CI roles live in the bootstrap stack now; the main stack
# only references the provider ARN to trust it (e.g. the frontend-deploy role).
variable "github_oidc_provider_arn" {
  description = "GitHub OIDC provider ARN from the bootstrap stack (github_oidc_provider_arn output). Enables the frontend-deploy role."
  type        = string
  default     = ""
}

variable "github_owner" {
  description = "GitHub org/user that owns the infra repo."
  type        = string
  default     = "huzaifa678"
}

variable "github_repo" {
  description = "GitHub repo name holding this Terraform / the CI workflows."
  type        = string
  default     = "kinetics-pipeline"
}

variable "terraform_state_bucket" {
  description = "S3 bucket holding the Terraform remote state (granted to the plan role)."
  type        = string
  default     = "kinetics-pipeline-bucket-ec371a2a"
}

variable "enable_hyperpod" {
  description = <<-EOT
    Create the SageMaker HyperPod cluster (module.hyperpod). Default true. Set
    false for the FIRST infra apply on a cold bring-up: the SageMaker cluster
    CREATE fails until the ArgoCD-managed HyperPod dependency chart is installed
    (gotcha #1), and ArgoCD lives in the cluster layer which applies after infra.
    Bring it up with false, apply the cluster layer, then flip to true + re-apply.
    The HyperPod execution/autoscaler IAM roles (module.iam) are NOT gated by this.
  EOT
  type        = bool
  default     = true
}

variable "enable_gpu_autoscaling" {
  description = <<-EOT
    Use HyperPod's managed Karpenter autoscaling for GPU capacity. When true
    (default), GPU instance groups are created per-AZ at count 0 and Karpenter
    scales them on pending GPU pods with scale-to-zero — no scale-gpus.sh, and
    the auto-stop Lambda is disabled (Karpenter handles idle teardown).
    When false, falls back to the legacy single fixed-count group sized by
    gpu_instance_count.
  EOT
  type        = bool
  default     = true
}

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

variable "hyperpod_system_instance_count" {
  description = <<-EOT
    Count for the always-on NON-GPU HyperPod system instance group that hosts the
    training-operator controller. 1 = operator can run; 0 = no system node (cluster
    creates with 0 instances). Requires the "Total number of instances allowed
    across SageMaker HyperPod clusters" quota (L-3308CCC7) >= this; that quota is 0
    by default, so keep this 0 until the increase is granted.
  EOT
  type        = number
  default     = 1
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
  description = "MLflow version for the managed tracking server. Empty = let SageMaker pick the latest supported version (recommended)."
  type        = string
  default     = ""
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

variable "manage_incluster_addons" {
  description = "Let Terraform manage the in-cluster APP layer (cert-manager, LB controller, external-dns, HyperPod operator addons). Set false to let GitOps own them. ArgoCD itself is gated separately by manage_argocd. AWS-API resources are unaffected."
  type        = bool
  default     = true
}

variable "manage_argocd" {
  description = "Let Terraform manage the ArgoCD bootstrap layer (ArgoCD Helm release + in-cluster env Secret + app-of-apps). Requires cluster API reachability (enable_self_hosted_runner). When false, bootstrap ArgoCD out-of-band (gitops/bootstrap)."
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

# ---------------------------------------------------------------------------
# Inference ingress — internal ALB via the AWS Load Balancer Controller, with
# an ACM cert + Route53 record for a real HTTPS endpoint reachable over the
# Client VPN. All off/empty by default: existing runs stay ClusterIP-only.
# ---------------------------------------------------------------------------
variable "enable_aws_lb_controller" {
  description = "Install the AWS Load Balancer Controller (required for the inference Ingress to provision an ALB). Off by default."
  type        = bool
  default     = false
}

variable "enable_external_dns" {
  description = "Install external-dns so the inference ALB auto-registers its Route53 A-record (the ALB DNS name isn't known at apply time). Requires inference_route53_zone_id."
  type        = bool
  default     = false
}

variable "inference_domain_name" {
  description = "FQDN for the inference endpoint (e.g. inference.example.com). Empty = no ACM cert / DNS record is created."
  type        = string
  default     = ""
}

variable "inference_route53_zone_id" {
  description = "Route53 hosted zone ID for ACM DNS validation + the inference A-record. Required when inference_domain_name is set."
  type        = string
  default     = ""
}

variable "aws_lb_controller_chart_version" {
  description = "aws-load-balancer-controller Helm chart version (eks-charts)."
  type        = string
  default     = "1.13.3"
}

variable "external_dns_chart_version" {
  description = "external-dns Helm chart version (kubernetes-sigs)."
  type        = string
  default     = "1.15.2"
}


variable "enable_managed_prometheus" {
  description = "Create an Amazon Managed Service for Prometheus (AMP) workspace + a Pod Identity role so the in-cluster Prometheus can remote_write to it. Metrics then survive terraform destroy."
  type        = bool
  default     = false
}

variable "enable_managed_grafana" {
  description = <<-EOT
    Create an Amazon Managed Grafana (AMG) workspace (AMP + X-Ray datasources).
    NOTE: AMG requires IAM Identity Center (SSO) or SAML to log in — plain IAM
    users cannot sign in. Leave off until SSO/SAML is configured for the account.
  EOT
  type        = bool
  default     = false
}

variable "enable_xray_tracing" {
  description = "Create an X-Ray write role + Pod Identity association for the in-cluster OTel collector, so trainer/inference spans export to AWS X-Ray (the GitOps otel-collector values add the awsxray exporter). Traces then survive terraform destroy."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Public inference frontend: React SPA (S3+CloudFront) + Cognito auth + WAF.
# Prod-only; everything off/empty by default. Turning these on shifts the
# inference posture from VPN-internal to PUBLIC — gate it with WAF + JWT.
# ---------------------------------------------------------------------------
variable "enable_cognito" {
  description = "Create a Cognito user pool (SPA + machine app clients) for inference auth. The edge verifies the JWT when COGNITO_ISSUER is set."
  type        = bool
  default     = false
}

variable "enable_frontend" {
  description = "Host the React SPA on S3 + CloudFront (+ ACM/Route53). Requires frontend_domain_name + frontend_route53_zone_id."
  type        = bool
  default     = false
}

variable "enable_waf" {
  description = "Attach WAFv2 (managed common rules + rate limit) to the SPA CloudFront and the public inference ALB."
  type        = bool
  default     = false
}

variable "frontend_domain_name" {
  description = "FQDN the SPA is served at (e.g. app.example.com)."
  type        = string
  default     = ""
}

variable "api_domain_name" {
  description = "Public FQDN for the inference API ALB in prod (e.g. api.example.com). Empty keeps inference internal."
  type        = string
  default     = ""
}

variable "frontend_route53_zone_id" {
  description = "Route53 hosted zone for the SPA ACM cert + alias. Required when enable_frontend."
  type        = string
  default     = ""
}

variable "cognito_hosted_ui_prefix" {
  description = "Cognito Hosted-UI domain prefix (globally unique in-region). Required when enable_cognito."
  type        = string
  default     = ""
}

variable "cognito_extra_callback_urls" {
  description = "Extra OAuth callback/logout URLs beyond https://<frontend_domain_name>/ (e.g. http://localhost:5173/ for local dev)."
  type        = list(string)
  default     = []
}
