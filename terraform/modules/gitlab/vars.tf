variable "public_key_openssh" {
  type = string
}

variable "gitlab" {
  type = object({
    group        = string,
    project_name = string,
    branch       = string,
  })
}
