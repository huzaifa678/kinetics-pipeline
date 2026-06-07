module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = var.name
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access = false

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  enable_cluster_creator_admin_permissions = true

  enable_irsa = true

  cluster_addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = {}
    eks-pod-identity-agent = {}
    aws-ebs-csi-driver     = {}

    amazon-sagemaker-hyperpod-training-operator = {
      most_recent = true
    }
  }

  # Small, always-on CPU node group for controllers (ACK, Karpenter,
  # ArgoCD, Prometheus). GPUs are NOT here — they're in HyperPod.
  eks_managed_node_groups = {
    system = {
      instance_types = [var.system_node_instance_type]
      capacity_type  = "ON_DEMAND"

      min_size     = 1
      max_size     = max(var.system_node_desired_size + 1, 3)
      desired_size = var.system_node_desired_size

       launch_template = {
        id      = aws_launch_template.system.id
        version = aws_launch_template.system.latest_version
      }

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
