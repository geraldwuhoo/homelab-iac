variable "proxmox" {
  type = object({
    api_url          = string,
    api_token_id     = string,
    api_token_secret = string,
    privkey          = string,
  })
}

variable "kubernetes" {
  type = object({
    config_path = string,
  })
}

variable "pubkey" {
  type = string
}

variable "privkey" {
  type = string
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

variable "nodes" {
  type = list(string)
}

variable "hosts" {
  type = list(object({
    mac_address = string,
    hostname    = string,
    hastate     = string,
    server      = bool,
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
