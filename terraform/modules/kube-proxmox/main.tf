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
