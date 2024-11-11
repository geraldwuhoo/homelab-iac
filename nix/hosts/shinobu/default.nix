{
  imports = [
    ./configuration.nix
    ../../modules/services/watchtower
    ../../modules/services/caddy
    ../../modules/services/registry
    ../../modules/services/tang
  ];
}
