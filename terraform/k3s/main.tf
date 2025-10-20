terraform {
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "1.2.1"
    }
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc04"
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
      version = "1.7.3"
    }
  }

  backend "s3" {
    bucket = "terraform"
    key    = "tfstate/k3s"
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
  sops-server-key-path = "~/.config/sops/age/server-side-key.txt"

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
  sops-server-key-path = local.sops-server-key-path

  hosts = local.hosts

  specs = {
    bridge  = "vmbr2"
    cores   = 4
    memory  = 10240
    balloon = 10240
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

locals {
  lxc_hosts = [
    {
      hostname = "shinobu"
      node     = "kabuki"
      networks = {
        "eth0" = {
          mac_address = "02:c9:f2:01:b1:45"
        }
      }
    },
    {
      hostname = "araragi"
      node     = "bake"
      networks = {
        "eth0" = {
          mac_address = "02:95:a7:a0:ee:b5"
          vlan        = 70
        }
      }
    }
  ]
}

resource "proxmox_lxc" "nixos" {
  for_each = { for host in local.lxc_hosts : host.hostname => host }

  target_node  = each.value.node
  hostname     = each.value.hostname
  ostemplate   = "cephfs:vztmpl/nixos-system-x86_64-linux.tar.xz"
  unprivileged = true

  ssh_public_keys = file(pathexpand("~/.ssh/id_rsa.pub"))

  cores  = 2
  memory = 4096
  swap   = 0

  start   = true
  onboot  = true
  hastate = "started"

  features {
    nesting = true
  }

  rootfs {
    storage = "rbd"
    size    = "32G"
  }

  dynamic "network" {
    for_each = each.value.networks

    content {
      name     = network.key
      bridge   = "vmbr2"
      hwaddr   = network.value.mac_address
      ip       = try(network.value.ip, "dhcp")
      ip6      = ""
      firewall = false
      tag      = try(network.value.vlan, null)
    }
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"] # sorry not posix
    command     = <<-EOT
      set -ex

      SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=2"

      # Wait until node is reachable
      until ssh $SSH_OPTS nixos@${self.hostname} true 2> /dev/null
      do
        echo "Waiting for NixOS installer to become available..."
        sleep 3
      done

      # Copy age key to remote
      ssh $SSH_OPTS nixos@${self.hostname} sudo mkdir -pv /persist/var/lib/sops/age
      scp $SSH_OPTS -v ${local.sops-server-key-path} nixos@${self.hostname}:server-side-key.txt
      ssh $SSH_OPTS nixos@${self.hostname} sudo mv -v ./server-side-key.txt /persist/var/lib/sops/age/
    EOT
  }
}

module "nixos" {
  for_each = setunion(
    [for host in local.hosts : host.hostname],
    [for host in local.lxc_hosts : host.hostname],
  )

  depends_on = [module.k3s, proxmox_lxc.nixos]
  source     = "github.com/Gabriella439/terraform-nixos-ng//nixos"

  host      = "nixos@${each.key}"
  flake     = "../../nix#${each.key}"
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
