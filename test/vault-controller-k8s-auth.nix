{ config, k8s, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.vault = {
    module = "vault";
    configuration.dev = {
      enable = true;
      token = {
        name = "vault-token";
        key = "token";
      };
    };
  };

  kubernetes.modules.vault-controller = {
    module = "vault-controller";
    configuration = {
      vault.address = "http://vault:8200";
      vault.saauth = true;
    };
  };

  kubernetes.resources.secrets.vault-token.data = {
    token = k8s.toBase64 "e2bf6c5e-88cc-2046-755d-7ba0bdafef35";
  };

  kubernetes.modules.vault-secrets = {
    module = "deployer";

    configuration.vars.vault_token = k8s.secretToEnv config.kubernetes.modules.vault.configuration.dev.token;

    configuration.configuration = {
      variable.vault_token = {};

      provider.vault = {
        address = "http://vault:8200";
        token = ''''${var.vault_token}'';
      };

      resource.vault_auth_backend.kubernetes = {
        type = "kubernetes";
      };

      resource.vault_policy.vault-controller = {
        name = "vault-controller";
        policy = ''
          path "tokens/*" {
            capabilities = ["read", "list"]
          }
        '';
      };

      resource.vault_generic_secret.auth_kubernetes_config = {
        path = "auth/kubernetes/config";
        data_json = ''{
          "kubernetes_host": "https://kubernetes:443",
          "kubernetes_ca_cert": "''${replace(file("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"), "\n", "\\n")}"
        }'';
        depends_on = ["vault_auth_backend.kubernetes"];
      };

      resource.vault_generic_secret.auth_kubernetes_role_vault_controller = {
        path = "auth/kubernetes/role/vault-controller";
        data_json = builtins.toJSON {
          bound_service_account_names = "vault-controller";
          bound_service_account_namespaces = "default";
          policies = ["default" "vault-controller"];
          ttl = "1h";
        };
        depends_on = ["vault_generic_secret.auth_kubernetes_config"];
      };

      resource.vault_mount.tokens = {
        path = "tokens";
        type = "generic";
        description = "Generic secrets";
      };

      resource.vault_generic_secret.test = {
        path = "tokens/test";
        data_json = builtins.toJSON {
          key = "value";
          key2 = "value2";
        };
        depends_on = ["vault_mount.tokens"];
      };
    };
  };

  kubernetes.modules.test-secret-claim = {
    module = "secret-claim";
    configuration.path = "tokens/test";
  };
}
