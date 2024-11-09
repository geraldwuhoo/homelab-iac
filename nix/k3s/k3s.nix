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
      singleNode = mkOption {
        type = types.bool;
        description = "Whether or not this is a single node cluster";
        default = false;
      };
    };
  };
  config = {
    environment.systemPackages =
      with pkgs;
      [
        ceph-client # ceph kernel modules for ceph-csi
      ]
      ++ (
        if config.k3s.master then
          [
            etcd # for etcdctl
          ]
        else
          [ ]
      );

    programs.bash.shellAliases =
      {
        k = "kubectl";
        dropcaches = "sync; echo 3 > /proc/sys/vm/drop_caches";
      }
      // (
        if config.k3s.master then
          {
            ketcdctl = "etcdctl --cacert=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt --cert=/var/lib/rancher/k3s/server/tls/etcd/client.crt --key=/var/lib/rancher/k3s/server/tls/etcd/client.key";
          }
        else
          { }
      );

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

    networking.firewall.allowedTCPPorts =
      [
        6443 # k3s: required so that pods can reach the API server (running on port 6443 by default)
      ]
      ++ (
        if config.k3s.singleNode then
          [ ]
        else
          [
            2379 # k3s, etcd clients: required if using a "High Availability Embedded etcd" configuration
            2380 # k3s, etcd peers: required if using a "High Availability Embedded etcd" configuration
            5001 # k3s: embedded Spigel registry mirror
            10250 # k3s: metrics server
          ]
      );
    networking.firewall.allowedUDPPorts =
      if config.k3s.singleNode then
        [ ]
      else
        [
          8472 # k3s, flannel: required if using multi-node for inter-node networking
        ];

    sops.secrets.k3s-token = { };

    services.k3s = {
      enable = true;
      role = if config.k3s.master then "server" else "agent";
      tokenFile = if config.k3s.singleNode then null else config.sops.secrets.k3s-token.path;
      serverAddr = if config.k3s.singleNode then "" else "https://k3s.wuhoo.xyz:6443";

      extraFlags = toString (
        [ ]
        ++ (
          if config.k3s.master then
            if config.k3s.singleNode then
              [
                "--tls-san ${config.networking.hostName}.wuhoo.xyz"
                "--disable traefik"
                "--disable local-storage"
                "--disable-cloud-controller"
                "--kubelet-arg node-status-update-frequency=5s"
                "--kube-controller-manager-arg node-monitor-period=5s"
                "--kube-controller-manager-arg node-monitor-grace-period=20s"
              ]
            else
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
      # Enable both embedded Spigel registry and external registry mirrors
      "rancher/k3s/registries.yaml" = {
        source = ./manifests/registries.yaml;
        mode = "0644";
      };
    };
  };
}
