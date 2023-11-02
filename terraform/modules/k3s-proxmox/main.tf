terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "2.9.14"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.0.4"
    }
  }
}

resource "random_password" "k3s_server_token" {
  length           = 32
  special          = false
  override_special = "_%@"
}

resource "null_resource" "cloud_init_config_file" {
  count = length(var.hosts)

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(pathexpand(var.proxmox.privkey))
    host        = "bake"
  }

  provisioner "file" {
    content = templatefile("${path.module}/templates/user_data.yaml.templ", {
      pubkey     = file(pathexpand(var.pubkey))
      hostname   = var.hosts[count.index].hostname
      domain     = var.domain
      vip        = "${var.vip_hostname}.${var.domain}"
      notify     = var.notify
      notify_url = var.notify_url
    })
    destination = "/mnt/pve/cephfs/snippets/user_data_${count.index}.yaml"
  }
}

resource "proxmox_vm_qemu" "k3s_node" {
  depends_on = [
    null_resource.cloud_init_config_file,
  ]
  count = length(var.hosts)

  vmid = 3000 + count.index
  name = var.hosts[count.index].hostname
  desc = "k3s node ${count.index}"

  target_node = var.hosts[count.index].node
  hastate     = var.hosts[count.index].hastate
  onboot      = true

  clone = var.template

  cores   = var.specs.cores
  sockets = var.specs.sockets
  memory  = var.specs.memory
  balloon = var.specs.balloon
  tablet  = false
  agent   = 1
  qemu_os = "l26"
  scsihw  = "virtio-scsi-pci"

  disk {
    type    = "scsi"
    storage = var.specs.storage
    size    = var.specs.size
    ssd     = 1
    discard = "on"
  }

  network {
    model   = "virtio"
    macaddr = var.hosts[count.index].mac_address
    bridge  = var.specs.bridge
  }

  timeouts {
    create = "15m"
    delete = "5m"
  }

  os_type = "cloud-init"

  cicustom                = "user=cephfs:snippets/user_data_${count.index}.yaml"
  cloudinit_cdrom_storage = var.specs.storage

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(pathexpand(var.privkey))
    host        = self.name
  }

  provisioner "remote-exec" {
    inline = [
      templatefile("${path.module}/templates/k3s_install.sh.templ", {
        secret   = nonsensitive(random_password.k3s_server_token.result)
        k3s_version  = var.k3s_version
        init     = count.index == 0 ? "--cluster-init" : "--server https://${var.vip_hostname}.${var.domain}:6443"
        hostname = self.name
        vip      = "${var.vip_hostname}.${var.domain}"
        server   = var.hosts[count.index].server
        mode     = var.hosts[count.index].server ? "server" : "agent"
      })
    ]
  }

  provisioner "local-exec" {
    command = <<-EOT
      ssh -o StrictHostKeyChecking=no root@${self.name} '(sleep 2; reboot)&'
      sleep 3
      until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 root@${self.name} true 2> /dev/null 
      do
        echo "Waiting for MicroOS to reboot or become available..."
        sleep 3
      done
    EOT
  }
}

data "external" "kubeconfig" {
  depends_on = [
    proxmox_vm_qemu.k3s_node
  ]

  program = [
    "/usr/bin/ssh",
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
