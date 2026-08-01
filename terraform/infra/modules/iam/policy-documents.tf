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

data "aws_iam_policy_document" "hyperpod_inline" {
  # checkov:skip=CKV_AWS_356:EC2 describe/ENI + CloudWatch Logs don't support resource-level scoping; ENIs are created dynamically at node provision time.
  # checkov:skip=CKV_AWS_111:The unconstrained actions are ops-plane (Logs/metrics/ENI lifecycle), not data writes; S3 data access is bucket-scoped above.
  # checkov:skip=CKV_AWS_109:Same ops-plane actions (Logs/EC2 describe/ENI lifecycle) — no permissions-management or resource-exposure actions are granted.
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

  # HyperPod attaches nodes to the VPC via ENIs and tears them down on
  # scale-in/delete. CreateCluster validates these up front — without
  # DeleteNetworkInterface it fails at CREATE with an execution-role error.
  statement {
    sid    = "VpcEniForClusterNodes"
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:CreateNetworkInterfacePermission",
      "ec2:DeleteNetworkInterfacePermission",
    ]
    resources = ["*"]
  }
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

# ===========================================================================
# KEDA -> AMP (Pod Identity): lets the KEDA operator query the AMP workspace for
# the Prometheus scaler's AMP-trigger fallback. Gated on enable_managed_prometheus
# (mirrors amp_remote_write) — the default in-cluster-Prometheus trigger needs no
# AWS creds, so this role/association only exist when AMP is on. Gating on the flag
# (not the ARN, which may be unknown at plan) keeps the empty ARN out of the policy.
# ===========================================================================
data "aws_iam_policy_document" "keda_amp" {
  count = var.enable_managed_prometheus ? 1 : 0

  statement {
    sid    = "AmpQueryMetrics"
    effect = "Allow"
    actions = [
      "aps:QueryMetrics"
    ]
    resources = [var.amp_workspace_arn]
  }
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

data "aws_iam_policy_document" "karpenter_controller" {
  # This is the upstream Karpenter controller policy: EC2 fleet/describe/pricing
  # actions that don't support resource-level ARNs (describes) or are gated by
  # `aws:RequestTag`/`ec2:ResourceTag` conditions instead of resource scoping.
  # checkov:skip=CKV_AWS_356:Karpenter's EC2 describe/pricing/fleet actions can't be resource-scoped; scoping is enforced via tag conditions, not resource ARNs.
  # checkov:skip=CKV_AWS_109:No IAM permissions-management actions here; the wildcard statements are read/describe + tag-conditioned instance lifecycle.
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

# ===========================================================================
# AMP remote_write (Pod Identity): lets the in-cluster Prometheus
# (kube-prometheus-stack-prometheus / monitoring) ship metrics to the AMP
# workspace. Gated by the workspace ARN — created only when AMP is enabled.
# ===========================================================================
data "aws_iam_policy_document" "amp_remote_write" {
  count = var.enable_managed_prometheus ? 1 : 0

  statement {
    sid       = "AmpRemoteWrite"
    actions   = ["aps:RemoteWrite", "aps:GetSeries", "aps:GetLabels", "aps:GetMetricMetadata"]
    resources = [var.amp_workspace_arn]
  }
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

# ===========================================================================
# cert-manager (Pod Identity): ACME DNS-01 solver — creates/removes the
# _acme-challenge TXT records Let's Encrypt checks. Scoped to the configured
# hosted zone (same zone external-dns uses). GetChange must be account-wide
# (change IDs aren't zone-scoped); ListHostedZonesByName has no resource ARN.
# ===========================================================================
data "aws_iam_policy_document" "cert_manager" {
  count = var.enable_cert_manager_dns01 ? 1 : 0

  statement {
    sid       = "GetChange"
    actions   = ["route53:GetChange"]
    resources = ["arn:${local.partition}:route53:::change/*"]
  }

  statement {
    sid       = "ChangeRecords"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = var.route53_zone_id != "" ? ["arn:${local.partition}:route53:::hostedzone/${var.route53_zone_id}"] : ["arn:${local.partition}:route53:::hostedzone/*"]
  }

  statement {
    sid       = "ListZones"
    actions   = ["route53:ListHostedZonesByName", "route53:ListResourceRecordSets"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "external_secrets" {
  statement {
    sid    = "ReadPlatformSecrets"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]

    resources = [
      "arn:${local.partition}:secretsmanager:${local.region}:${local.account_id}:secret:kinetics-*",
      "arn:${local.partition}:secretsmanager:${local.region}:${local.account_id}:secret:AmazonMSK_*",
    ]
  }

  # The MSK SCRAM secret (AmazonMSK_*) is encrypted with a customer-managed CMK
  # (MSK requires a CMK for SCRAM secrets, not the default aws/secretsmanager key).
  # Without kms:Decrypt, GetSecretValue fails with "Access to KMS is not allowed",
  # so ESO can never sync seldon-kafka-sasl. Scope the grant to decrypts performed
  # *on behalf of* Secrets Manager (ViaService) rather than a raw key wildcard.
  statement {
    sid       = "DecryptSecretsViaSecretsManager"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["arn:${local.partition}:kms:${local.region}:${local.account_id}:key/*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${local.region}.amazonaws.com"]
    }
  }
}

# ===========================================================================
# Thanos (Pod Identity): allows Thanos components (Store Gateway, Compactor,
# Sidecar, Receive, Ruler) to read and write TSDB blocks stored in S3.
# ===========================================================================
data "aws_iam_policy_document" "thanos" {
  statement {
    sid    = "ThanosObjectAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]

    resources = [
      "${var.thanos_blocks_bucket_arn}/*",
    ]
  }

  statement {
    sid    = "ThanosBucketAccess"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
    ]

    resources = [
      var.thanos_blocks_bucket_arn,
    ]
  }
}
