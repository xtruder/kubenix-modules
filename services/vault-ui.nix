{ config, lib, k8s, ... }:

with lib;
with k8s;

{
  kubernetes.moduleDefinitions.vault-ui.module = { name, config, ... }: {
    options = {
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
      kubernetes.resources.deployments.vault-ui = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          replicas = config.replicas;
          selector.matchLabels.app = name;
          template = {
            metadata.name = name;
            metadata.labels.app = name;
            spec = {
              containers.vault = {
                image = config.image;
                env = {
                  VAULT_URL_DEFAULT.value = config.vault.defaultUrl;
                  VAULT_AUTH_DEFAULT.value = config.vault.defaultAuth;
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

      kubernetes.resources.services.vault = {
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
  };
}
