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


resource "kubernetes_manifest" "app_of_apps" {
  count = var.enable_argocd && var.gitops_repo_url != "" ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "app-of-apps"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = var.gitops_repo_revision
        path           = "gitops/apps"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }

  depends_on = [
    helm_release.argocd,
    aws_eks_pod_identity_association.karpenter,
    aws_eks_pod_identity_association.ack_sagemaker,
  ]
}
