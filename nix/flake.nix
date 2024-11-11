{
  description = "NixOS server configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko/v1.9.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs-stable.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-generators,
      disko,
      sops-nix,
      ...
    }:
    {
      nixosConfigurations =
        let
          keys = [
            "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDfl1dB7NdK3ShSTbdkOFfxD5c6jKsEDJiwU6HlfPA1XtfFbauzOlUtpLRMG22wnFai7Xd0ejpt2f5eh2w5g9P4QCZawInMC4kgK5qN/hIB+LHIe+go89pI1s27Zy+aOCciWSfv9O0HeCWtB0mUxnGRjBLtBQaIwENzi2MiPw0ce5QuLrP1Zm60TXdKpbHeThni5SNp4mAVfFWgGqxDI5xzLo61Ad6D97hR+dz0hR8DVUhDSfath9zovglxoyIn5m7oNlApzg3OmFeIdLThwZwXeagXHFJqoub0TsnUNT4v1fOYhwMk0XXE/3faj8Gex2Xs4s/PtWyULfV4oaajgUtG8MmDJR+OdhAI3Mu1Yds7e22FB22zeMdq1UWRLutMbkM+XgXvRdsd1+tq9lOm2YVGydKFL2Wh4nmR6cz4+/aSN23xqBYDGMR3IjYje4oVk57XyWpjeWXpDU68vZ90lToVJB0q2SUufpjPW4vg64Im2pw59D6p+E2xbQe/TMgSe6MjoEMKNTnqJ5/08atF7tprZZ2KPIPtU9/tbi5Gkocnjls2Mp0E28PxZ5h7ghDa2zKkRxTRg/0YOUJ9JKFxaDt2WeLnodeKcuYVHl02Qa9kstNJX7DpysH9zKROUgk1Lju8IpUjt6RX6B05YbRH1UxV+rP+l2dCEyhdu0KFHopQ0w== jerry@Arch-Desktop"
          ];
          system = "x86_64-linux";
        in
        # NixOS LXCs
        builtins.mapAttrs
          (
            name: host:
            nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [
                {
                  networking.hostName = name;
                  common.keys = keys;
                  oci.enable = true;
                  watchtower.hostname = name;
                }
                sops-nix.nixosModules.sops
                ./common
                ./lxc
                ./hosts/${name}
              ];
            }
          )
          {
            shinobu = { };
            araragi = { };
          }
        # NixOS k3s VMs
        //
          builtins.mapAttrs
            (
              name: host:
              nixpkgs.lib.nixosSystem {
                system = host.arch or system;
                modules = [
                  {
                    networking.hostName = name;
                    common.keys = keys;
                  }
                  sops-nix.nixosModules.sops
                  disko.nixosModules.disko
                  ./common
                  ./vm
                  ./k3s
                  ./hosts/${name}
                ];
              }
            )
            {
              k3s-master-0 = { };
              k3s-master-1 = { };
              k3s-master-2 = { };
              k3s-worker-0 = { };
              k3s-worker-1 = { };
              k3s-worker-2 = { };
              k3s-worker-3 = { };
              hetzner = {
                arch = "aarch64-linux";
              };
            }
        # NixOS install media
        // {
          lxc = nixos-generators.nixosGenerate {
            inherit system;
            modules = [
              { common.keys = keys; }
              sops-nix.nixosModules.sops
              ./common
              ./lxc
            ];
            format = "proxmox-lxc";
          };

          iso = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              ({
                users.users = {
                  nixos.openssh.authorizedKeys.keys = keys;
                  root.openssh.authorizedKeys.keys = keys;
                };
                services.qemuGuest.enable = true;
              })
            ];
          };
        };
    };
}
