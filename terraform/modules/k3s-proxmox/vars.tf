variable "proxmox" {
  type = object({
    privkey = string,
  })
  sensitive = true
}

variable "vip_hostname" {
  type = string
}

variable "domain" {
  type = string
}

variable "iso" {
  type = string
}

variable "sops-server-key-path" {
  type = string
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
