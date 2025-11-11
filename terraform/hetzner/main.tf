terraform {
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "1.3.0"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.56.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.52.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.1.0"
    }
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = "18.5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
    flux = {
      source  = "fluxcd/flux"
      version = "1.7.4"
    }
  }

  backend "s3" {
    bucket = "terraform"
    key    = "tfstate/hetzner"
    region = "us-east-1"
    endpoints = {
      s3 = "s3.wuhoo.xyz"
    }

    skip_credentials_validation = true
  }
}

# Decrypt sops encrypted vars
provider "sops" {}

data "sops_file" "secret" {
  source_file = "${path.module}/config.sops.yaml"
}

provider "hcloud" {
  token = data.sops_file.secret.data["hcloud_token"]
}

provider "cloudflare" {
  api_token = data.sops_file.secret.data["cloudflare_api_token"]
}

locals {
  hetzner_hosts = [
    {
      hostname = "hetzner"
    },
  ]
}

module "k3s-hetzner" {
  for_each = { for index, host in local.hetzner_hosts : host.hostname => host }

  source               = "../modules/k3s-hcloud"
  ssh_key_path         = "~/.ssh/id_rsa.pub"
  name                 = each.value.hostname
  datacenter           = "nbg1-dc3"
  zone_id              = data.sops_file.secret.data["cloudflare_zone_id"]
  domain               = "wuhoo.xyz"
  sops-server-key-path = "~/.config/sops/age/server-side-key.txt"
}

resource "local_sensitive_file" "kubeconfig" {
  for_each = { for index, host in local.hetzner_hosts : host.hostname => host }

  content         = module.k3s-hetzner[each.value.hostname].k3s_kubeconfig
  filename        = pathexpand("~/.kube/${each.value.hostname}-hetzner.config")
  file_permission = "0600"
}

module "nixos" {
  for_each = { for index, host in local.hetzner_hosts : host.hostname => host }

  depends_on = [module.k3s-hetzner]
  source     = "github.com/Gabriella439/terraform-nixos-ng//nixos"

  host      = "nixos@${each.value.hostname}"
  flake     = "../../nix#${each.value.hostname}"
  arguments = ["--use-remote-sudo"]
}

# Configure the GitLab repository for Flux
resource "tls_private_key" "flux" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

provider "gitlab" {
  token = data.sops_file.secret.data["gitlab_token"]
}

module "gitlab" {
  depends_on = [module.k3s-hetzner]
  source     = "../modules/gitlab"

  public_key_openssh = resource.tls_private_key.flux.public_key_openssh

  gitlab = var.gitlab
}

# Bootstrap Flux
provider "kubernetes" {
  config_path = resource.local_sensitive_file.kubeconfig["hetzner"].filename
}

provider "flux" {
  kubernetes = {
    config_path = resource.local_sensitive_file.kubeconfig["hetzner"].filename
  }
  git = {
    url = "ssh://git@gitlab.com/${module.gitlab.gitlab_project.path_with_namespace}.git"
    ssh = {
      username    = "git"
      private_key = resource.tls_private_key.flux.private_key_pem
    }
    branch = var.gitlab.branch
  }
}

module "fluxcd" {
  depends_on = [
    module.k3s-hetzner,
    resource.local_sensitive_file.kubeconfig["hetzner"],
    module.gitlab,
  ]
  source = "../modules/fluxcd"

  sops_key_path = var.sops_key_path
  fluxcd_path   = var.fluxcd_path
}
