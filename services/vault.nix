{ config, lib, ... }:

with lib;

{
  kubernetes.moduleDefinitions.vault.module = { name, config, ... }: {
    options = {
      image = mkOption {
        description = "Vault image to use";
        type = types.str;
        default = "vault";
      };

      configuration = mkOption {
        description = "Vault configuration file content";
        type = types.attrs;
      };

      replicas = mkOption {
        description = "Number of vault replicas to deploy";
        default = 2;
        type = types.int;
      };
    };

    config = {
      kubernetes.resources.deployments.vault = {
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
                args = ["server"];
                securityContext = {
                  privileged = false;
                  capabilities.add = ["IPC_LOCK"];
                };
                env = {
                  VAULT_LOCAL_CONFIG.value = builtins.toJSON config.configuration;
                  VAULT_CLUSTER_INTERFACE.value = "eth0";
                  VAULT_REDIRECT_INTERFACE.value = "eth0";
                };
                resources = {
                  requests.memory = "50Mi";
                  requests.cpu = "50m";
                  limits.memory = "128Mi";
                  limits.cpu = "500m";
                };
                ports = [{
                  containerPort = 8200;
                  name = "http";
                } {
                  containerPort = 8201;
                  name = "cluster";
                }];
                readinessProbe = {
                  httpGet = {
                    path = "/v1/sys/leader";
                    port = 8200;
                  };
                  initialDelaySeconds = 30;
                  timeoutSeconds = 30;
                };
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
            port = 8200;
            targetPort = 8200;
          }];
          selector.app = name;
        };
      };
    };
  };
}
