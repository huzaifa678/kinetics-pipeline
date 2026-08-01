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
