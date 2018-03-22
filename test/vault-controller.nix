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
      namespace = "default";
      vault.address = "http://vault:8200";
      vault.token.name = "vault-token";
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
