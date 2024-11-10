{
  pkgs,
  lib,
  config,
  ...
}:

{
  options = {
    common = with lib; {
      keys = mkOption {
        type = types.listOf types.str;
        description = "SSH keys";
      };
    };
  };

  config = {
    nix.settings.auto-optimise-store = true;

    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
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

    nix.settings.trusted-users = [ "nixos" ];
    users.users.nixos = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = config.common.keys;
    };
    security.sudo.wheelNeedsPassword = false;

    programs.bash.shellAliases = {
      ngc = "sudo nix-collect-garbage -d --verbose";
    };

    environment.systemPackages = with pkgs; [
      # Standard utils, but some better
      fd
      htop-vim
      inetutils
      ncdu
      ripgrep
      tmux
      tree
      vim
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
