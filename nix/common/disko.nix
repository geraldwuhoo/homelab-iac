{ lib, ... }:
{
  disko.devices = {
    disk = {
      main = {
        # When using disko-install, we will overwrite this value from the commandline
        device = "/dev/sda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            MBR = {
              type = "EF02"; # for grub MBR
              size = "1M";
              priority = 1; # Needs to be first partition
            };
            ESP = {
              type = "EF00";
              size = "500M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zroot";
              };
            };
          };
        };
      };
    };

    zpool = {
      zroot = {
        type = "zpool";
        options.ashift = "12";
        rootFsOptions = {
          acltype = "posixacl";
          relatime = "on";
          xattr = "sa";
          dnodesize = "auto";
          canmount = "off";
          mountpoint = "none";
          compression = "zstd";
          "com.sun:auto-snapshot" = "false";
        };
        postCreateHook = ''
          zfs list -t snapshot -H -o name | grep -E '^zroot/ROOT/default@blank$' || zfs snapshot zroot/ROOT/default@blank
        '';
        datasets = {
          # Root mount
          "ROOT" = {
            type = "zfs_fs";
            options.mountpoint = "none";
          };
          "ROOT/default" = {
            type = "zfs_fs";
            mountpoint = "/";
            options.mountpoint = "legacy";
          };

          # Misc persistence
          "persist" = {
            type = "zfs_fs";
            mountpoint = "/persist";
          };
          "persist/nix" = {
            type = "zfs_fs";
            mountpoint = "/nix";
          };

          # /var/lib/rancher for k3s
          "persist/var" = {
            type = "zfs_fs";
            mountpoint = "/var";
            options.canmount = "off";
          };
          "persist/var/lib" = {
            type = "zfs_fs";
            mountpoint = "/var/lib";
            options.canmount = "off";
          };
          "persist/var/lib/rancher" = {
            type = "zfs_fs";
          };

          # /etc/rancher for k3s
          "persist/etc" = {
            type = "zfs_fs";
            mountpoint = "/etc";
            options.canmount = "off";
          };
          "persist/etc/rancher" = {
            type = "zfs_fs";
          };
        };
      };
    };
  };

  # Roll back to empty snapshot on every boot
  # Inspired by https://grahamc.com/blog/erase-your-darlings/
  # Lots of config taken from https://git.elia.garden/leela/dotfiles
  boot.initrd.postDeviceCommands = lib.mkAfter ''
    echo "rolling back root to empty snapshot"
    zfs rollback -r zroot/ROOT/default@blank
  '';

  fileSystems = {
    "/".neededForBoot = true;
    "/nix".neededForBoot = true;
    "/persist".neededForBoot = true; # needed for sops-nix key early
  };

  boot.kernelParams = [
    "zfs.zfs_arc_min=268435456"
    "zfs.zfs_arc_max=1073741824"
    "kernel.unprivileged_userns_clone=1"
  ];

  services.zfs.trim.enable = true;
}
