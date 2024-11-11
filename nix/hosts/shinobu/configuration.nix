{ lib, config, ... }:
{
  sops.secrets.cf-api-token = { };
  sops.templates.Caddyfile = {
    content = ''
      {
        email caddy@geraldwu.com
        acme_ca ${
          if config.caddy.staging then
            "https://acme-staging-v02.api.letsencrypt.org/directory"
          else
            "https://acme-v02.api.letsencrypt.org/directory"
        }
        order replace after encode
      }

      (local-net) {
        @not-allowed {
          not {
            remote_ip 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12
          }
        }
        respond @not-allowed 200 {
          body `wuhoo`
          close
        }
      }

      (dnstls) {
        tls {
          dns cloudflare ${config.sops.placeholder.cf-api-token}
          resolvers 1.1.1.1
        }
      }

      wuhoo.xyz, *.wuhoo.xyz {
        import dnstls
        @pve host pve.wuhoo.xyz
        handle @pve {
          import local-net
          reverse_proxy ${
            lib.concatMapStringsSep " " (item: "https://${item}.wuhoo.xyz:8006") [
              "bake"
              "nise"
              "neko"
              "kabuki"
            ]
          } {
            lb_policy ip_hash
            lb_try_duration 15s
            lb_try_interval 250ms
          }
        }

        ${
          lib.concatMapStringsSep "\n"
            (item: ''
              @${item} host ${item}.wuhoo.xyz
              handle @${item} {
                import local-net
                reverse_proxy http://${item}:5000 {
                  header_up Docker-Distribution-Api-Version "registry/2.0"
                }
              }
            '')
            [
              "devcache"
              "hub"
              "k8sgcr"
              "registryk8s"
              "quay"
              "gcr"
              "ghcr"
              "rgitlab"
            ]
        }

        respond 200 {
          body `wuhoo`
          close
        }
      }

      s3.wuhoo.xyz, *.s3.wuhoo.xyz {
        import dnstls
        import local-net
        reverse_proxy ${
          lib.concatMapStringsSep " " (item: "${item}.wuhoo.xyz:7480") [
            "bake"
            "nise"
            "neko"
          ]
        } {
          lb_policy round_robin
          lb_try_duration 15s
          lb_try_interval 250ms
        }
      }
    '';
  };
}
