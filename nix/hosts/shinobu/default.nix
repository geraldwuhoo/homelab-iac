{
  imports = [
    ./configuration.nix
    ../../services/watchtower
    ../../services/caddy
    ../../services/registry
    ../../services/tang
  ];
}
