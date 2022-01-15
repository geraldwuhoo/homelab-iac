variable "proxmox" {
  description = "Connection parameters for PVE cluster"
  type = object({
    api_url          = string
    api_token_id     = string
    api_token_secret = string
  })
}

variable "scsi_storage" {
  description = "Name of SCSI storage pool for VM disks"
  type        = string
}

variable "cluster" {
  description = "Cluster definition"
}

variable "cluster_name" {
  description = "Name of kubernetes cluster"
  type        = string
}
