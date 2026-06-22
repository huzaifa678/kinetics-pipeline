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

# ETL shard-build Job SA -> S3 write role (Pod Identity). Namespace must match
# where the etl-shards Job is applied (default "default").
resource "aws_eks_pod_identity_association" "etl_shards" {
  cluster_name    = var.cluster_name
  namespace       = var.etl_shards_namespace
  service_account = "etl-shards"
  role_arn        = var.etl_shards_role_arn
  tags            = var.tags
}

# The ArgoCD image update needs permission to read the ECR repos and pull the images
# Pod identity instead of IRSA, best because minimal permissions and only needed for a single service account in the argocd namespace,
# so no need to create a separate OIDC provider or IRSA role for it.
resource "aws_eks_pod_identity_association" "image_updater" {
  cluster_name    = var.cluster_name
  namespace       = "argocd"
  service_account = "argocd-image-updater"
  role_arn        = var.image_updater_role_arn
  tags            = var.tags
}

# AWS Load Balancer Controller SA -> ALB-provisioning role (Pod Identity).
resource "aws_eks_pod_identity_association" "aws_lbc" {
  count = var.enable_aws_lb_controller ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = var.aws_lbc_role_arn
  tags            = var.tags
}

# external-dns SA -> Route53 role (Pod Identity).
resource "aws_eks_pod_identity_association" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "external-dns"
  role_arn        = var.external_dns_role_arn
  tags            = var.tags
}

# In-cluster Prometheus SA -> AMP remote_write role (Pod Identity). The SA name
# is the kube-prometheus-stack default (release "kube-prometheus-stack").
resource "aws_eks_pod_identity_association" "amp_remote_write" {
  count = var.amp_remote_write_role_arn != "" ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = "monitoring"
  service_account = "kube-prometheus-stack-prometheus"
  role_arn        = var.amp_remote_write_role_arn
  tags            = var.tags
}

# In-cluster OTel collector SA -> X-Ray write role (Pod Identity). SA name is
# pinned by fullnameOverride: otel-collector in the GitOps values.
resource "aws_eks_pod_identity_association" "otel_xray" {
  count = var.otel_xray_role_arn != "" ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = "observability"
  service_account = "otel-collector"
  role_arn        = var.otel_xray_role_arn
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

  # Custom health assessment for the HyperPodPyTorchJob CRD. ArgoCD ships no
  # built-in health check for it, so without this the manual-sync training app
  # sits "Progressing/Unknown" forever and never surfaces Succeeded/Failed. This
  # maps the operator's Kubeflow-style status.conditions to ArgoCD health, via
  # the chart's configs.cm (merged into the argocd-cm ConfigMap).
  values = [yamlencode({
    configs = {
      cm = {
        "resource.customizations.health.sagemaker.amazonaws.com_HyperPodPyTorchJob" = <<-EOT
          hs = {}
          if obj.status ~= nil and obj.status.conditions ~= nil then
            for i, c in ipairs(obj.status.conditions) do
              if c.type == "Failed" and c.status == "True" then
                hs.status = "Degraded"
                hs.message = c.message
                return hs
              end
              if c.type == "Succeeded" and c.status == "True" then
                hs.status = "Healthy"
                hs.message = c.message
                return hs
              end
              if c.type == "Running" and c.status == "True" then
                hs.status = "Progressing"
                hs.message = c.message
                return hs
              end
            end
          end
          hs.status = "Progressing"
          hs.message = "Waiting for HyperPodPyTorchJob status"
          return hs
        EOT
      }
    }
  })]
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

# ---------------------------------------------------------------------------
# AWS Load Balancer Controller — backs the inference Ingress with an internal
# ALB. Auth via Pod Identity (no IRSA/SA annotation needed).
# ---------------------------------------------------------------------------
resource "helm_release" "aws_load_balancer_controller" {
  count = var.enable_aws_lb_controller ? 1 : 0

  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.aws_lb_controller_chart_version

  set = [
    { name = "clusterName", value = var.cluster_name },
    { name = "region", value = var.region },
    { name = "vpcId", value = var.vpc_id },
    { name = "serviceAccount.create", value = "true" },
    { name = "serviceAccount.name", value = "aws-load-balancer-controller" },
  ]

  depends_on = [aws_eks_pod_identity_association.aws_lbc]
}

# ---------------------------------------------------------------------------
# external-dns — registers the inference ALB's Route53 A-record (the ALB DNS
# name isn't known at apply time). upsert-only + a TXT owner record so it never
# deletes pre-existing records it doesn't own.
# ---------------------------------------------------------------------------
resource "helm_release" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  name       = "external-dns"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = var.external_dns_chart_version

  set = concat([
    { name = "provider.name", value = "aws" },
    { name = "policy", value = "upsert-only" },
    { name = "registry", value = "txt" },
    { name = "txtOwnerId", value = var.cluster_name },
    { name = "serviceAccount.create", value = "true" },
    { name = "serviceAccount.name", value = "external-dns" },
    { name = "env[0].name", value = "AWS_REGION" },
    { name = "env[0].value", value = var.region },
    ], var.external_dns_domain_filter != "" ? [
    { name = "domainFilters[0]", value = var.external_dns_domain_filter },
  ] : [])

  depends_on = [aws_eks_pod_identity_association.external_dns]
}
