variable "sops_key_path" {
  type    = string
  default = "~/.config/sops/age/keys.txt"
}

variable "gitlab" {
  type = object({
    group        = string,
    project_name = string,
    branch       = string,
  })
  default = {
    group        = "geraldwuhoo",
    project_name = "homelab-iac"
    branch       = "master"
  }
}

variable "fluxcd_path" {
  type    = string
  default = "fluxcd/clusters/production"
}
