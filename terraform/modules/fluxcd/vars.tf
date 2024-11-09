variable "sops_key_path" {
  type = string
}

variable "fluxcd_path" {
  type = string
}

variable "patch" {
  type    = bool
  default = true
}
