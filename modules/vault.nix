{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

{
  imports = [
    kubenix.k8s
  ];

  options.args = {
    image = mkOption {
      description = "Vault image to use";
      type = types.str;
      default = "vault:0.11.0";
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
    submodule = {
      name = "vault";
      version = "1.0.0";
      description = "";
    };
    kubernetes.modules.k8s-request-cert = mkIf (!config.args.dev.enable) {
      module = "k8s-request-cert";
      name = "${name}-k8s-request-cert";
      namespace = module.namespace;
      configuration = {
        kubernetes.api.statefulsets.vault.spec.servicename = name;
        resourcePath = ["statefulSets" "vault" "spec" "template" "spec"];
        serviceAccountName = name;
        mountContainer = "vault";
        addresses = ["127.0.0.1" "vault" "vault.${module.namespace}"]
          ++ (map (i: "vault-${toString i}") (range 0 (config.args.replicas - 1))) 
          ++ (map (i: "vault-${toString i}.${module.namespace}") (range 0 (config.args.replicas - 1))) 
          ++ config.args.tls.additionalDomains;
      };
    };

    configuration = mkIf (!config.args.dev.enable) {
      ui = config.args.ui.enable;
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
      }] ++ (optionals (config.args.tls.secret != null) [{
        tcp = {
          address = "0.0.0.0:8200";
          tls_cert_file = "/var/lib/vault/ssl/tls.crt";
          tls_key_file = "/var/lib/vault/ssl/tls.key";
        };
      }]);
    };

    kubernetes.api.statefulsets.vault = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        podManagementPolicy = "Parallel";
        serviceName = name;
        replicas = config.args.replicas;
        selector.matchLabels.app = name;
        template = {
          metadata.name = name;
          metadata.labels.app = name;
          spec = {
            serviceAccountName = name;
            containers.vault = {
              image = config.args.image;
              args = ["server"] ++ optionals config.args.dev.enable ["-dev"];
              securityContext.capabilities.add = ["IPC_LOCK"];
              env = {
                VAULT_LOCAL_CONFIG.value = builtins.toJSON config.args.configuration;
                VAULT_CLUSTER_INTERFACE.value = "eth0";
                VAULT_REDIRECT_INTERFACE.value = "eth0";
                VAULT_DEV_ROOT_TOKEN_ID = mkIf config.args.dev.enable (secretToEnv config.args.dev.token);
                VAULT_CAPATH = mkIf (!config.args.dev.enable) {
                  value = "/cert/ca.crt";
                };
                VAULT_ADDR.value =
                  if (!config.args.dev.enable)
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
                  port = if config.args.dev.enable then 8200 else 8400;
                };
                initialDelaySeconds = 30;
                timeoutSeconds = 30;
              };
              livenessProbe = mkIf (config.args.tls.secret != null) {
                exec.command = ["kill" "-SIGHUP" "1"];
                initialDelaySeconds = config.args.configReloadPeriod;
                periodSeconds = config.args.configReloadPeriod;
              };
              volumeMounts.cert = mkIf (config.args.tls.secret != null) {
                name = "cert";
                mountPath = "/var/lib/vault/ssl/";
              };
            };
            volumes.cert = mkIf (config.args.tls.secret != null) {
              secret.secretName = config.args.tls.secret;
            };
          };
        };
      };
    };

    kubernetes.api.poddisruptionbudgets.vault = {
      metadata.name = name;
      metadata.labels.app = name;
      spec.maxUnavailable = 1;
      spec.selector.matchLabels.app = name;
    };

    kubernetes.api.services = mkMerge ([{
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

    kubernetes.api.serviceaccounts.vault = {
      metadata.name = name;
      metadata.labels.app = name;
    };
  };
}