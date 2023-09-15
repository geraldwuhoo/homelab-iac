terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.40.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.14.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "0.7.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.0.4"
    }
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = "16.3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.23.0"
    }
    flux = {
      source  = "fluxcd/flux"
      version = "1.0.0-rc.5"
    }
  }
  backend "pg" {
    schema_name = "hetzner"
  }
}

provider "sops" {}

data "sops_file" "secret" {
  source_file = "secret.sops.yaml"
}

provider "hcloud" {
  token = data.sops_file.secret.data["hcloud_token"]
}

provider "cloudflare" {
  api_token = data.sops_file.secret.data["cloudflare_api_token"]
}

module "kube-hetzner" {
  providers = {
    hcloud = hcloud
  }
  hcloud_token = data.sops_file.secret.data["hcloud_token"]

  # Then fill or edit the below values. Only the first values starting with a * are obligatory; the rest can remain with their default values, or you
  # could adapt them to your needs.

  # * For local dev, path to the git repo
  # source = "../../../terraform-hcloud-kube-hetzner/" 
  # For normal use, this is the path to the terraform registry
  source = "kube-hetzner/kube-hetzner/hcloud"
  # you can optionally specify a version number
  version = "2.7.1"

  # Note that some values, notably "location" and "public_key" have no effect after initializing the cluster.
  # This is to keep Terraform from re-provisioning all nodes at once, which would lose data. If you want to update
  # those, you should instead change the value here and manually re-provision each node. Grep for "lifecycle".

  # * Your public key
  ssh_public_key = file(pathexpand("~/.ssh/id_ed25519_hetzner.pub"))
  # * Your private key must be "private_key = null" when you want to use ssh-agent for a Yubikey-like device authentification or an SSH key-pair with a passphrase.
  # For more details on SSH see https://github.com/kube-hetzner/kube-hetzner/blob/master/docs/ssh.md
  ssh_private_key = file(pathexpand("~/.ssh/id_ed25519_hetzner"))

  # These can be customized, or left with the default values
  # * For Hetzner locations see https://docs.hetzner.com/general/others/data-centers-and-connection/
  network_region = "us-east" # change to `us-east` if location is ash

  # For the control planes, at least three nodes are the minimum for HA. Otherwise, you need to turn off the automatic upgrade (see ReadMe).
  # As per Rancher docs, it must always be an odd number, never even! See https://rancher.com/docs/k3s/latest/en/installation/ha-embedded/
  # For instance, one is ok (non-HA), two is not ok, and three is ok (becomes HA). It does not matter if they are in the same nodepool or not! So they can be in different locations and of various types.

  # Of course, you can choose any number of nodepools you want, with the location you want. The only constraint on the location is that you need to stay in the same network region, Europe, or the US.
  # For the server type, the minimum instance supported is cpx11 (just a few cents more than cx11); see https://www.hetzner.com/cloud.

  # IMPORTANT: Before you create your cluster, you can do anything you want with the nodepools, but you need at least one of each control plane and agent.
  # Once the cluster is up and running, you can change nodepool count and even set it to 0 (in the case of the first control-plane nodepool, the minimum is 1),
  # you can also rename it (if the count is 0), but do not remove a nodepool from the list.

  # The only nodepools that are safe to remove from the list when you edit it are at the end of the lists. That is due to how subnets and IPs get allocated (FILO).
  # You can, however, freely add other nodepools at the end of each list if you want! The maximum number of nodepools you can create combined for both lists is 255.
  # Also, before decreasing the count of any nodepools to 0, it's essential to drain and cordon the nodes in question. Otherwise, it will leave your cluster in a bad state.

  # Before initializing the cluster, you can change all parameters and add or remove any nodepools. You need at least one nodepool of each kind, control plane, and agent.
  # The nodepool names are entirely arbitrary, you can choose whatever you want, but no special characters or underscore, and they must be unique; only alphanumeric characters and dashes are allowed.

  # If you want to have a single node cluster, have one control plane nodepools with a count of 1, and one agent nodepool with a count of 0.

  # * Example below:

  control_plane_nodepools = [
    {
      name        = "control-plane-ash",
      server_type = "cpx31",
      location    = "ash",
      labels      = [],
      taints      = [],
      count       = 1
    },
  ]

  agent_nodepools = [
    {
      name        = "agent-small-ash",
      server_type = "cpx11",
      location    = "ash",
      labels      = [],
      taints      = [],
      count       = 0
    },
  ]

  # * LB location and type, the latter will depend on how much load you want it to handle, see https://www.hetzner.com/cloud/load-balancer
  load_balancer_type     = "lb11"
  load_balancer_location = "ash"

  ### The following values are entirely optional

  # To use local storage on the nodes, you can enable Longhorn, default is "false".
  enable_longhorn = false

  # To disable Hetzner CSI storage, you can set the following to true, default is "false".
  disable_hetzner_csi = true

