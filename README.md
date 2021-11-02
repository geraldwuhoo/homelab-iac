# Homelab deployment

Infrastructure as Code files for homelab cluster.

## What does this do?

Starting with a minimal working Proxmox cluster, Ceph cluster, and RHEL8-based VM template, this IaC repo configures the following:

* HA Kubernetes cluster deployed via `kubeadm`
    * 3 controlplane nodes
    * 3 worker nodes
* Idempotent creation/destruction of Kubernetes nodes
* Kube-vip floating IP via ARP for HA entrypoint to cluster
* Kube-vip cloud controller for services of type LoadBalancer
* Nginx-ingress-controller for services of type Ingress
* Cert-manager with automatic Let's Encrypt wildcard certificates via Cloudflare DNS-01 verification
* Ceph-CSI driver for both RBD-backed and CephFS-backed dynamic PersistentVolumeClaims 
* Copies the generated Kubernetes config file to local `${HOME}/.kube/config` to allow local control of the remote cluster via `kubectl`

Importantly, each Kubernetes node is a linked clone to the RHEL8-based VM template. This saves significant storage, as the base OS and Kubernetes packages can be stored only once in the base VM template, instead of `size(cluster)` times.

Typically, this would cause problems when trying to upgrade the base template. However, this is solved easily with the idempotency of Terraform and Ansible. See the Redeployment/Upgrade section for more details.

## Requirements

* `terraform`
* `terragrunt`
* `ansible`
* `sops`
* `age` (optional, but please use `age` instead of PGP)

## Pre-deployment steps

### Expected infrastructure

The following already-existing infrastructure is expected for the IaC to work:

* Proxmox cluster
* Ceph cluster, with RBD and CephFS pools
* RHEL8-based VM template for Kubernetes nodes
* Static DHCP leases for expected Kubernetes nodes
* DNS record for expected floating IP
* PostgreSQL cluster (optional, Terraform remote state backend)

### Configuration variables

Replace relevant variables in `terraform/vars.tf`, `terraform/config.yaml`, `ansible/group_vars/*`, `ansible/host_vars/*` as applicable. Self-explanatory.

### Terraform remote state

The Terraform config is configured to store its state in a remote postgresql cluster. To use your own postgresql cluster, you can initialize the Terraform/Terragrunt with:

```
terragrunt init
```

This will prompt for the postgresql connection string, which will be stored for future use. In case you do not have a postgresql cluster, you can instead store state locally, but be sure to secure this as it contains sensitive data and certainly should not be pushed unencrypted to a git repo. To store the state locally, delete the `backend "pg" {}` line in the `terraform` block in `terraform/main.tf`.

### Sops and terragrunt

The `terraform/config.yaml` has sensitive variables encrypted with `sops`. The `sops` encryption expects an `age` key at `${HOME}/.config/sops/age/keys.txt` with corresponding public key `age145q8qdg9ljfsl88dl3d5j9qqcq62nhev49eyqj30ssl5ryqc5vgssrmuau`. If you do not have this key, you can delete the `sops` metadata section in `terraform/config.yaml` and replace the encrypted sensitive data with unencrypted secrets. Then, re-encrypt in place with:

```
sops --encrypted-regex "(api.*|macaddr|username|password|connection_url)" --encrypt --in-place terraform/config.yaml
```

### Sops and ansible

The `ansible/group_vars/*.sops.yml` has sensitive variables encrypted with `sops`. The `sops` encryption expects an `age` key at `${HOME}/.config/sops/age/keys.txt` with corresponding public key `age145q8qdg9ljfsl88dl3d5j9qqcq62nhev49eyqj30ssl5ryqc5vgssrmuau`. If you do not have this key, you can delete the `sops` metadata section in `ansible/group_vars/*.sops.yml` and replace the encrypted sensitive data with unencrypted secrets. Then, re-encrypt in place with:

```
sops --encrypt --in-place ansible/group_vars/${FILENAME}.sops.yml
```

### Optional: Delay startup delay for all VMs to allow hyperconverged ceph to initialize

If you're running a Ceph cluster hyperconverged on Proxmox cluster, then it's convenient to wait for Ceph intialization before attempting VM autostart.

```
pvenode config set --startall-onboot-delay 180
```

## Deployment steps


### Step 1: Deploy VMs and `kubeadm` cluster

```
terragrunt apply
```

That's it!

## Redeployment/upgrade steps

Let's say you want to update your base VM template, and you want to recreate your Kubernetes nodes to point at the new template. This is trivial since both Terraform and Ansible are idempotent.

1. Point the `template_name` var for a target node in `terraform/config.sops.yaml` at the name of the new template.
1. Recreate and rejoin the node (now based on the new template) to the Kubernetes infrastructure:

    `terragrunt apply`

1. Repeat steps 1-2 for each node in the cluster

**IT IS IMPORTANT THAT YOU RUN EACH STEP SEQUENTIALLY. DO NOT RUN IN PARALLEL.**

If you parallelize these instructions, it's possible to put your Kubernetes cluster in an inconsistent state. We are essentially doing a rolling upgrade of the cluster.
