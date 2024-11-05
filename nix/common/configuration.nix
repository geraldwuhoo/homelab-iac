{
  pkgs,
  lib,
  config,
  ...
}:

{
  imports = [ ./hardware-configuration.nix ];
  options = {
    common = with lib; {
      keys = mkOption {
        type = types.listOf types.str;
        description = "Whether or not this is a master node";
      };
    };
  };

  config = {
    services.qemuGuest.enable = true;

    boot.loader.grub = {
      enable = true;
      zfsSupport = true;
      timeoutStyle = "countdown";
    };
    boot.loader.timeout = 1;
    boot.initrd.postDeviceCommands = lib.mkAfter ''
      echo "rolling back root to empty snapshot"
      zfs rollback -r zroot/ROOT/default@blank
    '';

    nix.settings.auto-optimise-store = true;

    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
      hostKeys = [
        {
          bits = 4096;
          path = "/persist/etc/ssh/ssh_host_rsa_key";
          type = "rsa";
        }
        {
          path = "/persist/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ];
    };
    users.users.root = {
      openssh.authorizedKeys.keys = config.common.keys;
    };

    environment.systemPackages = with pkgs; [
      # Standard utils, but some better
      htop-vim
      tmux
    ];

    sops = {
      defaultSopsFile = ../secrets/secrets.sops.yaml;
      defaultSopsFormat = "yaml";
      age.keyFile = "/persist/var/lib/sops/age/server-side-key.txt";
      age.sshKeyPaths = [ ];
      gnupg.sshKeyPaths = [ ];
    };

    system.stateVersion = "24.05";
  };
}
