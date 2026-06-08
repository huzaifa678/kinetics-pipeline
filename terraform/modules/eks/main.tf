data "aws_partition" "current" {}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = var.name
  cluster_version = var.kubernetes_version

  # Public endpoint stays on so Terraform's helm/kubernetes providers can reach
  # the API from wherever apply runs, but access is restricted to an allowlist
  # (e.g. your VPN/proxy static egress IP). Private access is on by default, so
  # nodes always talk to the control plane over the private endpoint.
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false

  access_entries = {
    for idx, arn in var.cluster_admin_principal_arns : "cluster-admin-${idx}" => {
      principal_arn = arn
      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # Let on-VPN clients reach the cluster API SG (private endpoint) on 443.
  cluster_security_group_additional_rules = var.vpn_client_cidr_block == "" ? {} : {
    vpn_https = {
      description = "Client VPN users to API server on 443"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = [var.vpn_client_cidr_block]
    }
  }

  enable_irsa = true

  cluster_addons = merge(
    {
      coredns                = {}
      kube-proxy             = {}
      vpc-cni                = {}
      eks-pod-identity-agent = {}
      aws-ebs-csi-driver     = {}
    },
    var.enable_hyperpod_operator ? {
      amazon-sagemaker-hyperpod-training-operator = {
        most_recent = true
      }
    } : {},
  )

  # Small, always-on CPU node group for controllers (ACK, Karpenter,
  # ArgoCD, Prometheus). GPUs are NOT here — they're in HyperPod.
  eks_managed_node_groups = {
    system = {
      instance_types = [var.system_node_instance_type]
      capacity_type  = "ON_DEMAND"

      min_size     = 1
      max_size     = max(var.system_node_desired_size + 1, 3)
      desired_size = var.system_node_desired_size

      use_custom_launch_template = true

      launch_template_id      = aws_launch_template.system.id
      launch_template_version = aws_launch_template.system.latest_version

      labels = {
        role = "system"
      }
    }
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = var.name
  }

  tags = var.tags
}
