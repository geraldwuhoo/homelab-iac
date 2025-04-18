{ lib, config, ... }:

let
  registries = {
    registry-hub = {
      volumes = [ "${config.sops.templates.dockerhub-config.path}:/etc/distribution/config.yml:ro" ];
    };
    registry-devcache = { };
    registry-gcr = {
      environment = {
        "REGISTRY_PROXY_REMOTEURL" = "https://gcr.io";
      };
    };
    registry-ghcr = {
      environment = {
        "REGISTRY_PROXY_REMOTEURL" = "https://ghcr.io";
      };
    };
    registry-k8sgcr = {
      environment = {
        "REGISTRY_PROXY_REMOTEURL" = "https://k8s.gcr.io";
      };
    };
    registry-quay = {
      environment = {
        "REGISTRY_PROXY_REMOTEURL" = "https://quay.io";
      };
    };
    registry-registryk8s = {
      environment = {
        "REGISTRY_PROXY_REMOTEURL" = "https://registry.k8s.io";
      };
    };
    registry-rgitlab = {
      environment = {
        "REGISTRY_PROXY_REMOTEURL" = "https://registry.gitlab.com";
      };
    };
  };
in
{
  # Create config file for DockerHub with login credentials
  sops.secrets.registry-proxy-username = { };
  sops.secrets.registry-proxy-password = { };
  sops.templates.dockerhub-config = {
    content = ''
      version: 0.1
      log:
        fields:
          service: registry
      storage:
        cache:
          blobdescriptor: inmemory
        filesystem:
          rootdirectory: /var/lib/registry
        maintenance:
          uploadpurging:
            enabled: false
        tag:
          concurrencylimit: 8
        delete:
          enabled: true
      http:
        addr: :5000
        headers:
          X-Content-Type-Options: [nosniff]
      proxy:
        remoteurl: "https://registry-1.docker.io"
        username: ${config.sops.placeholder.registry-proxy-username}
        password: ${config.sops.placeholder.registry-proxy-password}
        ttl: 168h
      health:
        storagedriver:
          enabled: true
          interval: 10s
          threshold: 3
    '';
  };

  # Generate all registry containers
  virtualisation.oci-containers.containers = builtins.mapAttrs (name: container: {
    image = "docker.io/library/registry:3.0.0-rc.3";
    environment = {
      "OTEL_TRACES_EXPORTER" = "none";
    } // (container.environment or { });
    volumes = container.volumes or [ ];
    log-driver = "journald";
    labels = {
      "io.containers.autoupdate" = "image";
    };
    extraOptions = [
      "--network-alias=${lib.strings.removePrefix "registry-" name}"
      "--network=main"
    ];
  }) registries;

  # Generate all systemd services for registry containers
  systemd.services =
    builtins.mapAttrs
      (name: container: {
        serviceConfig = {
          Restart = lib.mkOverride 90 "always";
        };
        partOf = [ "podman-compose-registry-root.target" ];
        wantedBy = [ "podman-compose-registry-root.target" ];
      })
      (
        builtins.listToAttrs (
          builtins.map (x: {
            name = "podman-" + x;
            value = { };
          }) (builtins.attrNames registries)
        )
      );

  # Root service
  # When started, this will automatically create all resources and start
  # the containers. When stopped, this will teardown all resources.
  systemd.targets."podman-compose-registry-root" = {
    unitConfig = {
      Description = "Root target generated by compose2nix.";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
