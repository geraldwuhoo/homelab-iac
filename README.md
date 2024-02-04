# Homelab deployment

Infrastructure as Code files for homelab cluster.

## What does this do?

Starting with a minimal working Proxmox cluster, Ceph cluster, and [openSUSE MicroOS cloud-init image](https://en.opensuse.org/Portal:MicroOS/Downloads), this IaC repo configures the following:

* HA Kubernetes cluster deployed via `k3s`
    * 3 controlplane nodes (able to run workloads)
    * 3 worker nodes
* Idempotent creation/destruction of Kubernetes nodes
* Kube-vip floating IP via ARP for HA entrypoint to cluster
* Kube-vip cloud controller for services of type LoadBalancer
* Nginx-ingress-controller for services of type Ingress
* Cert-manager with automatic Let's Encrypt wildcard certificates via Cloudflare DNS-01 verification
* Ceph-CSI driver for both RBD-backed and CephFS-backed dynamic PersistentVolumeClaims 
* Copies the generated Kubernetes config file to local `${HOME}/.kube/config` to allow local control of the remote cluster via `kubectl`
* Automatic rolling upgrades of the OS via `kured`
* Automatic rolling upgrades of `k3s` via `system-upgrade-controller`
* Deploys many pre-configured services using `flux` gitops (see [FluxCD gitops](#fluxcd-gitops) section)
* Fully HA backed services with HA Postgres and HA Redis/KeyDB
  * Zalando's Postgres operator is used for multi-replica Postgres for true HA failover during rolling upgrades
  * KeyDB is used in place of Redis for multi-master "Redis" for true HA during rolling upgrades

## Requirements

* `terraform`
* `sops`
* `age` (optional, but please use `age` instead of PGP)
* `flux2`

## Pre-deployment steps

### Expected infrastructure

The following already-existing infrastructure is expected for the IaC to work:

* Proxmox cluster
* Ceph cluster, with RBD and CephFS pools
* Registered [openSUSE MicroOS cloud-init image](https://en.opensuse.org/Portal:MicroOS/Downloads)
* Static DHCP leases for expected Kubernetes nodes
* DNS record for expected floating IP
* PostgreSQL cluster (optional, Terraform remote state backend)

### Configuration variables

Replace relevant variables in `terraform/k3s/main.tf`, `terraform/config.sops.yaml` as applicable. Self-explanatory.

### Terraform remote state

The Terraform config is configured to store its state in a remote postgresql cluster. To use your own postgresql cluster, you can initialize the Terraform/Terragrunt with:

```
terraform init
```

This will prompt for the postgresql connection string, which will be stored for future use. In case you do not have a postgresql cluster, you can instead store state locally, but be sure to secure this as it contains sensitive data and certainly should not be pushed unencrypted to a git repo. To store the state locally, delete the `backend "pg" {}` line in the `terraform` block in `terraform/main.tf`.

### Sops and Terraform

The `terraform/k3s/config.sops.yaml` has sensitive variables encrypted with `sops`. The `sops` encryption expects an `age` key at `${HOME}/.config/sops/age/keys.txt` with corresponding public key `age145q8qdg9ljfsl88dl3d5j9qqcq62nhev49eyqj30ssl5ryqc5vgssrmuau`. If you do not have this key, you can delete the `sops` metadata section in `terraform/config.yaml` and replace the encrypted sensitive data with unencrypted secrets. Then, re-encrypt in place with:

```
sops --encrypted-regex "(api.*|macaddr|username|password|connection_url)" --encrypt --in-place terraform/k3s/config.sops.yaml
```

### Optional: Delay startup delay for all VMs to allow hyperconverged ceph to initialize

If you're running a Ceph cluster hyperconverged on Proxmox cluster, then it's convenient to wait for Ceph intialization before attempting VM autostart.

```
pvenode config set --startall-onboot-delay 180
```

## Deployment steps


### Step 1: Deploy VMs and `k3s` cluster

```
$ cd terraform/k3s
$ terraform init
$ terraform apply
```

That's it!

## Redeployment/upgrade steps

Let's say you want to redeploy a node for any reason (perhaps it's unhealthy). Then:

1. Log in to the PVE UI and delete the VM from the UI.
1. Recreate and rejoin the node to the Kubernetes infrastructure:

    `terraform apply`

1. Repeat steps 1-2 for each node in the cluster as necessary.

**IT IS IMPORTANT THAT YOU RUN EACH STEP SEQUENTIALLY. DO NOT RUN IN PARALLEL.**

## FluxCD gitops

Deployments and services are managed by FluxCD, in the `fluxcd` directory. In order to use the CD managed by FluxCD, the cluster expects the correct SOPS key in the cluster as follows:

```
kubectl create namespace flux-system && kubectl -n flux-system create secret generic sops-age --from-file=keys.agekey=${HOME}/.config/sops/age/keys.txt
```

Then, the cluster can be bootstrapped with FluxCD with:

```
export GITLAB_TOKEN=<GITLAB_TOKEN>
flux bootstrap gitlab --owner=geraldwuhoo --repository=homelab-iac --branch=master --path=fluxcd/clusters/production --token-auth --personal
```

FluxCD will now automatically monitor changes to the repo and deploy them to the cluster.

### On-premise services

This FluxCD infrastructure deploys the following to on-prem production:

#### Core services

* `ceph-csi` storageclass
* `cert-manager`
* `Descheduler`
* `external-dns`
* Nginx ingress controller
* `keel.sh`
* `kube-vip` cloud controller manager
* Zalando's Postgres operator
* Rancher's `system-upgrade-controller`
* `velero` backup software

#### Core resources

* Let's Encrypt certificates via `cert-manager`
* Controlplane and worker node upgrade plans via `system-upgrade-controller`
* Velero backup locations and schedule via `velero`

#### User-facing services

* [Authentik SSO](https://goauthentik.io) (SAML2, OIDC/Oauth2, LDAP provider)
* Fully HA [Nextcloud](https://nextcloud.com) (SAML2)
* [GitLab EE](https://about.gitlab.com) with fully working CI/CD and registries (SAML2)
* [Matrix Synapse](https://matrix.org) with workers and bridges (OIDC/Oauth2)
* [Jellyfin](https://jellyfin.org) (LDAP)
  * Sonarr, Radarr, Prowlarr (SSO Proxied)
  * Transmission (SSO Proxied)
* [Wikijs](https://js.wiki) (OIDC/Oauth2)
* [`kubernetes-dashboard`](https://github.com/kubernetes/dashboard)
* [Vaultwarden](https://github.com/dani-garcia/vaultwarden)
* [Arch Linux packages mirror](https://mirror.wuhoo.xyz)
* [Gotify](https://gotify.net)
* [Homer](https://github.com/bastienwirtz/homer)
* [PrivateBin](https://privatebin.info)
* [timvisee's `send`](https://gitlab.com/timvisee/send)
* [Syncthing](https://syncthing.net)
* [Wallabag](https://wallabag.it)
