locals {
  config = yamldecode(sops_decrypt_file(("config.sops.yaml")))
}

inputs = {
  pm_api_url          = local.config.proxmox.api_url
  pm_api_token_id     = local.config.proxmox.api_token_id
  pm_api_token_secret = local.config.proxmox.api_token_secret

  controlplane = local.config.nodes.controlplane
  workers      = local.config.nodes.workers
}