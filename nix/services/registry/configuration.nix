# Auto-generated using compose2nix v0.3.2-pre.
{ lib, config, ... }:

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

  # Containers
  virtualisation.oci-containers.containers."registry-hub" = {
    image = "docker.io/library/registry:3.0.0-rc.1";
    environment = {
      "OTEL_TRACES_EXPORTER" = "none";
    };
    volumes = [ "${config.sops.templates.dockerhub-config.path}:/etc/distribution/config.yml:ro" ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=hub"
      "--network=main"
    ];
  };
  systemd.services."podman-registry-hub" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    partOf = [ "podman-compose-registry-root.target" ];
    wantedBy = [ "podman-compose-registry-root.target" ];
  };
  virtualisation.oci-containers.containers."registry-devcache" = {
    image = "docker.io/library/registry:3.0.0-rc.1";
    environment = {
      "OTEL_TRACES_EXPORTER" = "none";
    };
    log-driver = "journald";
    extraOptions = [
      "--network-alias=devcache"
      "--network=main"
    ];
  };
  systemd.services."podman-registry-devcache" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    partOf = [ "podman-compose-registry-root.target" ];
    wantedBy = [ "podman-compose-registry-root.target" ];
  };
  virtualisation.oci-containers.containers."registry-gcr" = {
    image = "docker.io/library/registry:3.0.0-rc.1";
    environment = {
      "OTEL_TRACES_EXPORTER" = "none";
      "REGISTRY_PROXY_REMOTEURL" = "https://gcr.io";
    };
    log-driver = "journald";
    extraOptions = [
      "--network-alias=gcr"
      "--network=main"
    ];
  };
  systemd.services."podman-registry-gcr" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    partOf = [ "podman-compose-registry-root.target" ];
    wantedBy = [ "podman-compose-registry-root.target" ];
  };
  virtualisation.oci-containers.containers."registry-ghcr" = {
    image = "docker.io/library/registry:3.0.0-rc.1";
    environment = {
      "OTEL_TRACES_EXPORTER" = "none";
      "REGISTRY_PROXY_REMOTEURL" = "https://ghcr.io";
    };
    log-driver = "journald";
    extraOptions = [
      "--network-alias=ghcr"
      "--network=main"
    ];
  };
  systemd.services."podman-registry-ghcr" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    partOf = [ "podman-compose-registry-root.target" ];
    wantedBy = [ "podman-compose-registry-root.target" ];
  };
  virtualisation.oci-containers.containers."registry-k8sgcr" = {
    image = "docker.io/library/registry:3.0.0-rc.1";
    environment = {
      "OTEL_TRACES_EXPORTER" = "none";
      "REGISTRY_PROXY_REMOTEURL" = "https://k8s.gcr.io";
    };
    log-driver = "journald";
    extraOptions = [
      "--network-alias=k8sgcr"
      "--network=main"
    ];
  };
  systemd.services."podman-registry-k8sgcr" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    partOf = [ "podman-compose-registry-root.target" ];
    wantedBy = [ "podman-compose-registry-root.target" ];
  };
  virtualisation.oci-containers.containers."registry-quay" = {
    image = "docker.io/library/registry:3.0.0-rc.1";
    environment = {
      "OTEL_TRACES_EXPORTER" = "none";
      "REGISTRY_PROXY_REMOTEURL" = "https://quay.io";
    };
    log-driver = "journald";
    extraOptions = [
      "--network-alias=quay"
      "--network=main"
    ];
  };
  systemd.services."podman-registry-quay" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    partOf = [ "podman-compose-registry-root.target" ];
    wantedBy = [ "podman-compose-registry-root.target" ];
  };
  virtualisation.oci-containers.containers."registry-registryk8s" = {
    image = "docker.io/library/registry:3.0.0-rc.1";
    environment = {
      "OTEL_TRACES_EXPORTER" = "none";
      "REGISTRY_PROXY_REMOTEURL" = "https://registry.k8s.io";
    };
    log-driver = "journald";
    extraOptions = [
      "--network-alias=registryk8s"
      "--network=main"
    ];
  };
  systemd.services."podman-registry-registryk8s" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    partOf = [ "podman-compose-registry-root.target" ];
    wantedBy = [ "podman-compose-registry-root.target" ];
  };
  virtualisation.oci-containers.containers."registry-rgitlab" = {
    image = "docker.io/library/registry:3.0.0-rc.1";
    environment = {
      "OTEL_TRACES_EXPORTER" = "none";
      "REGISTRY_PROXY_REMOTEURL" = "https://registry.gitlab.com";
    };
    log-driver = "journald";
    extraOptions = [
      "--network-alias=rgitlab"
      "--network=main"
    ];
  };
  systemd.services."podman-registry-rgitlab" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    partOf = [ "podman-compose-registry-root.target" ];
    wantedBy = [ "podman-compose-registry-root.target" ];
  };

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
