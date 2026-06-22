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

  # SageMaker assumes this role to validate the cluster's VPC config at create
  # time (esp. with override_vpc_config / per-AZ subnet pinning). Without these
  # describes, CreateCluster fails with "Unable to retrieve subnets".
  statement {
    sid    = "VpcDescribeForClusterCreate"
    effect = "Allow"
    actions = [
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeAvailabilityZones",
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
# ETL shard-build Job (Pod Identity): writes WebDataset shards to the data
# bucket. Input mp4s are read from the FSx /data mount (POSIX), so it only needs
# S3 *write* to the output prefix — least privilege.
# ===========================================================================
data "aws_iam_policy_document" "etl_shards" {
  statement {
    sid       = "ShardsS3Write"
    actions   = ["s3:PutObject", "s3:AbortMultipartUpload"]
    resources = ["${var.data_bucket_arn}/*"]
  }
  statement {
    sid       = "ShardsS3List"
    actions   = ["s3:ListBucket"]
    resources = [var.data_bucket_arn]
  }
}

resource "aws_iam_role" "etl_shards" {
  name               = "${var.name}-etl-shards"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "etl_shards" {
  name   = "${var.name}-etl-shards-s3"
  role   = aws_iam_role.etl_shards.id
  policy = data.aws_iam_policy_document.etl_shards.json
}

# ===========================================================================
# ArgoCD Image Updater: Pod Identity role with read-only ECR access (poll tags
# + mint a short-lived registry token). Optional/capability — harmless if the
# Image Updater isn't installed.
# ===========================================================================
data "aws_iam_policy_document" "image_updater" {
  statement {
    sid       = "EcrAuthToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrReadRepo"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
      "ecr:DescribeImages",
      "ecr:ListImages",
    ]
    resources = [var.ecr_repository_arn != "" ? var.ecr_repository_arn : "*"]
  }
}

resource "aws_iam_role" "image_updater" {
  name               = "${var.name}-image-updater"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "image_updater" {
  name   = "${var.name}-image-updater-ecr"
  role   = aws_iam_role.image_updater.id
  policy = data.aws_iam_policy_document.image_updater.json
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

# ===========================================================================
# AMP remote_write (Pod Identity): lets the in-cluster Prometheus
# (kube-prometheus-stack-prometheus / monitoring) ship metrics to the AMP
# workspace. Gated by the workspace ARN — created only when AMP is enabled.
# ===========================================================================
data "aws_iam_policy_document" "amp_remote_write" {
  count = var.amp_workspace_arn != "" ? 1 : 0

  statement {
    sid       = "AmpRemoteWrite"
    actions   = ["aps:RemoteWrite", "aps:GetSeries", "aps:GetLabels", "aps:GetMetricMetadata"]
    resources = [var.amp_workspace_arn]
  }
}

resource "aws_iam_role" "amp_remote_write" {
  count = var.amp_workspace_arn != "" ? 1 : 0

  name               = "${var.name}-amp-remote-write"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "amp_remote_write" {
  count = var.amp_workspace_arn != "" ? 1 : 0

  name   = "${var.name}-amp-remote-write"
  role   = aws_iam_role.amp_remote_write[0].id
  policy = data.aws_iam_policy_document.amp_remote_write[0].json
}

# ===========================================================================
# OTel collector -> X-Ray (Pod Identity): lets the in-cluster otel-collector
# (otel-collector / observability) push trace segments to AWS X-Ray, and
# (if AMP is on) remote_write metrics too.
# ===========================================================================
data "aws_iam_policy_document" "otel_xray" {
  count = var.enable_xray_tracing ? 1 : 0

  statement {
    sid = "XRayWrite"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets",
      "xray:GetSamplingStatisticSummaries",
    ]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = var.amp_workspace_arn != "" ? [1] : []
    content {
      sid       = "AmpRemoteWrite"
      actions   = ["aps:RemoteWrite", "aps:GetSeries", "aps:GetLabels", "aps:GetMetricMetadata"]
      resources = [var.amp_workspace_arn]
    }
  }
}

resource "aws_iam_role" "otel_xray" {
  count = var.enable_xray_tracing ? 1 : 0

  name               = "${var.name}-otel-xray"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "otel_xray" {
  count = var.enable_xray_tracing ? 1 : 0

  name   = "${var.name}-otel-xray"
  role   = aws_iam_role.otel_xray[0].id
  policy = data.aws_iam_policy_document.otel_xray[0].json
}

# ===========================================================================
# AWS Load Balancer Controller (Pod Identity): provisions ALBs for the
# inference Ingress. Uses the upstream policy doc vendored under policies/.
# ===========================================================================
resource "aws_iam_policy" "aws_lbc" {
  count = var.enable_aws_lb_controller ? 1 : 0

  name   = "${var.name}-aws-lbc"
  policy = file("${path.module}/policies/aws-lb-controller.json")
  tags   = var.tags
}

resource "aws_iam_role" "aws_lbc" {
  count = var.enable_aws_lb_controller ? 1 : 0

  name               = "${var.name}-aws-lbc"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "aws_lbc" {
  count = var.enable_aws_lb_controller ? 1 : 0

  role       = aws_iam_role.aws_lbc[0].name
  policy_arn = aws_iam_policy.aws_lbc[0].arn
}

# ===========================================================================
# external-dns (Pod Identity): manages the inference A-record in Route53.
# Scoped to the configured hosted zone when provided.
# ===========================================================================
data "aws_iam_policy_document" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  statement {
    sid       = "ChangeRecords"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = var.route53_zone_id != "" ? ["arn:${local.partition}:route53:::hostedzone/${var.route53_zone_id}"] : ["arn:${local.partition}:route53:::hostedzone/*"]
  }

  statement {
    sid       = "ListZones"
    actions   = ["route53:ListHostedZones", "route53:ListResourceRecordSets", "route53:ListTagsForResource"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  name               = "${var.name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  name   = "${var.name}-external-dns"
  role   = aws_iam_role.external_dns[0].id
  policy = data.aws_iam_policy_document.external_dns[0].json
}
