terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.26.0"
    }
    flux = {
      source  = "fluxcd/flux"
      version = "1.2.3"
    }
  }
}

resource "kubernetes_namespace_v1" "flux_system" {
  metadata {
    name = "flux-system"
  }

  lifecycle {
    ignore_changes = [
      metadata[0].labels
    ]
  }
}

resource "kubernetes_secret_v1" "sops_age" {
  metadata {
    name      = "sops-age"
    namespace = kubernetes_namespace_v1.flux_system.metadata[0].name
  }

  data = {
    "keys.agekey" = file(pathexpand(var.sops_key_path))
  }
}

resource "flux_bootstrap_git" "this" {
  depends_on = [kubernetes_secret_v1.sops_age]

  path = var.fluxcd_path
}
