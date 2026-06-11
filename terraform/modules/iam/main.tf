data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id               = data.aws_caller_identity.current.account_id
  region                   = data.aws_region.current.name
  partition                = data.aws_partition.current.partition
  karpenter_node_role_name = "${var.name}-karpenter-node"
}

# ---------------------------------------------------------------------------
# Shared trust policy for EKS Pod Identity. Roles are assumed by the EKS Pod
# Identity service principal — no OIDC provider, no SA annotations needed.
# The (namespace, service-account) -> role mapping is an
# aws_eks_pod_identity_association (see the addons module).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# ===========================================================================
# HyperPod execution role (assumed by SageMaker, not a pod — keeps its own
# service trust).
# ===========================================================================
data "aws_iam_policy_document" "hyperpod_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "hyperpod_execution" {
  name               = "${var.name}-hyperpod-exec"
  assume_role_policy = data.aws_iam_policy_document.hyperpod_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "hyperpod_inline" {
  statement {
    sid    = "S3DataAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [
      var.data_bucket_arn,
      "${var.data_bucket_arn}/*",
      var.checkpoint_bucket_arn,
      "${var.checkpoint_bucket_arn}/*",
    ]
  }

  statement {
    sid    = "Logging"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "cloudwatch:PutMetricData",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "hyperpod_inline" {
  name   = "${var.name}-hyperpod-inline"
  role   = aws_iam_role.hyperpod_execution.id
  policy = data.aws_iam_policy_document.hyperpod_inline.json
}

resource "aws_iam_role_policy_attachment" "hyperpod_managed" {
  role       = aws_iam_role.hyperpod_execution.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSageMakerClusterInstanceRolePolicy"
}

# ===========================================================================
# HyperPod autoscaler (Karpenter) cluster role. Assumed by the HyperPod service
# (hyperpod.sagemaker.amazonaws.com), not a pod — it lets HyperPod's managed
# Karpenter add/remove cluster nodes on demand. Passed to the cluster as
# cluster_role when enable_gpu_autoscaling = true. No AWS managed policy covers
# these actions, so the permissions are inline (mirrors the AWS docs policy).
# ===========================================================================
data "aws_iam_policy_document" "hyperpod_autoscaler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["hyperpod.sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "hyperpod_autoscaler" {
  name               = "${var.name}-hyperpod-autoscaler"
  assume_role_policy = data.aws_iam_policy_document.hyperpod_autoscaler_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "hyperpod_autoscaler" {
  statement {
    sid       = "ManageClusterNodes"
    effect    = "Allow"
    actions   = ["sagemaker:BatchAddClusterNodes", "sagemaker:BatchDeleteClusterNodes"]
    resources = ["arn:${local.partition}:sagemaker:*:*:cluster/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      # Literal IAM policy variable — only acts on clusters in the caller account.
      values = ["$${aws:PrincipalAccount}"]
    }
  }

  statement {
    sid       = "KmsGrantsForClusterVolumes"
    effect    = "Allow"
    actions   = ["kms:CreateGrant", "kms:DescribeKey"]
    resources = ["arn:${local.partition}:kms:*:*:key/*"]
    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values   = ["sagemaker.*.amazonaws.com"]
    }
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "kms:GrantOperations"
      values = [
        "CreateGrant", "Decrypt", "DescribeKey",
        "GenerateDataKeyWithoutPlaintext", "ReEncryptTo",
        "ReEncryptFrom", "RetireGrant",
      ]
    }
  }
}

resource "aws_iam_role_policy" "hyperpod_autoscaler" {
  name   = "${var.name}-hyperpod-autoscaler"
  role   = aws_iam_role.hyperpod_autoscaler.id
  policy = data.aws_iam_policy_document.hyperpod_autoscaler.json
}

# ===========================================================================
# ACK SageMaker controller role (Pod Identity).
# ===========================================================================
resource "aws_iam_role" "ack_sagemaker" {
  name               = "${var.name}-ack-sagemaker"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ack_sagemaker" {
  role       = aws_iam_role.ack_sagemaker.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSageMakerFullAccess"
}

# ===========================================================================
# Karpenter: node role (EC2 trust) + controller role (Pod Identity).
# ===========================================================================
data "aws_iam_policy_document" "karpenter_node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_node" {
  name               = local.karpenter_node_role_name
  assume_role_policy = data.aws_iam_policy_document.karpenter_node_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "karpenter_node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryReadOnly",
    "AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.value}"
}

# Controller role assumed via Pod Identity.
resource "aws_iam_role" "karpenter_controller" {
  name               = "${var.name}-karpenter"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "karpenter_controller" {
  statement {
    sid     = "AllowScopedEC2InstanceAccessActions"
    effect  = "Allow"
    actions = ["ec2:RunInstances", "ec2:CreateFleet"]
    resources = [
      "arn:${local.partition}:ec2:${local.region}::image/*",
      "arn:${local.partition}:ec2:${local.region}::snapshot/*",
      "arn:${local.partition}:ec2:${local.region}:*:security-group/*",
      "arn:${local.partition}:ec2:${local.region}:*:subnet/*",
    ]
  }

  statement {
    sid       = "AllowScopedEC2LaunchTemplateAccessActions"
    effect    = "Allow"
    actions   = ["ec2:RunInstances", "ec2:CreateFleet"]
    resources = ["arn:${local.partition}:ec2:${local.region}:*:launch-template/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }
  }

  statement {
    sid     = "AllowScopedEC2InstanceActionsWithTags"
    effect  = "Allow"
    actions = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
    resources = [
      "arn:${local.partition}:ec2:${local.region}:*:fleet/*",
      "arn:${local.partition}:ec2:${local.region}:*:instance/*",
      "arn:${local.partition}:ec2:${local.region}:*:volume/*",
      "arn:${local.partition}:ec2:${local.region}:*:network-interface/*",
      "arn:${local.partition}:ec2:${local.region}:*:launch-template/*",
      "arn:${local.partition}:ec2:${local.region}:*:spot-instances-request/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }
  }

  statement {
    sid       = "AllowScopedResourceTagging"
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:${local.partition}:ec2:${local.region}:*:*/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }
  }

  statement {
    sid     = "AllowScopedDeletion"
    effect  = "Allow"
    actions = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
    resources = [
      "arn:${local.partition}:ec2:${local.region}:*:instance/*",
      "arn:${local.partition}:ec2:${local.region}:*:launch-template/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }
  }

  statement {
    sid    = "AllowRegionalReadActions"
    effect = "Allow"
    actions = [
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
      "ec2:DescribeAvailabilityZones",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowSSMReadActions"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:${local.partition}:ssm:${local.region}::parameter/aws/service/*"]
  }

  statement {
    sid       = "AllowPricingReadActions"
    effect    = "Allow"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  statement {
    sid       = "AllowPassingInstanceRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.karpenter_node.arn]
  }

  statement {
    sid    = "AllowInstanceProfileManagement"
    effect = "Allow"
    actions = [
      "iam:CreateInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:TagInstanceProfile",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowClusterEndpointDiscovery"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:${local.partition}:eks:${local.region}:${local.account_id}:cluster/${var.cluster_name}"]
  }

  statement {
    sid    = "AllowInterruptionQueueActions"
    effect = "Allow"
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
    resources = [var.karpenter_interruption_queue_arn]
  }
}

resource "aws_iam_role_policy" "karpenter_controller" {
  name   = "${var.name}-karpenter-controller"
  role   = aws_iam_role.karpenter_controller.id
  policy = data.aws_iam_policy_document.karpenter_controller.json
}
