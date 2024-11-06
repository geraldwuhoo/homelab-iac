{
  lib,
  modulesPath,
  pkgs,
  ...
}:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [
    "ata_piix"
    "uhci_hcd"
    "virtio_pci"
    "virtio_scsi"
    "sd_mod"
    "sr_mod"
  ];
  boot.initrd.kernelModules = if pkgs.system == "aarch64-linux" then [ "virtio_gpu" ] else [ ];
  boot.kernelModules = if pkgs.system == "aarch64-linux" then [ ] else [ "kvm-intel" ];
  boot.kernelParams = if pkgs.system == "aarch64-linux" then [ "console=tty" ] else [ ];
  boot.extraModulePackages = [ ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  networking.usePredictableInterfaceNames = false;
}