  # If you want to use a specific Hetzner CCM and CSI version, set them below; otherwise, leave them as-is for the latest versions.
  # hetzner_ccm_version = ""
  # hetzner_csi_version = ""

  # If you want to specify the Kured version, set it below - otherwise it'll use the latest version available
  # kured_version = ""

  # We give you the possibility to use letsencrypt directly with Traefik because it's an easy setup, however it's not optimal,
  # as the free version of Traefik causes a little bit of downtime when when the certificates get renewed. For proper SSL management,
  # we instead recommend you to use cert-manager, that you can easily deploy with helm; see https://cert-manager.io/.
  # traefik_acme_tls = true
  # traefik_acme_email = "mail@example.com"

  # If you want to enable the Nginx ingress controller (https://kubernetes.github.io/ingress-nginx/) instead of Traefik, you can set this to "nginx". Default is "traefik".
  # By the default we load optimal Traefik and Nginx ingress controller config for Hetzner, however you may need to tweak it to your needs, so to do,
  # we allow you to add a traefik_values and nginx_values, see towards the end of this file in the advanced section.
  # After the cluster is deployed, you can always use HelmChartConfig definition to tweak the configuration.
  # If you want to disable both controllers set this to "none"
  ingress_controller = "none"

  # If you want to disable the metric server, you can! Default is "true".
  enable_metrics_server = true

  # If you want to allow non-control-plane workloads to run on the control-plane nodes, set "true" below. The default is "false".
  # True by default for single node clusters.
  allow_scheduling_on_control_plane = true

  # If you want to disable the automatic upgrade of k3s, you can set this to false. The default is "true".
  automatically_upgrade_k3s = false

  # The default is "true" (in HA setup it works wonderfully well, with automatic roll-back to the previous snapshot in case of an issue).
  # IMPORTANT! For non-HA clusters i.e. when the number of control-plane nodes is < 3, you have to turn it off.
  automatically_upgrade_os = false

  # Allows you to specify either stable, latest, testing or supported minor versions (defaults to stable)
  # see https://rancher.com/docs/k3s/latest/en/upgrades/basic/ and https://update.k3s.io/v1-release/channels
  initial_k3s_channel = "stable"

  # The cluster name, by default "k3s"
  cluster_name = "personal-hetzner-k3s"

  # Whether to use the cluster name in the node name, in the form of {cluster_name}-{nodepool_name}, the default is "true".
  use_cluster_name_in_node_name = true

  # Adding extra firewall rules, like opening a port
  # More info on the format here https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/firewall
  extra_firewall_rules = [
    {
      direction       = "out"
      protocol        = "tcp"
      port            = "587"
      source_ips      = []
      destination_ips = ["0.0.0.0/0", "::/0"]
      description     = "SMTP outbound"
    },
    {
      direction       = "out"
      protocol        = "tcp"
      port            = "22"
      source_ips      = []
      destination_ips = ["0.0.0.0/0", "::/0"]
      description     = "SSH outbound for Flux git cloning"
    },
    {
      direction       = "in"
      protocol        = "udp"
      port            = "3478"
      source_ips      = ["0.0.0.0/0", "::/0"]
      destination_ips = []
      description     = "STUN inbound"
    },
    {
      direction       = "in"
      protocol        = "tcp"
      port            = "3478"
      source_ips      = ["0.0.0.0/0", "::/0"]
      destination_ips = []
      description     = "STUN inbound"
    },
    {
      direction       = "in"
      protocol        = "udp"
      port            = "5349"
      source_ips      = ["0.0.0.0/0", "::/0"]
      destination_ips = []
      description     = "STUN inbound"
    },
    {
      direction       = "in"
      protocol        = "tcp"
      port            = "5349"
      source_ips      = ["0.0.0.0/0", "::/0"]
      destination_ips = []
      description     = "STUN inbound"
    },
    {
      direction       = "in"
      protocol        = "udp"
      port            = "49152-65535"
      source_ips      = ["0.0.0.0/0", "::/0"]
      destination_ips = []
      description     = "STUN inbound"
    },
  ]
  # extra_firewall_rules = [
  #   # For Postgres
  #   {
  #     direction       = "in"
  #     protocol        = "tcp"
  #     port            = "5432"
  #     source_ips      = ["0.0.0.0/0", "::/0"]
  #     destination_ips = [] # Won't be used for this rule 
  #   },
  #   # To Allow ArgoCD access to resources via SSH
  #   {
  #     direction       = "out"
  #     protocol        = "tcp"
  #     port            = "22"
  #     source_ips      = [] # Won't be used for this rule 
  #     destination_ips = ["0.0.0.0/0", "::/0"]
  #   }
  # ]

  # If you want to configure additional Arguments for traefik, enter them here as a list and in the form of traefik CLI arguments; see https://doc.traefik.io/traefik/reference/static-configuration/cli/
  # Example: traefik_additional_options = ["--log.level=DEBUG", "--tracing=true"]
  # traefik_additional_options = []

