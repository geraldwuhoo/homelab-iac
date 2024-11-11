{ lib, config, ... }:
{
  networking.hostId = "e1346eed";

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

      (dnstls) {
        tls {
          dns cloudflare ${config.sops.placeholder.cf-api-token}
          resolvers 1.1.1.1
        }
      }

      (reverseproxy) {
        reverse_proxy {
          to 10.40.0.91:443
          transport http {
            tls
            tls_insecure_skip_verify
          }
        }
      }

      ${lib.concatMapStringsSep "\n"
        (item: ''
          ${item}, *.${item} {
            import dnstls
            import reverseproxy
          }
        '')
        [
          "wuhoo.xyz"
          "geraldwu.com"
          "nekomimi.org"
        ]
      }
    '';
  };

  caddy.caddyfilePath = config.sops.templates.Caddyfile.path;
}
