{ config, k8s, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.goldfish.configuration = {
    replicas = 2;
    tls.disable = true;
    tls.autoredirect = false;
    certificate.pki = {
      altNames = ["goldfish" "goldfish.example.com"];
      commonName = "goldfish.example.com";
    };
    vault.address = "http://vault:8200";
    vault.runtimeConfig = "goldfish/goldfish";
  };

  kubernetes.modules.vault.configuration.dev = {
    enable = true;
    token = {
      name = "vault-token";
      key = "token";
    };
  };

  kubernetes.resources.secrets.vault-token.data = {
    token = k8s.toBase64 "e2bf6c5e-88cc-2046-755d-7ba0bdafef35";
  };

  kubernetes.modules.vault-deployer = {
    module = "deployer";

    configuration.vars.vault_token = k8s.secretToEnv config.kubernetes.modules.vault.configuration.dev.token;

    configuration.configuration = {
      variable.vault_token = {};

      provider.vault = {
        address = "http://vault:8200";
        token = ''''${var.vault_token}'';
      };

      resource.vault_mount.pki = {
        type = "pki";
        path = "pki";
      };

      resource.vault_mount.goldfish = {
        path = "goldfish";
        type = "generic";
      };

      resource.vault_auth_backend.approle.type = "approle";

      # generate root ca
      resource.vault_generic_secret.ca = {
        path = "pki/root/generate/internal";
        disable_read = true;
        data_json = builtins.toJSON {
          key_type = "ec";
          key_bits = 256;
          ttl = "87600h"; # 10 years
        };
        depends_on = ["vault_mount.pki"];
      };

      resource.vault_generic_secret.pki-roles-goldfish = {
        path = "pki/roles/goldfish";
        data_json = builtins.toJSON {
          allow_any_name = true;
          allowed_domains = ["goldfish" "goldfish.example.com"];
        };
        depends_on = ["vault_generic_secret.ca"];
      };

      resource.vault_policy.goldfish = {
        name = "goldfish";
        policy = ''
          # [mandatory]
          # store goldfish run-time settings here
          # goldfish hot-reloads from this endpoint every minute
          path "goldfish/goldfish" {
            capabilities = ["read", "update"]
          }

          # [optional]
          # to enable transit encryption, see wiki for details
          path "transit/encrypt/goldfish" {
            capabilities = ["read", "update"]
          }
          path "transit/decrypt/goldfish" {
            capabilities = ["read", "update"]
          }

          # [optional]
          # for goldfish to fetch certificates from PKI backend
          path "pki/issue/goldfish" {
            capabilities = ["update"]
          }
        '';
      };

      resource.vault_approle_auth_backend_role.goldfish = {
        backend = "approle";

        role_name = "goldfish";
        role_id = "goldfish";
        policies = ["default" "goldfish"];
        secret_id_num_uses = 1;
        secret_id_ttl = 300;
        period = 86400;
        token_ttl = 0;
        token_max_ttl = 0;
      };

      resource.vault_generic_secret.goldfish = {
        path = "goldfish/goldfish";
        disable_read = true;
        data_json = builtins.toJSON {
          DefaultSecretPath = "goldfish/";
          UserTransitKey = "usertransit";
          BulletinPath = "goldfish/bulletins/";
        };
        depends_on = ["vault_mount.goldfish"];
      };
    };
  };
}
