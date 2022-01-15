terraform {
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "~> 0.6"
    }
    proxmox = {
      source  = "telmate/proxmox"
      version = ">= 2.9.0"
    }
  }
  backend "pg" {
    schema_name = "production"
  }
}

data "sops_file" "config" {
  source_file = "config.sops.yaml"
}

locals {
  config_file = yamldecode(data.sops_file.config.raw)
  proxmox     = local.config_file.proxmox
  cluster     = local.config_file.production
}

provider "proxmox" {
  pm_api_url          = local.proxmox.api_url
  pm_api_token_id     = local.proxmox.api_token_id
  pm_api_token_secret = local.proxmox.api_token_secret
}

module "kube_proxmox_production" {
  source = "../modules/kube-proxmox"

  proxmox      = local.proxmox
  scsi_storage = "rbd"
  cluster      = local.cluster

  cluster_name = "prod"
}
