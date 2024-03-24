terraform {
  required_providers {
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = "16.10.0"
    }
  }
}
data "gitlab_project" "this" {
  path_with_namespace = "${var.gitlab.group}/${var.gitlab.project_name}"
}

resource "gitlab_deploy_key" "this" {
  project  = data.gitlab_project.this.id
  title    = "Flux"
  key      = var.public_key_openssh
  can_push = true
}
