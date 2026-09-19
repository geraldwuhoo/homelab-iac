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
      nodeIp = mkOption {
        type = types.nullOr types.str;
        description = "Address to advertise for this node, pinning the node IP rather than letting k3s auto-detect it from the default-gateway interface";
        default = null;
      };
    };
  };
  config =
    let
      mkContainerdShim = pkgs.callPackage ./containerd-shim.nix { };
      # k3s auto-detects these on its service PATH and generates the matching
      # containerd runtimes; the RuntimeClasses already ship with k3s.
      containerd-shims = [
        (mkContainerdShim {
          runtime = "wasmedge";
          version = "0.6.1";
          hashes = {
            x86_64-linux = "sha256-mff1bGSgUk6h7DkizQlbEIglpRPQIS23Wl37CLoZbM4=";
            aarch64-linux = "sha256-Sg+9gyPUAeyf8w49Zmxrg9J4BwqcJkkPYWsjqX8bxUY=";
          };
        })
        (mkContainerdShim {
          runtime = "wasmtime";
          version = "0.6.1";
          hashes = {
            x86_64-linux = "sha256-qbEhXuZw8RQUyP2OlwtSZ5CFkpyOxzoP5u2c8hXPm6E=";
            aarch64-linux = "sha256-CukicV3UhKkjgl/U+iUFL+APh2nSnCNnBPH1Y49zWuA=";
          };
        })
      ];
    in
    {
      boot = {
        kernel.sysctl = {
          "fs.inotify.max_user_instances" = 8192;
          "fs.inotify.max_user_watches" = 524288;
        };
        kernelModules = [
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
      };

      environment.systemPackages =
        with pkgs;
        [
          ceph-client # ceph kernel modules for ceph-csi
        ]
        ++ (lib.optionals (config.k3s.master) [
          etcd # for etcdctl
        ]);

      programs.bash.shellAliases =
        {
          k = "kubectl";
          dropcaches = "sync; echo 3 > /proc/sys/vm/drop_caches";
        }
        // (lib.optionalAttrs (config.k3s.master) {
          ketcdctl = "etcdctl --cacert=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt --cert=/var/lib/rancher/k3s/server/tls/etcd/client.crt --key=/var/lib/rancher/k3s/server/tls/etcd/client.key";
        });

      networking.firewall = {
        allowedTCPPorts =
          [
            6443 # k3s: required so that pods can reach the API server (running on port 6443 by default)
          ]
          ++ (lib.optionals (!config.k3s.singleNode) [
            2379 # k3s, etcd clients: required if using a "High Availability Embedded etcd" configuration
            2380 # k3s, etcd peers: required if using a "High Availability Embedded etcd" configuration
            5001 # k3s: embedded Spigel registry mirror
            10250 # k3s: metrics server
          ]);
        allowedUDPPorts = lib.mkIf (!config.k3s.singleNode) [
          8472 # k3s, flannel: required if using multi-node for inter-node networking
        ];
      };

      sops.secrets.k3s-token = { };

      systemd.services.k3s.path = containerd-shims;

      services.k3s = {
        enable = true;
        package = pkgs.k3s_1_35;
        role = if config.k3s.master then "server" else "agent";
        tokenFile = lib.mkIf (!config.k3s.singleNode) config.sops.secrets.k3s-token.path;
        serverAddr = lib.mkIf (!config.k3s.singleNode) "https://k3s.wuhoo.xyz:6443";

        extraFlags = toString (
          [
            "--kubelet-arg=allowed-unsafe-sysctls=net.ipv6.conf.all.disable_ipv6,net.ipv6.conf.default.disable_ipv6,net.ipv4.ip_forward,net.ipv4.conf.all.src_valid_mark"
          ]
          ++ (lib.optional (config.k3s.nodeIp != null) "--node-ip=${config.k3s.nodeIp}")
          ++ (
            if config.k3s.master then
              [
                "--disable traefik"
                "--disable local-storage"
                "--disable-cloud-controller"
                "--disable-helm-controller"
                "--kubelet-arg node-status-update-frequency=5s"
                "--kube-controller-manager-arg node-monitor-period=5s"
                "--kube-controller-manager-arg node-monitor-grace-period=20s"
              ]
              ++ (
                if config.k3s.singleNode then
                  [ "--tls-san ${config.networking.hostName}.wuhoo.xyz" ]
                else
                  [
                    "--tls-san k3s.wuhoo.xyz"
                    "--disable servicelb"
                    "--kube-controller-manager-arg bind-address=0.0.0.0"
                    "--kube-proxy-arg metrics-bind-address=0.0.0.0"
                    "--kube-scheduler-arg bind-address=0.0.0.0"
                    "--etcd-expose-metrics"
                    "--embedded-registry"
                  ]
              )
            else
              [ ]
          )
        );

        configPath = lib.mkIf (
          config.k3s.master && !config.k3s.singleNode
        ) config.sops.templates.k3s-config.path;

        manifests = lib.mkIf (config.k3s.master && !config.k3s.singleNode) (
          builtins.mapAttrs (name: file: { source = ./manifests/${name}.yaml; }) {
            kube-vip-rbac = { };
            kube-vip-ds = { };
            kube-vip-worker-ds = { };
          }
        );
      };

      sops.secrets.aws-access-key-id = lib.mkIf (config.k3s.master && !config.k3s.singleNode) { };
      sops.secrets.aws-secret-access-key = lib.mkIf (config.k3s.master && !config.k3s.singleNode) { };
      sops.templates.k3s-config = lib.mkIf (config.k3s.master && !config.k3s.singleNode) {
        content = ''
          etcd-s3: true
          etcd-s3-endpoint: s3.wuhoo.xyz
          etcd-s3-bucket: backup
          etcd-s3-folder: etcd
          etcd-s3-access-key: ${config.sops.placeholder.aws-access-key-id}
          etcd-s3-secret-key: ${config.sops.placeholder.aws-secret-access-key}
        '';
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
