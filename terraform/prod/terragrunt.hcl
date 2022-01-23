include "root" {
    path = find_in_parent_folders()
}

locals {
    kubernetes = {
        config_path = "~/.kube/prod.config"
    }
}

inputs = {
    kubernetes = local.kubernetes
}
