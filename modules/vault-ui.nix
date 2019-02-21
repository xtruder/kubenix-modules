{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

{
  imports = [
    kubenix.k8s
  ];

  options.args = {
    image = mkOption {
      description = "Vault ui image to use";
      type = types.str;
      default = "djenriquez/vault-ui:2.4.0-rc3";
    };

    replicas = mkOption {
      description = "Number of vault ui replicas to deploy";
      default = 1;
      type = types.int;
    };

    vault = {
      defaultUrl = mkOption {
        description = "Vault url";
        type = types.str;
        default = "https://vault:8300";
      };

      defaultAuth = mkOption {
        description = "Default vault auth method";
        type = types.enum ["github" "usernamepassword" "ldap" "token"];
        default = "token";
      };
    };
  };

  config = {
    submodule = {
      name = "vault-ui.nix";
      version = "1.0.0";
      description = "";
    };
    kubernetes.api.deployments.vault-ui = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        replicas = config.args.replicas;
        selector.matchLabels.app = name;
        template = {
          metadata.name = name;
          metadata.labels.app = name;
          spec = {
            containers.vault-ui = {
              image = config.args.image;
              env = {
                VAULT_URL_DEFAULT.value = config.args.vault.defaultUrl;
                VAULT_AUTH_DEFAULT.value = config.args.vault.defaultAuth;
                NODE_EXTRA_CA_CERTS.value = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt";
              };
              resources = {
                requests.memory = "50Mi";
                requests.cpu = "50m";
                limits.memory = "128Mi";
                limits.cpu = "500m";
              };
              ports = [{
                containerPort = 8000;
                name = "http";
              }];
            };
          };
        };
      };
    };

    kubernetes.api.services.vault-ui = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        ports = [{
          name = "http";
          port = 80;
          targetPort = 8000;
        }];
        selector.app = name;
      };
    };  
  };
}