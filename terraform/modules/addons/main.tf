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


# Root app-of-apps Application, deployed declaratively via the argocd-apps Helm
# chart. This replaces the earlier `terraform_data` + `local-exec` that shelled
# out to `aws eks update-kubeconfig | kubectl apply`: the helm provider talks to
# the cluster API directly (same exec-auth as the kubernetes provider), so there
# is no dependency on the `aws`/`kubectl` CLIs on the apply host, the resource
# has a real create/update/delete lifecycle (drift detection + clean destroy),
# and the manifest is rendered/owned by Terraform instead of a fire-and-forget
# shell command.
resource "helm_release" "argocd_apps" {
  count = var.enable_argocd && var.gitops_repo_url != "" ? 1 : 0

  name       = "argocd-apps"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_version

  values = [yamlencode({
    applications = {
      "app-of-apps" = {
        namespace  = "argocd"
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        project    = "default"
        source = {
          repoURL        = var.gitops_repo_url
          targetRevision = var.gitops_repo_revision
          path           = "gitops/bootstrap"
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated   = { prune = true, selfHeal = true }
          syncOptions = ["CreateNamespace=true", "SkipDryRunOnMissingResource=true"]
          retry = {
            limit   = 10
            backoff = { duration = "15s", maxDuration = "5m", factor = 2 }
          }
        }
      }
    }
  })]

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
