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
