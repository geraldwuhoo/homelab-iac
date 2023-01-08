terraform {
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "0.7.2"
    }
  }
  backend "pg" {
    schema_name = "k3s"
  }
}

provider "sops" {}

data "sops_file" "secret" {
  source_file = "${path.module}/config.sops.yaml"
}

module "k3s" {
  source = "../modules/k3s-proxmox"

  proxmox = {
    api_url          = data.sops_file.secret.data["proxmox.api_url"]
    api_token_id     = data.sops_file.secret.data["proxmox.api_token_id"]
    api_token_secret = data.sops_file.secret.data["proxmox.api_token_secret"]
    privkey          = "~/.ssh/id_rsa"
  }

  kubernetes = {
    config_path = "~/.kube/k3s.config"
  }

  pubkey       = "~/.ssh/id_rsa.pub"
  privkey      = "~/.ssh/id_rsa"
  domain       = "wuhoo.xyz"
  vip_hostname = "k3s"

  template = "microos-template"
  start_id = 3000

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

  specs = {
    bridge  = "vmbr2"
    cores   = 4
    memory  = 12288
    balloon = 8192
    size    = "64G"
    sockets = 1
    storage = "rbd"
  }

  notify     = true
  notify_url = data.sops_file.secret.data["notify_url"]
}

resource "local_sensitive_file" "kubeconfig" {
  content         = module.k3s.k3s_kubeconfig
  filename        = pathexpand("~/.kube/k3s.config")
  file_permission = "0600"
}
