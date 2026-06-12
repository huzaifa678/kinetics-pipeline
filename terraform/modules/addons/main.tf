resource "aws_eks_pod_identity_association" "karpenter" {
  cluster_name    = var.cluster_name
  namespace       = "karpenter"
  service_account = "karpenter"
  role_arn        = var.karpenter_role_arn
  tags            = var.tags
}

resource "aws_eks_pod_identity_association" "ack_sagemaker" {
  cluster_name    = var.cluster_name
  namespace       = "ack-system"
  service_account = "ack-sagemaker-controller"
  role_arn        = var.ack_sagemaker_role_arn
  tags            = var.tags
}


resource "helm_release" "argocd" {
  count            = var.enable_argocd ? 1 : 0
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_version
}


locals {
  app_of_apps_manifest = templatefile("${path.module}/app-of-apps.yaml.tpl", {
    app_name         = "app-of-apps"
    argocd_namespace = "argocd"
    repo_url         = var.gitops_repo_url
    repo_revision    = var.gitops_repo_revision
    repo_path        = "gitops/bootstrap"
  })
}


resource "terraform_data" "app_of_apps" {
  count = var.enable_argocd && var.gitops_repo_url != "" ? 1 : 0

  triggers_replace = [local.app_of_apps_manifest, var.cluster_name]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      MANIFEST = local.app_of_apps_manifest
    }
    command = <<-EOT
      set -euo pipefail
      KCFG="$(mktemp)"
      trap 'rm -f "$KCFG"' EXIT
      aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.region} --kubeconfig "$KCFG" >/dev/null
      printf '%s' "$MANIFEST" | kubectl --kubeconfig "$KCFG" apply -f -
    EOT
  }

  depends_on = [
    helm_release.argocd,
    aws_eks_pod_identity_association.karpenter,
    aws_eks_pod_identity_association.ack_sagemaker,
  ]
}


resource "helm_release" "cert_manager" {
  count = var.enable_hyperpod_operator ? 1 : 0

  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_version

  set = [{
    name  = "crds.enabled"
    value = "true"
  }]

  
  wait    = true
  timeout = 600
}

#
resource "terraform_data" "hyperpod_ready" {
  count = var.enable_hyperpod_operator ? 1 : 0
  input = var.hyperpod_cluster_arn
}


resource "aws_eks_addon" "hyperpod_taskgovernance" {
  count = var.enable_hyperpod_operator ? 1 : 0

  cluster_name                = var.cluster_name
  addon_name                  = "amazon-sagemaker-hyperpod-taskgovernance"
  resolve_conflicts_on_create = "OVERWRITE"
  tags                        = var.tags

  depends_on = [helm_release.cert_manager]
}

resource "aws_eks_addon" "hyperpod_operator" {
  count = var.enable_hyperpod_operator ? 1 : 0

  cluster_name                = var.cluster_name
  addon_name                  = "amazon-sagemaker-hyperpod-training-operator"
  resolve_conflicts_on_create = "OVERWRITE"
  tags                        = var.tags

  depends_on = [
    helm_release.cert_manager,
    aws_eks_addon.hyperpod_taskgovernance,
    terraform_data.hyperpod_ready,
  ]
}
