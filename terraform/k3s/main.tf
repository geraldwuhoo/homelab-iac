terraform {
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "1.1.1"
    }
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.1-rc4"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.0.6"
    }
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = "17.5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.33.0"
    }
    flux = {
      source  = "fluxcd/flux"
      version = "1.4.0"
    }
  }

  backend "s3" {
    bucket = "terraform"
    key = "tfstate/k3s"
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

# Provision the k3s cluster
provider "proxmox" {
  pm_api_url          = data.sops_file.secret.data["proxmox.api_url"]
  pm_api_token_id     = data.sops_file.secret.data["proxmox.api_token_id"]
  pm_api_token_secret = data.sops_file.secret.data["proxmox.api_token_secret"]
}

locals {
  # MAC addresses are stably generated via
  # echo "$FQDN" | md5sum | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/02:\1:\2:\3:\4:\5/'
  hosts = [
    {
      hostname    = "k3s-master-0"
      mac_address = "02:26:d4:2a:16:48"
      hastate     = "started"
      server      = true
      node        = "bake"
    },
    {
      hostname    = "k3s-master-1"
      mac_address = "02:1c:d6:7f:47:04"
      hastate     = "started"
      server      = true
      node        = "nise"
    },
    {
      hostname    = "k3s-master-2"
      mac_address = "02:42:36:8e:95:13"
      hastate     = "started"
      server      = true
      node        = "neko"
    },
    {
      hostname    = "k3s-worker-0"
      mac_address = "02:1a:f5:3c:85:0b"
      hastate     = "started"
      server      = false
      node        = "bake"
    },
    {
      hostname    = "k3s-worker-1"
      mac_address = "02:b7:6e:fa:43:e2"
      hastate     = "started"
      server      = false
      node        = "nise"
    },
    {
      hostname    = "k3s-worker-2"
      mac_address = "02:b1:a9:5e:03:10"
      hastate     = "started"
      server      = false
      node        = "neko"
    },
    {
      hostname    = "k3s-worker-3"
      mac_address = "02:91:3f:f7:28:e5"
      hastate     = "started"
      server      = false
      node        = "kabuki"
    },
  ]
}

module "k3s" {
  source = "../modules/k3s-proxmox"

  proxmox = {
    privkey = "~/.ssh/id_rsa"
  }

  domain       = "wuhoo.xyz"
  vip_hostname = "k3s"

  iso                  = "cephfs:iso/nixos-24.05.20241030.080166c-x86_64-linux.iso"
  sops-server-key-path = "~/.config/sops/age/server-side-key.txt"

  hosts = local.hosts

  specs = {
    bridge  = "vmbr2"
    cores   = 4
    memory  = 8192
    balloon = 8192
    size    = "64G"
    sockets = 1
    storage = "rbd"
  }
}

resource "local_sensitive_file" "kubeconfig" {
  content         = module.k3s.k3s_kubeconfig
  filename        = pathexpand(var.config_path)
  file_permission = "0600"
}

resource "proxmox_lxc" "nixos" {
  target_node = "bake"
  hostname = "testing"
  ostemplate = "cephfs:vztmpl/nixos-system-x86_64-linux.tar.xz"
  unprivileged = true
  password = "password"

  ssh_public_keys = file(pathexpand("~/.ssh/id_rsa.pub"))

  cores = 2
  memory = 4096
  swap = 0

  start = true
  onboot = true
  #hastate = "started"

  features {
    nesting = true
  }

  rootfs {
    storage = "rbd"
    size = "32G"
  }

  network {
    name = "eth0"
    bridge = "vmbr2"
    hwaddr = "02:9a:87:4e:cc:ff"
    ip = "dhcp"
    ip6 = "manual"
    firewall = false
  }
}

module "nixos" {
  for_each = setunion(
    [for host in local.hosts : host.hostname],
  )

  depends_on = [module.k3s]
  source     = "github.com/Gabriella439/terraform-nixos-ng//nixos"

  host  = "nixos@${each.key}"
  flake = "../../nix#${each.key}"
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
  depends_on = [module.k3s]
  source     = "../modules/gitlab"

  public_key_openssh = resource.tls_private_key.flux.public_key_openssh

  gitlab = var.gitlab
}

# Bootstrap Flux
provider "kubernetes" {
  config_path = resource.local_sensitive_file.kubeconfig.filename
}

provider "flux" {
  kubernetes = {
    config_path = resource.local_sensitive_file.kubeconfig.filename
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
    module.k3s,
    resource.local_sensitive_file.kubeconfig,
    module.gitlab,
  ]
  source = "../modules/fluxcd"

  sops_key_path = var.sops_key_path
  fluxcd_path   = var.fluxcd_path
}
