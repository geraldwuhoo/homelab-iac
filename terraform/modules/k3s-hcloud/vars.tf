variable "name" {
  type = string
}

variable "domain" {
  type = string
}

variable "zone_id" {
  type      = string
  sensitive = true
}

variable "ssh_key_path" {
  type = string
}

variable "sops-server-key-path" {
  type = string
}

variable "server_type" {
  type    = string
  default = "cax21"
}

variable "datacenter" {
  type    = string
  default = "hel1-dc2"
}
