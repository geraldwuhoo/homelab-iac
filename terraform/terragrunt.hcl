locals {
  config  = yamldecode(sops_decrypt_file(("${path_relative_from_include()}/config.sops.yaml")))
  cluster = yamldecode(file("${path_relative_to_include()}/config.yaml"))
  proxmox = local.config.proxmox
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 2.9.0"
    }
  }
}
provider "proxmox" {
  pm_api_url          = var.proxmox.api_url
  pm_api_token_id     = var.proxmox.api_token_id
  pm_api_token_secret = var.proxmox.api_token_secret
}
EOF
}

inputs = {
  proxmox = local.proxmox
  cluster = local.cluster
}
