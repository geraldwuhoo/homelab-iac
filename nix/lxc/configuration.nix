{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/virtualisation/proxmox-lxc.nix") ];

  boot.isContainer = true;

  systemd.suppressedSystemUnits = [
    "console-getty.service"
    "getty@.service"
    "systemd-udev-trigger.service"
    "systemd-udevd.service"
    "sys-fs-fuse-connections.mount"
    "sys-kernel-debug.mount"
    "dev-mqueue.mount"
  ];
}
