terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}


locals {
  documents = [for d in split("\n---", file(var.manifest_path)) : d if trimspace(d) != ""]

  namespace_docs = { for d in local.documents :
    "${yamldecode(d).kind}/${yamldecode(d).metadata.name}" => d
    if yamldecode(d).kind == "Namespace"
  }
  rbac_docs = { for d in local.documents :
    "${yamldecode(d).kind}/${try(yamldecode(d).metadata.namespace, "cluster")}/${yamldecode(d).metadata.name}" => d
    if yamldecode(d).kind != "Namespace"
  }
}

resource "kubectl_manifest" "namespace" {
  for_each          = local.namespace_docs
  yaml_body         = each.value
  server_side_apply = true
}

resource "kubectl_manifest" "rbac" {
  for_each          = local.rbac_docs
  yaml_body         = each.value
  server_side_apply = true

  depends_on = [kubectl_manifest.namespace]
}
