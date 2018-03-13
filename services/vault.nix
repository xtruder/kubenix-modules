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
        type = mkOptionType {
          name = "deepAttrs";
          description = "deep attribute set";
          check = isAttrs;
          merge = loc: foldl' (res: def: recursiveUpdate res def.value) {};
        };
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
    };

    config = {
      configuration = mkIf (!config.dev.enable) (if (config.tlsSecret != null) then {
        listener = [{
          tcp = {
            address = "0.0.0.0:8200";
            tls_cert_file = "/var/lib/vault/ssl/tls.crt";
            tls_key_file = "/var/lib/vault/ssl/tls.key";
          };
        } {
          tcp = {
            address = "0.0.0.0:8400";
            tls_disable = true;
          };
        }];
      } else {
        listener = [{
          tcp = {
            address = "0.0.0.0:8200";
            tls_disable = true;
          };
        }];
      });

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
                  VAULT_ADDR.value =
                    if (config.tlsSecret != null)
                    then "https://127.0.0.1:8200/"
                    else "http://127.0.0.1:8200";
                };
                resources = {
                  requests.memory = "50Mi";
                  requests.cpu = "50m";
                  limits.memory = "128Mi";
                  limits.cpu = "500m";
                };
                ports = [{
                  containerPort = 8200;
                  name = "vault";
                } {
                  containerPort = 8400;
                  name = "vault-unsecure";
                } {
                  containerPort = 8201;
                  name = "cluster";
                }];
                readinessProbe = {
                  httpGet = {
                    path = "/v1/sys/leader";
                    port = if (config.tlsSecret != null) then 8400 else 8200;
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
            name = "vault";
            port = 8200;
            targetPort = 8200;
          } {
            name = "vault-unsecure";
            port = 8400;
            targetPort = 8400;
          }];
          selector.app = name;
        };
      };

      kubernetes.resources.serviceAccounts.vault = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
      };
    };
  };
}