  # Use the klipper LB, instead of the default Hetzner one, that has an advantage of dropping the cost of the setup,
  # but you would need to point your DNS to every schedulable IPs in your cluster (usually agents). The default is "false".
  # Automatically "true" in the case of single node cluster.
  enable_klipper_metal_lb = "true"

  # If you want to configure a different CNI for k3s, use this flag
  # possible values: flannel (Default), calico
  # Cilium or other would be easy to add, you can mirror how Calico was added. PRs are welcome!
  # CAVEATS: Calico is not supported when not using the Hetzner LB (like when use_klipper_lb is set to true or when using a single node cluster),
  # because of the following issue https://github.com/k3s-io/klipper-lb/issues/6.
  cni_plugin = "flannel"

  # If you want to disable the k3s default network policy controller, use this flag!
  # Calico overrides this value to true automatically, the default is "false".
  # disable_network_policy = true

  # If you want to disable the automatic use of placement group "spread". See https://docs.hetzner.com/cloud/placement-groups/overview/
  # That may be useful if you need to deploy more than 500 nodes! The default is "false".
  # placement_group_disable = true

  # You can enable cert-manager (installed by Helm behind the scenes) with the following flag, the default is "false".
  # enable_cert_manager = true

  # You can enable Rancher (installed by Helm behind the scenes) with the following flag, the default is "false".
  # When Rancher is enabled, it automatically installs cert-manager too, and it uses rancher's own certificates.
  # As for the number of replicas, it is set to the numbe of control plane nodes.
  # IMPORTANT: Rancher's install is quite memory intensive, you will require at least 4GB if RAM, meaning cx21 server type (for your control plane).
  # You can customized all of the above by creating and applying a HelmChartConfig to pass the helm chart values of your choice. 
  # See https://rancher.com/docs/k3s/latest/en/helm/ 
  # and https://rancher.com/docs/rancher/v2.6/en/installation/install-rancher-on-k8s/chart-options/
  # enable_rancher = true

  # When Rancher is deployed, by default is uses the "stable" channel. But this can be customized.
  # The allowed values are "stable", "latest", and "alpha".
  # rancher_install_channel = "latest"

  # Set your Rancher hostname, the default is "rancher.example.com".
  # It is a required value when using rancher, but up to you to point the DNS to it or not. 
  # You can also not point the DNS, and just port-forward locally via kubectl to get access to the dashboard.
  # rancher_hostname = "rancher.xyz.dev"

  # Separate from the above Rancher config (only use one or the other). You can import this cluster directly on an
  # an already active Rancher install. By clicking "import cluster" choosing "generic", giving it a name and pasting
  # the cluster registration url below. However, you can also ignore that and apply the url via kubectl as instructed
  # by Rancher in the wizard, and that would register your cluster too.
  # More information about the registration can be found here https://rancher.com/docs/rancher/v2.6/en/cluster-provisioning/registered-clusters/
  # rancher_registration_manifest_url = "https://rancher.xyz.dev/v3/import/xxxxxxxxxxxxxxxxxxYYYYYYYYYYYYYYYYYYYzzzzzzzzzzzzzzzzzzzzz.yaml"
}

resource "cloudflare_record" "hetzner" {
  zone_id         = data.sops_file.secret.data["cloudflare_zone_id"]
  name            = "hetzner"
  value           = module.kube-hetzner.control_planes_public_ipv4[0]
  type            = "A"
  ttl             = 60
  proxied         = false
  allow_overwrite = true
}

resource "local_sensitive_file" "kubeconfig" {
  content         = replace(module.kube-hetzner.kubeconfig_file, "default", "hetzner")
  filename        = pathexpand("~/.kube/hetzner.config")
  file_permission = "0600"
}

# Configure the GitLab repository for Flux
resource "tls_private_key" "flux" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

provider "gitlab" {
  token = data.sops_file.secret.data["gitlab_token"]
}

module "gitlab" {
  source     = "../modules/gitlab"

  public_key_openssh = resource.tls_private_key.flux.public_key_openssh

  gitlab = var.gitlab
}

# Bootstrap Flux
provider "kubernetes" {
  config_path = resource.local_sensitive_file.kubeconfig.filename
}

provider "flux" {
  kubernetes = {
    config_path = resource.local_sensitive_file.kubeconfig.filename
  }
  git = {
    url = "ssh://git@gitlab.com/${module.gitlab.gitlab_project.path_with_namespace}.git"
    ssh = {
      username    = "git"
      private_key = resource.tls_private_key.flux.private_key_pem
    }
    branch = var.gitlab.branch
  }
}

module "fluxcd" {
  depends_on = [
    module.kube-hetzner,
    resource.local_sensitive_file.kubeconfig,
    module.gitlab,
  ]
  source = "../modules/fluxcd"

  sops_key_path = var.sops_key_path
  fluxcd_path   = var.fluxcd_path
}

