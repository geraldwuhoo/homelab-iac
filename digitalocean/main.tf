terraform {
  backend "pg" {
    schema_name = "digitalocean"
  }
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 0.7"
    }
  }
}

variable "netmaker" {
  type = object({
    domain = string
  })
}

variable "status" {
  type = object({
    domain = string
  })
}

provider "sops" {}

data "sops_file" "secret" {
  source_file = "secret.sops.yaml"
}

provider "digitalocean" {
  token = data.sops_file.secret.data["do_token"]
}

resource "digitalocean_droplet" "gateway" {
  name      = "gateway"
  region    = "sfo3"
  image     = "ubuntu-20-04-x64"
  size      = "s-1vcpu-2gb"
  user_data = file("cloud-config.yaml")
}

resource "digitalocean_domain" "status" {
  name = var.status.domain
}

resource "digitalocean_record" "status_root" {
  domain = digitalocean_domain.status.id
  type   = "A"
  name   = "@"
  value  = digitalocean_droplet.gateway.ipv4_address
  ttl    = 30
}

resource "digitalocean_domain" "netmaker" {
  name = var.netmaker.domain
}

resource "digitalocean_record" "netmaker_root" {
  domain = digitalocean_domain.netmaker.id
  type   = "A"
  name   = "@"
  value  = digitalocean_droplet.gateway.ipv4_address
  ttl    = 30
}

resource "digitalocean_record" "netmaker_wildcard" {
  domain = digitalocean_domain.netmaker.id
  type   = "A"
  name   = "*"
  value  = digitalocean_droplet.gateway.ipv4_address
  ttl    = 30
}
