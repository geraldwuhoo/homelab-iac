terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.50.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.52.0"
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

resource "hcloud_rdns" "primary_ip" {
  primary_ip_id = hcloud_primary_ip.primary_ip.id
  ip_address    = hcloud_primary_ip.primary_ip.ip_address
  dns_ptr       = "${var.name}.${var.domain}"
}

resource "hcloud_firewall" "firewall" {
  name = "${var.name}_firewall"

  // Inbound connections
  rule {
    direction   = "in"
    protocol    = "icmp"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "Allow incoming ICMP ping requests"
  }
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "Allow incoming SSH traffic"
  }
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "80"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "Allow incoming HTTP connections"
  }
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "443"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "Allow incoming HTTPS connections"
  }
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "6443"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "Allow incoming requests to the Kube API server"
  }
  rule {
    direction   = "in"
    protocol    = "udp"
    port        = "3478"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "STUN inbound"
  }
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "3478"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "STUN inbound"
  }
  rule {
    direction   = "in"
    protocol    = "udp"
    port        = "5349"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "STUN inbound"
  }
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "5349"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "STUN inbound"
  }
  rule {
    direction   = "in"
    protocol    = "udp"
    port        = "49152-65535"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "STUN inbound"
  }

  // Outbound connections
  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "Allow outbound ICMP ping requests"
  }
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "80"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "Allow outbound HTTP requests"
  }
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "443"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "Allow outbound HTTPS requests"
  }
  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "53"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "Allow outbound UDP DNS requests"
  }
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "53"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "Allow outbound TCP DNS requests"
  }
  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "123"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "Allow outbound UDP NTP requests"
  }
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "587"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "Allow outbound SMTP requests"
  }
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "22"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "SSH outbound for Flux git cloning"
  }
  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "443"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "Cloudflare Warp outbound"
  }
  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "2408"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "Cloudflare Warp outbound"
  }
  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "500"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "Cloudflare Warp outbound"
  }
  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "1701"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "Cloudflare Warp outbound"
  }
  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "4500"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "Cloudflare Warp outbound"
  }
  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "1637"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "AirVPN outbound"
  }
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
  name         = var.name
  image        = "ubuntu-24.04" # we just need _something_ to be running for nixos-anywhere
  server_type  = var.server_type
  datacenter   = var.datacenter
  ssh_keys     = [hcloud_ssh_key.primary_ssh_key.id]
  firewall_ids = [hcloud_firewall.firewall.id]

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
      until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 nixos@${self.name} true 2> /dev/null
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

data "external" "kubeconfig" {
  program = [
    "ssh",
    "-o UserKnownHostsFile=/dev/null",
    "-o StrictHostKeyChecking=no",
    "nixos@${var.name}",
    "echo '{\"kubeconfig\":\"'$(sudo cat /etc/rancher/k3s/k3s.yaml | base64)'\"}'"
  ]

  depends_on = [hcloud_server.node]
}
