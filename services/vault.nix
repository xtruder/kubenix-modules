{ config, lib, k8s, ... }:

with lib;
with k8s;

{
  kubernetes.moduleDefinitions.vault.module = { name, module, config, ... }: {
    options = {
      image = mkOption {
        description = "Vault image to use";
        type = types.str;
        default = "vault";
      };

      configuration = mkOption {
        description = "Vault configuration file content";
        type = types.attrs;
        default = {};
      };

      replicas = mkOption {
        description = "Number of vault replicas to deploy";
        default = 1;
        type = types.int;
      };

      dev = {
        enable = mkOption {
          description = "Whether to enable development mode";
          type = types.bool;
          default = false;
        };

        token = mkSecretOption {
          description = "Development root token id";
          default = null;
        };
      };

      tlsSecret = mkOption {
        description = "Name of the secret where to read tls certs";
        type = types.nullOr types.str;
        default = null;
      };

      healthPort = mkOption {
        description = "Healtcheck port";
        type = types.int;
        default = 8200;
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
                args = ["server"] ++ optionals config.dev.enable ["-dev"];
                securityContext = {
                  privileged = false;
                  capabilities.add = ["IPC_LOCK"];
                };
                env = {
                  VAULT_LOCAL_CONFIG.value = builtins.toJSON config.configuration;
                  VAULT_CLUSTER_INTERFACE.value = "eth0";
                  VAULT_REDIRECT_INTERFACE.value = "eth0";
                  VAULT_DEV_ROOT_TOKEN_ID = mkIf (config.dev.token != null) (secretToEnv config.dev.token);
                  VAULT_CAPATH.value = "/var/lib/vault/ssl/ca.crt";
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
                    port = config.healthPort;
                  };
                  initialDelaySeconds = 30;
                  timeoutSeconds = 30;
                };
                volumeMounts.storage = mkIf (config.tlsSecret != null) {
                  name = "cert";
                  mountPath = "/var/lib/vault/ssl/";
                };
              };
              volumes.cert = mkIf (config.tlsSecret != null) {
                secret.secretName = config.tlsSecret;
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

      kubernetes.resources.serviceAccounts.vault = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
      };

      kubernetes.resources.clusterRoleBindings.vault-tokenreview-binding = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = "${module.namespace}-${module.name}-tokenreview-binding";
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "system:auth-delegator";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = module.name;
          namespace = module.namespace;
        }];
      };
    };
  };
}
