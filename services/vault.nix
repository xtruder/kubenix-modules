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

      tls = {
        secret = mkOption {
          description = "Name of the secret where to read tls certs";
          type = types.nullOr types.str;
          default = null;
        };

        additionalDomains = mkOption {
          description = "Additional ssl domains for incluster ssl";
          type = types.listOf types.str;
          default = [];
        };
      };

      configReloadPeriod = mkOption {
        description = "Vault config reload period";
        type = types.int;
        default = 60;
      };
    };

    config = {
      kubernetes.modules.k8s-request-cert = mkIf (!config.dev.enable) {
        module = "k8s-request-cert";
        name = "${module.name}-k8s-request-cert";
        configuration = {
          kubernetes.resources.statefulSets.vault.spec.serviceName = name;
          resourcePath = ["statefulSets" "vault" "spec" "template" "spec"];
          serviceAccountName = module.name;
          mountContainer = "vault";
          addresses = ["127.0.0.1" "vault" "vault.${module.namespace}"] ++ config.tls.additionalDomains;
        };
      };

      configuration = mkIf (!config.dev.enable) {
        listener = [{
          tcp = {
            address = "0.0.0.0:8400";
            tls_disable = true;
          };
        } {
          tcp = {
            address = "0.0.0.0:8300";
            tls_cert_file = "/cert/node.crt";
            tls_key_file = "/cert/node.key";
          };
        }] ++ (optionals (config.tls.secret != null) [{
          tcp = {
            address = "0.0.0.0:8200";
            tls_cert_file = "/var/lib/vault/ssl/tls.crt";
            tls_key_file = "/var/lib/vault/ssl/tls.key";
          };
        }]);
      };

      kubernetes.resources.statefulSets.vault = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          serviceName = name;
          replicas = config.replicas;
          selector.matchLabels.app = name;
          template = {
            metadata.name = name;
            metadata.labels.app = name;
            spec = {
              serviceAccountName = name;
              containers.vault = {
                image = config.image;
                args = ["server"] ++ optionals config.dev.enable ["-dev"];
                securityContext.capabilities.add = ["IPC_LOCK"];
                env = {
                  VAULT_LOCAL_CONFIG.value = builtins.toJSON config.configuration;
                  VAULT_CLUSTER_INTERFACE.value = "eth0";
                  VAULT_REDIRECT_INTERFACE.value = "eth0";
                  VAULT_DEV_ROOT_TOKEN_ID = mkIf (config.dev.token != null) (secretToEnv config.dev.token);
                  VAULT_CAPATH = mkIf (!config.dev.enable) {
                    value = "/cert/ca.crt";
                  };
                  VAULT_ADDR.value =
                    if (!config.dev.enable)
                    then "https://127.0.0.1:8300/"
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
                  name = "vault-ssl";
                } {
                  containerPort = 8300;
                  name = "vault-incluster";
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
                    port = if config.dev.enable then 8200 else 8400;
                  };
                  initialDelaySeconds = 30;
                  timeoutSeconds = 30;
                };
                livenessProbe = mkIf (config.tls.secret != null) {
                  exec.command = ["kill" "-SIGHUP" "1"];
                  initialDelaySeconds = config.configReloadPeriod;
                  periodSeconds = config.configReloadPeriod;
                };
                volumeMounts.cert = mkIf (config.tls.secret != null) {
                  name = "cert";
                  mountPath = "/var/lib/vault/ssl/";
                };
              };
              volumes.cert = mkIf (config.tls.secret != null) {
                secret.secretName = config.tls.secret;
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
            name = "vault-ssl";
            port = 8200;
            targetPort = 8200;
          } {
            name = "vault-incluster";
            port = 8300;
            targetPort = 8300;
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
