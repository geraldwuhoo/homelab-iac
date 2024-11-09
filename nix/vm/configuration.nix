{
  pkgs,
  lib,
  config,
  ...
}:
{
  imports = [ ./hardware-configuration.nix ];
  options = {
    vm = with lib; {
      efi = mkOption {
        type = types.bool;
        description = "Enable EFI support";
        default = false;
      };
    };
  };

  config = {
    services.qemuGuest.enable = true;

    boot.loader.efi.canTouchEfiVariables = config.vm.efi;
    boot.loader.grub = {
      enable = true;
      zfsSupport = true;
      efiSupport = config.vm.efi;
    };
    boot.loader.timeout = 1;
  };
}
