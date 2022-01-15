variable "proxmox" {
  type = object({
    api_url          = string
    api_token_id     = string
    api_token_secret = string
  })
}

variable "cluster" {
  type = list(object({
    type = string
    specs = object({
      cores   = number
      memory  = number
      balloon = number
      storage = string
    })
    nodes = list(object({
      vmid          = number
      name          = string
      node          = string
      macaddr       = string
      template_name = string
    }))
  }))
}
