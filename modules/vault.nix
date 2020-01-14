{ config, lib, k8s, ... }:

with lib;
with k8s;

{
  imports = [./k8s-request-cert.nix];

  kubernetes.moduleDefinitions.vault.module = { name, module, config, ... }: {
    options = {
      image = mkOption {
        description = "Vault image to use";
        type = types.str;
        default = "vault:1.0.3";
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
          default = {
            name = "vault-token";
            key = "token";
          };
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

      ui.enable = mkOption {
        description = "Whether to enable vault ui";
        type = types.bool;
        default = true;
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
        namespace = module.namespace;
        configuration = {
          kubernetes.resources.statefulSets.vault.spec.serviceName = name;
          kubernetes.resources.statefulSets.vault.spec.selector.matchLabels.app = name;
          resourcePath = ["statefulSets" "vault" "spec" "template" "spec"];
          serviceAccountName = module.name;
          mountContainer = "vault";
          addresses = ["127.0.0.1" "vault" "vault.${module.namespace}"]
            ++ (map (i: "vault-${toString i}") (range 0 (config.replicas - 1))) 
            ++ (map (i: "vault-${toString i}.${module.namespace}") (range 0 (config.replicas - 1))) 
            ++ config.tls.additionalDomains;
        };
      };

      configuration = mkIf (!config.dev.enable) {
        ui = config.ui.enable;
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
          selector.matchLabels.app = name;
          podManagementPolicy = "Parallel";
          serviceName = name;
          replicas = config.replicas;
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
                  VAULT_DEV_ROOT_TOKEN_ID = mkIf config.dev.enable (secretToEnv config.dev.token);
                  VAULT_CAPATH = mkIf (!config.dev.enable) {
                    value = "/cert/ca.crt";
                  };
                  VAULT_ADDR.value =
                    if (!config.dev.enable)
                    then "https://127.0.0.1:8300/"
                    else "http://127.0.0.1:8200";
                };
                resources = {
                  requests.memory = "256Mi";
                  requests.cpu = "100m";
                  limits.memory = "256Mi";
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

      kubernetes.resources.podDisruptionBudgets.vault = {
        metadata.name = name;
        metadata.labels.app = name;
        spec.maxUnavailable = 1;
        spec.selector.matchLabels.app = name;
      };

      kubernetes.resources.services = mkMerge ([{
        vault = {
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
      }] ++ map (i: {
        "vault-${toString i}" = {
          metadata.name = "${name}-${toString i}";
          metadata.labels.app = name;
          metadata.annotations.
            "service.alpha.kubernetes.io/tolerate-unready-endpoints" = "true";
          spec = {
            publishNotReadyAddresses = true;
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
            selector = {
              app = name;
              "statefulset.kubernetes.io/pod-name" = "${name}-${toString i}";
            };
          };
        };
      }) (range 0 (config.replicas - 1)));

      kubernetes.resources.serviceAccounts.vault = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
      };
    };
  };
}
