variable "proxmox" {
  type = object({
    privkey = string,
  })
  sensitive = true
}

variable "pubkey" {
  type = string
}

variable "privkey" {
  type      = string
  sensitive = true
}

variable "vip_hostname" {
  type = string
}

variable "domain" {
  type = string
}

variable "template" {
  type = string
}

variable "start_id" {
  type = number
}

variable "hosts" {
  type = list(object({
    mac_address = string,
    hostname    = string,
    hastate     = string,
    server      = bool,
    node        = string,
  }))
}

variable "specs" {
  type = object({
    cores   = number,
    sockets = number,
    memory  = number,
    balloon = number,
    storage = string,
    size    = string,
    bridge  = string,
  })
}

variable "k3s_version" {
  type = string
}

variable "notify" {
  type = bool
}

variable "notify_url" {
  type      = string
  sensitive = true
}
