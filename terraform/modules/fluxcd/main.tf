terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.35.1"
    }
    flux = {
      source  = "fluxcd/flux"
      version = "1.5.1"
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

locals {
  kustomization_override = <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- gotk-components.yaml
- gotk-sync.yaml
patches:
- path: gotk-patches.yaml
  EOF
}

resource "flux_bootstrap_git" "this" {
  depends_on = [kubernetes_secret_v1.sops_age]

  path                   = var.fluxcd_path
  kustomization_override = var.patch ? local.kustomization_override : null
}
