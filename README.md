# Homelab deployment

Infrastructure as Code files for homelab cluster.

## What does this do?

Starting with a minimal working Proxmox cluster and Ceph cluster, this IaC repo configures the following:

* HA Kubernetes cluster deployed via `k3s`
    * 3 controlplane nodes (able to run workloads)
    * 4 worker nodes
* Idempotent creation/destruction of Kubernetes nodes using ephemeral NixOS
* `kube-vip` floating IP via ARP for HA entrypoint to cluster
* `kube-vip` cloud controller for services of type LoadBalancer
* `nginx-ingress-controller` for services of type Ingress
* `tor-controller` for Tor onion services
* `cert-manager` with automatic Let's Encrypt wildcard certificates via Cloudflare DNS-01 verification
* `ceph-csi` driver for both RBD-backed and CephFS-backed dynamic PersistentVolumeClaims 
* Copies the generated Kubernetes config file to local `${HOME}/.kube/config` to allow local control of the remote cluster via `kubectl`
* Deploys many pre-configured services using `flux` gitops (see [FluxCD gitops](#fluxcd-gitops) section)
* Fully HA backed services with HA Postgres and HA Redis/KeyDB
  * Zalando's Postgres operator is used for multi-replica Postgres for true HA failover during rolling upgrades
  * KeyDB is used in place of Redis for multi-master "Redis" for true HA during rolling upgrades

## Requirements

* `terraform`/`opentofu`
* `sops`
* `age` (optional, but please use `age` instead of PGP)
* `nix`
* `flux2`

## Pre-deployment steps

### Expected infrastructure

The following already-existing infrastructure is expected for the IaC to work:

* Proxmox cluster
* Ceph cluster, with RBD and CephFS pools
* Static DHCP leases for expected Kubernetes nodes
* DNS record for expected floating IP
* PostgreSQL cluster (optional, Terraform remote state backend)

### Configuration variables

Replace relevant variables in `terraform/k3s/main.tf`, `terraform/config.sops.yaml` as applicable. Self-explanatory.

### Terraform remote state

The Terraform config is configured to store its state in a remote postgresql cluster. To use your own postgresql cluster, you can initialize the Terraform/Terragrunt with:

```
tofu init
```

This will prompt for the postgresql connection string, which will be stored for future use. In case you do not have a postgresql cluster, you can instead store state locally, but be sure to secure this as it contains sensitive data and certainly should not be pushed unencrypted to a git repo. To store the state locally, delete the `backend "pg" {}` line in the `terraform` block in `terraform/main.tf`.

### Sops and Terraform

The `terraform/k3s/config.sops.yaml` has sensitive variables encrypted with `sops`. The `sops` encryption expects an `age` key at `${HOME}/.config/sops/age/keys.txt` with corresponding public key `age145q8qdg9ljfsl88dl3d5j9qqcq62nhev49eyqj30ssl5ryqc5vgssrmuau`. If you do not have this key, you can delete the `sops` metadata section in `terraform/config.yaml` and replace the encrypted sensitive data with unencrypted secrets. Then, re-encrypt in place with:

```
sops --encrypted-regex "(api.*|macaddr|username|password|connection_url)" --encrypt --in-place terraform/k3s/config.sops.yaml
```

### Creating the ISO

The ISO is just a standard NixOS install ISO with preconfigured guest agent and SSH keys. To build the ISO:

```
$ cd nix
$ nix build ".#nixosConfigurations.iso.config.system.build.isoImage"
```

This will build the ISO and link it in `nix/result`. Upload this ISO to PVE and update any references in Terraform to its filename.

### Creating the LXC template

The LXC template is a standard NixOS template with preconfigured SSH keys. To build the template:

```
$ cd nix
$ nix build ".#nixosConfigurations.lxc"
```

This will build the LXC template and link it in `nix/result`. Upload this template to PVE and update any references in Terraform to its filename.

### Optional: Delay startup delay for all VMs to allow hyperconverged ceph to initialize

If you're running a Ceph cluster hyperconverged on Proxmox cluster, then it's convenient to wait for Ceph intialization before attempting VM autostart.

```
pvenode config set --startall-onboot-delay 180
```

## Deployment steps


### Step 1: Deploy VMs and `k3s` cluster

```
$ cd terraform/k3s
$ tofu init
$ tofu apply
```

That's it!

### Background info: a note on the base OS

k3s runs on NixOS VMs. The NixOS VMs use ephemeral roots. They only save data at the following locations:

* `/nix`: Self-explanatory. Nix configuration and packages.
* `/persist`: SSH host keys and `sops-age` decryption key for secrets.
* `/var/lib/rancher`: Persistent k3s data.
* `/etc/rancher`: Persistent k3s data.

All other data is wiped on every boot by rolling back to an empty `zfs` snapshot. NixOS then fills in the root from its configuration and the nix-store at `/nix`.

## Redeployment/upgrade steps

Let's say you want to redeploy a node for any reason (perhaps it's unhealthy). Then:

1. Log in to the PVE UI and delete the VM from the UI.
1. Recreate and rejoin the node to the Kubernetes infrastructure:

    `tofu apply`

1. Repeat steps 1-2 for each node in the cluster as necessary.

**IT IS IMPORTANT THAT YOU RUN EACH STEP SEQUENTIALLY. DO NOT RUN IN PARALLEL.**

## Upgrading nodes

Since the nodes use NixOS with flakes, we first update the flake.lock to grab the latest packages:

```
$ cd nix
$ nix flake update
```

Then, we push out these changes to all remote hosts via Terraform:

```
$ cd terraform/k3s
$ tofu apply
```

That's it!

## FluxCD gitops

Deployments and services are managed by FluxCD, in the `fluxcd` directory. The terraform above automatically boostraps FluxCD into the cluster.

### On-premise services

This FluxCD infrastructure deploys the following to on-prem production:

#### Core services

* `ceph-csi` storageclass
* `cert-manager`
* `Descheduler`
* `external-dns`
* Nginx ingress controller
* [`tor-controller`](https://github.com/bugfest/tor-controller)
* `keel.sh`
* `kube-vip` cloud controller manager
* Zalando's Postgres operator
* `volsync` backup software

#### Core resources

* Let's Encrypt certificates via `cert-manager`

#### User-facing services

* [Authentik SSO](https://goauthentik.io) (SAML2, OIDC/Oauth2, LDAP provider)
* Fully HA [Nextcloud](https://nextcloud.com) (SAML2)
* [Immich](https://immich.app/) (OIDC/Oauth2)
* [GitLab EE](https://about.gitlab.com) with fully working CI/CD and registries (SAML2)
* [Matrix Synapse](https://matrix.org) with workers and bridges (OIDC/Oauth2)
* [Jellyfin](https://jellyfin.org) (LDAP)
* [Paperless-ngx](https://github.com/paperless-ngx/paperless-ngx) (OIDC/Oauth2)
* [blink](https://github.com/JaneJeon/blink) (OIDC/Oauth2)
* [Wikijs](https://js.wiki) (OIDC/Oauth2)
* [ntfy.sh](https://ntfy.sh)
* [mollysocket](https://github.com/mollyim/mollysocket)
* [`kubernetes-dashboard`](https://github.com/kubernetes/dashboard)
* [Vaultwarden](https://github.com/dani-garcia/vaultwarden)
* [Actualbudget](https://actualbudget.com/)
* [FindMyDevice](https://gitlab.com/Nulide/findmydevice)
* [Arch Linux packages mirror](https://mirror.wuhoo.xyz)
* [PrivateBin](https://privatebin.info)
* [Firefox SyncServer](https://github.com/mozilla-services/syncserver)
* [timvisee's `send`](https://gitlab.com/timvisee/send)
* [Syncthing](https://syncthing.net)
* [drawio](https://draw.io)
