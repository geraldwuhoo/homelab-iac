{
  services.tang = {
    enable = true;
    listenStream = [ "1234" ];
    ipAddressAllow = [ "10.0.0.0/8" ];
  };

  networking.firewall.allowedTCPPorts = [ 1234 ];

  fileSystems."/var/lib/private/tang" = {
    device = "/persist/var/lib/private/tang";
    fsType = "none";
    options = [ "bind" ];
  };
}
