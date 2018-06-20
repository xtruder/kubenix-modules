{ config, k8s, ... }:

{
  require = [
    ./test.nix
    ../modules/vault-login.nix
    ../modules/vault.nix
    ../modules/nginx.nix
    ../modules/deployer.nix
  ];

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

  kubernetes.resources.secrets.vault-token.data = {
    token = k8s.toBase64 "e2bf6c5e-88cc-2046-755d-7ba0bdafef35";
  };

  kubernetes.resources.secrets.vault-sa = {
    nix.dependencies = ["serviceAccounts/vault-sa"];

    metadata.annotations."kubernetes.io/service-account.name" = "vault-sa";
    type = "kubernetes.io/service-account-token";
  };

  kubernetes.resources.serviceAccounts.vault-sa = {
    secrets = [{ name = "vault-sa"; }];
  };

  kubernetes.modules.nginx = {
    configuration.kubernetes.modules.token1 = {
      module = "vault-login-sidecar";
      configuration = {
        resourcePath = ["deployments" "nginx" "spec" "template" "spec"];
        serviceAccountName = "nginx";
        mountContainer = "nginx";
        mountPath = "/token1";
        vault.address = "http://vault:8200";
        vault.role = "vault-login";
        tokenRenewPeriod = 60;
      };
    };

    configuration.kubernetes.modules.token2 = {
      module = "vault-login-sidecar";
      configuration = {
        resourcePath = ["deployments" "nginx" "spec" "template" "spec"];
        serviceAccountName = "nginx";
        mountContainer = "nginx";
        mountPath = "/token2";
        vault.address = "http://vault:8200";
        vault.role = "vault-login";
        tokenRenewPeriod = 60;
      };
    };

    configuration.kubernetes.modules.token3 = {
      module = "vault-login-sidecar";
      configuration = {
        resourcePath = ["deployments" "nginx" "spec" "template" "spec"];
        serviceAccountName = "vault-sa";
        mountContainer = "nginx";
        mountPath = "/token3";
        vault.address = "http://vault:8200";
        vault.role = "vault-login";
        kubernetes.token = {
          name = "vault-sa";
          key = "token";
        };
        tokenRenewPeriod = 60;
      };
    };
  };

  kubernetes.modules.vault-deployer = {
    module = "deployer";

    configuration.vars.vault_token = k8s.secretToEnv {
      name = "vault-token";
      key = "token";
    };

    configuration.configuration = {
      variable.vault_token = {};

      provider.vault = {
        address = "http://vault:8200";
        token = ''''${var.vault_token}'';
      };

      resource.vault_auth_backend.kubernetes = {
        type = "kubernetes";
      };

      resource.vault_generic_secret.auth_kubernetes_config = {
        path = "auth/kubernetes/config";
        data_json = ''{
          "kubernetes_host": "https://kubernetes:443",
          "kubernetes_ca_cert": "''${replace(file("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"), "\n", "\\n")}"
        }'';
        depends_on = ["vault_auth_backend.kubernetes"];
      };

      resource.vault_generic_secret.auth_kubernetes_role_vault_login = {
        path = "auth/kubernetes/role/vault-login";
        data_json = builtins.toJSON {
          bound_service_account_names = ["nginx" "vault-sa"];
          bound_service_account_namespaces = "default";
          policies = ["default"];
          period = "1h";
        };
        depends_on = ["vault_generic_secret.auth_kubernetes_config"];
      };
    };
  };
}
