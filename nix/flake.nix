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
                  networking.hostId = host.hostId;
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
            shinobu = {
              hostId = "335388f6";
            };
            araragi = {
              hostId = "e1346eed";
            };
          }
        # NixOS k3s VMs
        //
          builtins.mapAttrs
            (
              name: host:
              nixpkgs.lib.nixosSystem {
                inherit system;
                modules = [
                  {
                    networking.hostName = name;
                    networking.hostId = host.hostId;
                    common.keys = keys;
                    k3s.master = host.master;
                  }
                  sops-nix.nixosModules.sops
                  disko.nixosModules.disko
                  ./common
                  ./vm
                  ./k3s
                ];
              }
            )
            {
              k3s-master-0 = {
                hostId = "c4442a6f";
                master = true;
              };
              k3s-master-1 = {
                hostId = "eb7164eb";
                master = true;
              };
              k3s-master-2 = {
                hostId = "584c5421";
                master = true;
              };
              k3s-worker-0 = {
                hostId = "34b8009a";
                master = false;
              };
              k3s-worker-1 = {
                hostId = "df8fe0da";
                master = false;
              };
              k3s-worker-2 = {
                hostId = "b16785a4";
                master = false;
              };
              k3s-worker-3 = {
                hostId = "12060450";
                master = false;
              };
            }
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

          hetzner = nixpkgs.lib.nixosSystem {
            system = "aarch64-linux";
            modules = [
              {
                networking.hostName = "hetzner";
                networking.hostId = "41f85022";
                common.keys = keys;
                vm.efi = true;
                k3s.master = true;
                k3s.singleNode = true;
              }
              sops-nix.nixosModules.sops
              disko.nixosModules.disko
              ./common
              ./vm
              ./k3s
            ];
          };
        };
    };
}
