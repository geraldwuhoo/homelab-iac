variable "config_path" {
  type    = string
  default = "~/.kube/k3s.config"
}

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
