include "root" {
    path = find_in_parent_folders()
}

locals {
    kubernetes = {
        config_path = "~/.kube/staging.config"
    }
}

inputs = {
    kubernetes = local.kubernetes
}
