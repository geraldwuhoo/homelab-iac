terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.1-rc4"
    }
  }
}

resource "proxmox_vm_qemu" "k3s_node" {
  count = length(var.hosts)

  vmid = 3000 + count.index
  name = var.hosts[count.index].hostname
  desc = "k3s node ${count.index}"

  target_node = var.hosts[count.index].node
  hastate     = var.hosts[count.index].hastate
  onboot      = true
  skip_ipv6   = true

  cores   = var.specs.cores
  sockets = var.specs.sockets
  memory  = var.specs.memory
  balloon = var.specs.balloon
  tablet  = false
  agent   = 1
  qemu_os = "l26"
  scsihw  = "virtio-scsi-pci"

  serial {
    id   = 0
    type = "socket"
  }

  disks {
    scsi {
      scsi0 {
        disk {
          storage    = var.specs.storage
          size       = var.specs.size
          emulatessd = true
          discard    = true
        }
      }
    }
    ide {
      ide2 {
        cdrom {
          iso = var.iso
        }
      }
    }
  }

  network {
    model   = "virtio"
    macaddr = var.hosts[count.index].mac_address
    bridge  = var.specs.bridge
  }

  agent_timeout = "900"
  timeouts {
    create = "15m"
    delete = "5m"
  }

  # Run nixos-anywhere to provision the node
  provisioner "local-exec" {
    interpreter = ["bash", "-c"] # sorry not posix
    command     = <<-EOT
      set -ex

      # Wait until node is reachable
      until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 nixos@${self.name} true 2> /dev/null 
      do
        echo "Waiting for NixOS installer to become available..."
        sleep 3
      done

      # Copy age key to remote
      tempdir="$(mktemp -d)"
      trap 'rm -rfv -- "$tempdir"' EXIT
      mkdir -pv "$tempdir"/sops/persist/var/lib/sops/age
      cp -av ${var.sops-server-key-path} "$tempdir"/sops/persist/var/lib/sops/age

      # Install nixos configuration
      nix run github:nix-community/nixos-anywhere -- --extra-files "$tempdir"/sops --flake "../../nix#${self.name}" nixos@${self.name}
    EOT
  }
}

data "external" "kubeconfig" {
  depends_on = [
    proxmox_vm_qemu.k3s_node
  ]

  program = [
    "ssh",
    "-o UserKnownHostsFile=/dev/null",
    "-o StrictHostKeyChecking=no",
    "root@${proxmox_vm_qemu.k3s_node[0].name}",
    "echo '{\"kubeconfig\":\"'$(cat /etc/rancher/k3s/k3s.yaml | base64)'\"}'"
  ]
}

# resource "tls_private_key" "trustanchor_key" {
#   algorithm   = "ECDSA"
#   ecdsa_curve = "P256"
# }

# resource "tls_self_signed_cert" "trustanchor_cert" {
#   private_key_pem       = tls_private_key.trustanchor_key.private_key_pem
#   validity_period_hours = 87600
#   is_ca_certificate     = true

#   subject {
#     common_name    = "identity.linkerd.cluster.local"
#     street_address = []
#   }

#   allowed_uses = [
#     "crl_signing",
#     "cert_signing",
#     "server_auth",
#     "client_auth"
#   ]
# }

# resource "tls_private_key" "issuer_key" {
#   algorithm   = "ECDSA"
#   ecdsa_curve = "P256"
# }

# resource "tls_cert_request" "issuer_req" {
#   private_key_pem = tls_private_key.issuer_key.private_key_pem

#   subject {
#     common_name    = "identity.linkerd.cluster.local"
#     street_address = []
#   }
# }

# resource "tls_locally_signed_cert" "issuer_cert" {
#   cert_request_pem      = tls_cert_request.issuer_req.cert_request_pem
#   ca_private_key_pem    = tls_private_key.trustanchor_key.private_key_pem
#   ca_cert_pem           = tls_self_signed_cert.trustanchor_cert.cert_pem
#   validity_period_hours = 8760
#   is_ca_certificate     = true

#   allowed_uses = [
#     "crl_signing",
#     "cert_signing",
#     "server_auth",
#     "client_auth"
#   ]
# }

# resource "helm_release" "linkerd" {
#   name       = "linkerd"
#   repository = "https://helm.linkerd.io/stable"
#   chart      = "linkerd2"
#   version    = "2.11.2"

#   depends_on = [
#     data.external.kubeconfig
#   ]

#   values = [
#     "${file("${path.module}/linkerd_values.yaml")}"
#   ]

#   set {
#     name  = "identityTrustAnchorsPEM"
#     value = tls_self_signed_cert.trustanchor_cert.cert_pem
#   }

#   set {
#     name  = "identity.issuer.crtExpiry"
#     value = tls_locally_signed_cert.issuer_cert.validity_end_time
#   }

#   set {
#     name  = "identity.issuer.tls.crtPEM"
#     value = tls_locally_signed_cert.issuer_cert.cert_pem
#   }

#   set {
#     name  = "identity.issuer.tls.keyPEM"
#     value = tls_private_key.issuer_key.private_key_pem
#   }
# }

# resource "helm_release" "linkerd-viz" {
#   name       = "linkerd-viz"
#   repository = "https://helm.linkerd.io/stable"
#   chart      = "linkerd-viz"
#   version    = "2.11.2"

#   depends_on = [
#     helm_release.linkerd
#   ]

#   values = [
#     "${file("${path.module}/linkerd_viz_values.yaml")}"
#   ]
# }
