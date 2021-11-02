
variable "pm_api_url" {
  type      = string
  sensitive = true
}

variable "pm_api_token_id" {
  type      = string
  sensitive = true
}

variable "pm_api_token_secret" {
  type      = string
  sensitive = true
}

variable "scsi_storage" {
  type    = string
  default = "rbd"
}

variable "controlplane" {
  type = list(object({
    vmid          = number
    name          = string
    node          = string
    macaddr       = string
    template_name = string
  }))
}

variable "workers" {
  type = list(object({
    vmid          = number
    name          = string
    node          = string
    macaddr       = string
    template_name = string
  }))
}
