terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = ">= 2.9.0"
    }
  }
}

locals {
  cluster = flatten([
    for type in var.cluster : [
      for node in type.nodes : {
        type = type.type

        cores   = type.specs.cores
        memory  = type.specs.memory
        balloon = type.specs.balloon
        storage = type.specs.storage

        vmid          = node.vmid
        name          = node.name
        node          = node.node
        hastate       = node.hastate
        macaddr       = node.macaddr
        template_name = node.template_name
      }
    ]
  ])
}

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tmpl",
    {
      controlplane_names = var.cluster[index(var.cluster.*.type, "controlplane")].nodes.*.name
      worker_names       = var.cluster[index(var.cluster.*.type, "worker")].nodes.*.name
    }
  )
  filename             = "${path.module}/ansible/hosts.${var.cluster_name}"
  directory_permission = "0755"
  file_permission      = "0644"
}

resource "proxmox_vm_qemu" "kube-nodes" {
  for_each = { for node in local.cluster : node.vmid => node }
  vmid     = each.value.vmid
  name     = each.value.name

  agent = 1

  target_node = each.value.node
  hastate     = each.value.hastate
  onboot      = true

  clone      = each.value.template_name
  full_clone = false

  desc = format("%s cluster, %s node", var.cluster_name, each.value.type)
  tags = var.cluster_name

  cores    = each.value.cores
  sockets  = 1
  memory   = each.value.memory
  balloon  = each.value.balloon
  bios     = "ovmf"
  bootdisk = "scsi0"
  tablet   = false

  disk {
    slot    = 0
    type    = "scsi"
    storage = var.scsi_storage
    size    = each.value.storage
    ssd     = 1
    discard = "on"
  }

  network {
    model   = "virtio"
    macaddr = each.value.macaddr
    bridge  = "vmbr2"
  }

  timeouts {
    create = "10m"
    delete = "5m"
  }

  provisioner "local-exec" {
    when       = destroy
    command    = "cd ${path.module}/ansible; kubectl drain --ignore-daemonsets --delete-emptydir-data ${self.name}; ansible --inventory=\"hosts.${self.tags}\" ${self.name} -m shell -a \"subscription-manager remove --all; subscription-manager unregister; subscription-manager clean; kubeadm reset --force\" -b; kubectl delete node ${self.name}; sed -i '/^${self.name}/d' ~/.ssh/known_hosts"
    on_failure = continue
  }

  depends_on = [
    local_file.ansible_inventory
  ]
}

resource "null_resource" "provisioner" {
  triggers = {
    "kube_nodes_instance_ids"      = "${join(",", values(proxmox_vm_qemu.kube-nodes)[*].vmid)}"
    "kube_nodes_instance_template" = "${join(",", values(proxmox_vm_qemu.kube-nodes)[*].clone)}"
  }

  provisioner "local-exec" {
    command = "cd ${path.module}/ansible && ansible-playbook --inventory=\"hosts.${var.cluster_name}\" --extra-vars='vip_hostname=\"${var.cluster_name}\"' k8s.yml"
  }

  depends_on = [
    proxmox_vm_qemu.kube-nodes
  ]
}

resource "tls_private_key" "trustanchor_key" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "trustanchor_cert" {
  key_algorithm         = tls_private_key.trustanchor_key.algorithm
  private_key_pem       = tls_private_key.trustanchor_key.private_key_pem
  validity_period_hours = 87600
  is_ca_certificate     = true

  subject {
    common_name    = "identity.linkerd.cluster.local"
    street_address = []
  }

  allowed_uses = [
    "crl_signing",
    "cert_signing",
    "server_auth",
    "client_auth"
  ]
}

resource "tls_private_key" "issuer_key" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "issuer_req" {
  key_algorithm   = tls_private_key.issuer_key.algorithm
  private_key_pem = tls_private_key.issuer_key.private_key_pem

  subject {
    common_name    = "identity.linkerd.cluster.local"
    street_address = []
  }
}

resource "tls_locally_signed_cert" "issuer_cert" {
  cert_request_pem      = tls_cert_request.issuer_req.cert_request_pem
  ca_key_algorithm      = tls_private_key.trustanchor_key.algorithm
  ca_private_key_pem    = tls_private_key.trustanchor_key.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.trustanchor_cert.cert_pem
  validity_period_hours = 8760
  is_ca_certificate     = true

  allowed_uses = [
    "crl_signing",
    "cert_signing",
    "server_auth",
    "client_auth"
  ]
}

resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  namespace  = "kube-system"

  depends_on = [
    null_resource.provisioner
  ]

  values = [
    "${file("${path.module}/cilium_values.yaml")}"
  ]
}

resource "helm_release" "linkerd" {
  name       = "linkerd"
  repository = "https://helm.linkerd.io/stable"
  chart      = "linkerd2"

  depends_on = [
    helm_release.cilium
  ]

  values = [
    "${file("${path.module}/linkerd_values.yaml")}"
  ]

  set {
    name  = "identityTrustAnchorsPEM"
    value = tls_self_signed_cert.trustanchor_cert.cert_pem
  }

  set {
    name  = "identity.issuer.crtExpiry"
    value = tls_locally_signed_cert.issuer_cert.validity_end_time
  }

  set {
    name  = "identity.issuer.tls.crtPEM"
    value = tls_locally_signed_cert.issuer_cert.cert_pem
  }

  set {
    name  = "identity.issuer.tls.keyPEM"
    value = tls_private_key.issuer_key.private_key_pem
  }
}

resource "helm_release" "linkerd-viz" {
  name       = "linkerd-viz"
  repository = "https://helm.linkerd.io/stable"
  chart      = "linkerd-viz"

  depends_on = [
    helm_release.linkerd
  ]

  values = [
    "${file("${path.module}/linkerd_viz_values.yaml")}"
  ]
}
