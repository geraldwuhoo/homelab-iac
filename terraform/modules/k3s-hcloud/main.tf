terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.48.1"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.45.0"
    }
  }
}

resource "hcloud_ssh_key" "primary_ssh_key" {
  name       = "${var.name}_ssh_key"
  public_key = file(pathexpand(var.ssh_key_path))
}

resource "hcloud_primary_ip" "primary_ip" {
  name          = "${var.name}_ipv4"
  datacenter    = var.datacenter
  type          = "ipv4"
  assignee_type = "server"
  auto_delete   = false
}

resource "cloudflare_record" "name_record" {
  zone_id = var.zone_id
  name    = var.name
  content = hcloud_primary_ip.primary_ip.ip_address
  type    = "A"
  ttl     = 60
  proxied = false
}

resource "hcloud_server" "node" {
  name        = var.name
  image       = "ubuntu-24.04" # we just need _something_ to be running for nixos-anywhere
  server_type = var.server_type
  datacenter  = var.datacenter
  ssh_keys    = [hcloud_ssh_key.primary_ssh_key.id]

  public_net {
    ipv4_enabled = true
    ipv4         = hcloud_primary_ip.primary_ip.id
    ipv6_enabled = false
  }

  # Run nixos-anywhere to provision the node
  provisioner "local-exec" {
    interpreter = ["bash", "-c"] # sorry not posix
    command     = <<-EOT
      set -ex

      # Wait until node is reachable
      until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 root@${self.name} true 2> /dev/null 
      do
        echo "Waiting for NixOS installer to become available..."
        sleep 3
      done

      # Copy age key to remote
      tempdir="$(mktemp -d)"
      trap 'rm -rfv -- "$tempdir"' EXIT
      mkdir -pv "$tempdir"/sops/persist/var/lib/sops/age
      cp -av ~/.config/sops/age/server-side-key.txt "$tempdir"/sops/persist/var/lib/sops/age

      # Install nixos configuration
      nix run github:nix-community/nixos-anywhere -- --extra-files "$tempdir"/sops --flake "../../nix#${self.name}" root@${self.name}

      # Wait until node is reachable
      until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 root@${self.name} true 2> /dev/null 
      do
        echo "Waiting for NixOS to become available..."
        sleep 3
      done
    EOT
  }

  depends_on = [cloudflare_record.name_record]
  lifecycle {
    ignore_changes = [ssh_keys]
  }
}
