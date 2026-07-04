terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}


# proper advisory checks-on to prevent/catch deadlocks in the HyperPod dependency chart (training operators + health-monitoring-agent) before the HyperPod cluster is created.
check "hyperpod_dependencies_healthy" {
  data "kubernetes_resource" "hyperpod_deps" {
    api_version = "argoproj.io/v1alpha1"
    kind        = "Application"

    metadata {
      name      = var.app_name
      namespace = var.app_namespace
    }
  }

  assert {
    condition = try(
      data.kubernetes_resource.hyperpod_deps.object.status.sync.status == "Synced" &&
      data.kubernetes_resource.hyperpod_deps.object.status.health.status == "Healthy",
      false
    )
    error_message = format(
      "HyperPod dependency chart not ready: ArgoCD Application '%s' is sync=%s health=%s (want Synced/Healthy). The SageMaker HyperPod cluster needs this umbrella chart (training operators + health-monitoring-agent) installed before it will create — see CLAUDE.md HyperPod gotcha #1.",
      var.app_name,
      try(data.kubernetes_resource.hyperpod_deps.object.status.sync.status, "<absent>"),
      try(data.kubernetes_resource.hyperpod_deps.object.status.health.status, "<absent>"),
    )
  }
}
