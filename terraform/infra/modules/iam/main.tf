resource "aws_iam_role" "hyperpod_execution" {
  name               = "${var.name}-hyperpod-exec"
  assume_role_policy = data.aws_iam_policy_document.hyperpod_assume.json
  tags               = var.tags
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

resource "aws_iam_role" "hyperpod_autoscaler" {
  name               = "${var.name}-hyperpod-autoscaler"
  assume_role_policy = data.aws_iam_policy_document.hyperpod_autoscaler_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "hyperpod_autoscaler" {
  name   = "${var.name}-hyperpod-autoscaler"
  role   = aws_iam_role.hyperpod_autoscaler.id
  policy = data.aws_iam_policy_document.hyperpod_autoscaler.json
}

resource "aws_iam_role" "keda_amp" {
  count = var.enable_managed_prometheus ? 1 : 0

  name               = "${var.name}-keda-amp"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "keda_amp" {
  count = var.enable_managed_prometheus ? 1 : 0

  name   = "${var.name}-keda-amp"
  role   = aws_iam_role.keda_amp[0].id
  policy = data.aws_iam_policy_document.keda_amp[0].json
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

resource "aws_iam_role_policy" "karpenter_controller" {
  name   = "${var.name}-karpenter-controller"
  role   = aws_iam_role.karpenter_controller.id
  policy = data.aws_iam_policy_document.karpenter_controller.json
}

resource "aws_iam_role" "amp_remote_write" {
  count = var.enable_managed_prometheus ? 1 : 0

  name               = "${var.name}-amp-remote-write"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "amp_remote_write" {
  count = var.enable_managed_prometheus ? 1 : 0

  name   = "${var.name}-amp-remote-write"
  role   = aws_iam_role.amp_remote_write[0].id
  policy = data.aws_iam_policy_document.amp_remote_write[0].json
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

resource "aws_iam_role" "cert_manager" {
  count = var.enable_cert_manager_dns01 ? 1 : 0

  name               = "${var.name}-cert-manager"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "cert_manager" {
  count = var.enable_cert_manager_dns01 ? 1 : 0

  name   = "${var.name}-cert-manager"
  role   = aws_iam_role.cert_manager[0].id
  policy = data.aws_iam_policy_document.cert_manager[0].json
}

resource "aws_iam_role" "external_secrets" {
  name               = "${var.name}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = var.tags
}

resource "aws_iam_policy" "external_secrets" {
  name   = "${var.name}-external-secrets"
  policy = data.aws_iam_policy_document.external_secrets.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  role       = aws_iam_role.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets.arn
}

resource "aws_iam_role" "thanos" {
  name               = "${var.name}-thanos"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "thanos" {
  name   = "${var.name}-thanos"
  role   = aws_iam_role.thanos.id
  policy = data.aws_iam_policy_document.thanos.json
}