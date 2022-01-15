variable "proxmox" {
  type = object({
    api_url          = string
    api_token_id     = string
    api_token_secret = string
  })
}