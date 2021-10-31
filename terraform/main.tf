terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "2.8.0"
    }
  }
  backend "pg" {}
}

provider "proxmox" {
  pm_api_url          = var.pm_api_url
  pm_api_token_id     = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
}

resource "proxmox_vm_qemu" "kube-controlplane" {
  count = length(var.controlplane)
  vmid  = var.controlplane[count.index]["vmid"]
  name  = var.controlplane[count.index]["name"]

  agent                     = 1
  guest_agent_ready_timeout = 180

  target_node = var.controlplane[count.index]["node"]
  hastate     = "ignored"

  clone      = var.template_name
  full_clone = false

  cores    = 2
  sockets  = 1
  memory   = 8192
  balloon  = 4096
  bios     = "ovmf"
  bootdisk = "scsi0"

  disk {
    slot    = 0
    type    = "scsi"
    storage = var.scsi_storage
    size    = "64G"
    ssd     = 1
    discard = "on"
  }

  network {
    model   = "virtio"
    macaddr = var.controlplane[count.index]["macaddr"]
    bridge  = "vmbr2"
  }

  provisioner "local-exec" {
    when       = destroy
    command    = "cd ../ansible; kubectl drain --ignore-errors --ignore-daemonsets --delete-emptydir-data ${self.name}; ansible ${self.name} -m shell -a \"subscription-manager remove --all; subscription-manager unregister; subscription-manager clean; kubeadm reset --force\" -b; kubectl delete node ${self.name}"
    on_failure = continue
  }
}

resource "proxmox_vm_qemu" "kube-workers" {
  count = length(var.workers)
  vmid  = var.workers[count.index]["vmid"]
  name  = var.workers[count.index]["name"]

  agent                     = 1
  guest_agent_ready_timeout = 180

  target_node = var.workers[count.index]["node"]
  hastate     = "ignored"

  clone      = var.template_name
  full_clone = false

  cores    = 4
  sockets  = 1
  memory   = 16384
  balloon  = 2048
  bios     = "ovmf"
  bootdisk = "scsi0"

  disk {
    slot    = 0
    type    = "scsi"
    storage = var.scsi_storage
    size    = "64G"
    ssd     = 1
    discard = "on"
  }

  network {
    model   = "virtio"
    macaddr = var.workers[count.index]["macaddr"]
    bridge  = "vmbr2"
  }

  provisioner "local-exec" {
    when       = destroy
    command    = "cd ../ansible; kubectl drain --ignore-errors --ignore-daemonsets --delete-emptydir-data ${self.name}; ansible ${self.name} -m shell -a \"subscription-manager remove --all; subscription-manager unregister; subscription-manager clean; kubeadm reset --force\" -b; kubectl delete node ${self.name}"
    on_failure = continue
  }
}

resource "null_resource" "provisioner" {
  triggers = {
    "controlplane_instance_ids" = "${join(",", proxmox_vm_qemu.kube-controlplane.*.id)}"
    "workers_instance_ids"      = "${join(",", proxmox_vm_qemu.kube-workers.*.id)}"
  }

  provisioner "local-exec" {
    command = "cd ../ansible && ansible-playbook k8s.yml"
  }

  depends_on = [
    proxmox_vm_qemu.kube-controlplane,
    proxmox_vm_qemu.kube-workers
  ]
}

resource "local_file" "ansible_inventory" {
  content = templatefile("inventory.tmpl",
    {
      controlplane_names = proxmox_vm_qemu.kube-controlplane.*.name
      worker_names       = proxmox_vm_qemu.kube-workers.*.name
    }
  )
  filename             = "../ansible/hosts"
  directory_permission = "0755"
  file_permission      = "0644"
}
