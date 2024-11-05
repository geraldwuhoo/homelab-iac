{
  pkgs,
  lib,
  config,
  ...
}:

{
  options = {
    k3s = with lib; {
      master = mkOption {
        type = types.bool;
        description = "Whether or not this is a master node";
      };
    };
  };
  config = {
    environment.systemPackages =
      with pkgs;
      [
        # ceph kernel modules for ceph-csi
        ceph-client
      ]
      ++ (
        if config.k3s.master then
          [
            # for etcdctl
            etcd
          ]
        else
          [ ]
      );

    programs.bash.shellAliases = {
      ketcdctl = "etcdctl --cacert=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt --cert=/var/lib/rancher/k3s/server/tls/etcd/client.crt --key=/var/lib/rancher/k3s/server/tls/etcd/client.key";
      dropcaches = "sync; echo 3 > /proc/sys/vm/drop_caches";
    };

    boot.kernelModules = [
      # ceph for ceph-csi
      "ceph"
      "rbd"

      # IPVS for kube-vip
      "ip_vs"
      "ip_vs_rr"

      # Wireguard for VPN
      "tun"
      "wireguard"
    ];

    networking.firewall.allowedTCPPorts = [
      6443 # k3s: required so that pods can reach the API server (running on port 6443 by default)
      2379 # k3s, etcd clients: required if using a "High Availability Embedded etcd" configuration
      2380 # k3s, etcd peers: required if using a "High Availability Embedded etcd" configuration
      5001 # k3s: embedded Spigel registry mirror
      10250 # k3s: metrics server
    ];
    networking.firewall.allowedUDPPorts = [
      8472 # k3s, flannel: required if using multi-node for inter-node networking
    ];

    sops.secrets.k3s-token = { };

    services.k3s = {
      enable = true;
      role = if config.k3s.master then "server" else "agent";
      tokenFile = config.sops.secrets.k3s-token.path;
      serverAddr = "https://k3s.wuhoo.xyz:6443";

      extraFlags = toString (
        [ ]
        ++ (
          if config.k3s.master then
            [
              "--tls-san k3s.wuhoo.xyz"
              "--disable traefik"
              "--disable servicelb"
              "--disable local-storage"
              "--disable-cloud-controller"
              "--kubelet-arg node-status-update-frequency=5s"
              "--kube-controller-manager-arg node-monitor-period=5s"
              "--kube-controller-manager-arg node-monitor-grace-period=20s"
              "--kube-controller-manager-arg bind-address=0.0.0.0"
              "--kube-proxy-arg metrics-bind-address=0.0.0.0"
              "--kube-scheduler-arg bind-address=0.0.0.0"
              "--etcd-expose-metrics"
              "--embedded-registry"
            ]
          else
            [ ]
        )
      );
    };

    environment.etc = {
      "rancher/k3s/registries.yaml".text = ''
        mirrors:
          "docker.io":
            endpoint:
            - "https://hub.wuhoo.xyz"
          "quay.io":
            endpoint:
            - "https://quay.wuhoo.xyz"
          "ghcr.io":
            endpoint:
            - "https://ghcr.wuhoo.xyz"
          "gcr.io":
            endpoint:
            - "https://gcr.wuhoo.xyz"
          "k8s.gcr.io":
            endpoint:
            - "https://k8sgcr.wuhoo.xyz"
          "registry.k8s.io":
            endpoint:
            - "https://registryk8s.wuhoo.xyz"
          "registry.gitlab.com":
            endpoint:
            - "https://rgitlab.wuhoo.xyz"
      '';
    };
  };
}
