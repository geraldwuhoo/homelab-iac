terraform {
  backend "pg" {
    schema_name = "staging"
  }
}

module "kube_proxmox" {
  source       = "../modules/kube-proxmox"
  scsi_storage = "rbd"
  cluster      = var.cluster
  cluster_name = "staging"
}
