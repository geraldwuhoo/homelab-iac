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
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.7.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 3.1.0"
    }
  }
}
provider "proxmox" {
  pm_api_url          = var.proxmox.api_url
  pm_api_token_id     = var.proxmox.api_token_id
  pm_api_token_secret = var.proxmox.api_token_secret
}
provider "kubernetes" {
  config_path = var.kubernetes.config_path
}
provider "helm" {
  kubernetes {
    config_path = var.kubernetes.config_path
  }
}
EOF
}

generate "vars" {
  path = "vars.tf"
  if_exists = "overwrite_terragrunt"
  contents = <<EOF
variable "proxmox" {
  type = object({
    api_url          = string
    api_token_id     = string
    api_token_secret = string
  })
}

variable "cluster" {
  type = list(object({
    type = string
    specs = object({
      cores   = number
      memory  = number
      balloon = number
      storage = string
    })
    nodes = list(object({
      vmid          = number
      name          = string
      node          = string
      hastate       = string
      macaddr       = string
      template_name = string
    }))
  }))
}

variable "kubernetes" {
  type = object({
    config_path = string
  })
}
EOF
}

inputs = {
  proxmox = local.proxmox
  cluster = local.cluster
}
