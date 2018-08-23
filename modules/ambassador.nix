{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.ambassador.module = {config, module, ...}: {
    options = {
      image = mkOption {
        description = "Name of the Ambassador image to use";
        type = types.str;
        default = "quay.io/datawire/ambassador:0.38.0";
      };

      replicas = mkOption {
        description = "Number of Ambassador replicas";
        type = types.int;
        default = 1;
      };

      exposeAdmin = mkOption {
        description = "Whether to enable Ambassador Admin UI";
        type = types.bool;
        default = false;
      };

      tls = {
        enable = mkOption {
          description = "Whether to enable TLS";
          type = types.bool;
          default = false;
        };
        certsSecret = mkOption {
          description = "Name of the secrets where certs are stored";
          type = types.str;
          default = "ambassador-certs";
        };
      };
    };

    config = {
      kubernetes.resources.deployments.ambassador = {
        metadata = {
          name = module.name;
          labels.app = module.name;
        };
        spec = {
          replicas = config.replicas;
          selector.matchLabels.app = module.name;
          template = {
            metadata.labels.app = module.name;
            spec = {
              serviceAccountName = module.name;
              volumes.cert.secret.secretName = config.tls.certsSecret;

              containers = {
                ambassador = {
                  image = config.image;
                  ports = [{
                      name = "admin";
                      containerPort = 8877;
                    }{
                      name = "https";
                      containerPort = 443;
                    }];

                  env = {
                    AMBASSADOR_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
                  };

                  resources = {
                    requests = {
                      cpu = "200m";
                      memory = "200Mi";
                    };
                    limits = {
                      cpu = "1000m";
                      memory = "400Mi";
                    };
                  };

                  volumeMounts = [{
                    name = "cert";
                    mountPath = "/etc/certs";
                  }];

                  readinessProbe = {
                    httpGet = {
                      path = "/ambassador/v0/check_ready";
                      port = 8877;
                    };
                    initialDelaySeconds = 30;
                    periodSeconds = 3;
                  };

                  livenessProbe = {
                    httpGet = {
                      path = "/ambassador/v0/check_alive";
                      port = 8877;
                    };
                    initialDelaySeconds = 30;
                    periodSeconds = 3;
                  };
                };
              };

              affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution = [{
                weight = 100;
                podAffinityTerm = {
                  labelSelector.matchExpressions = [{
                    key = "app";
                    operator = "In";
                    values = [ module.name ];
                  }];
                  topologyKey = "kubernetes.io/hostname";
                };
              }];
            };
          };
        };
      };

      kubernetes.resources.serviceAccounts.ambassador = {
        metadata = {
          name = module.name;
          labels.app = module.name;
        };
      };

      kubernetes.resources.clusterRoles.ambassador = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata = {
          name = module.name;
          labels.app = module.name;
        };
        rules = [{
          apiGroups = [""];
          resources = ["services"];
          verbs = ["get" "list" "watch"];
        } {
          apiGroups = [""];
          resources = ["configmaps"];
          verbs = ["create" "update" "patch" "get" "list" "watch"];
        } {
          apiGroups = [""];
          resources = ["secrets"];
          verbs = ["get" "list" "watch"];
        }];
      };

      kubernetes.resources.clusterRoleBindings.ambassador = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata = {
          name = module.name;
          labels.app = module.name;
        };

        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = module.name;
        };

        subjects = [{
          kind = "ServiceAccount";
          name = module.name;
          namespace = module.namespace;
        }];
      };

      kubernetes.resources.services = {
        ambassador = {
          metadata = {
            name = module.name;
            labels.app = module.name;
            annotations = mkIf config.tls.enable {
              "getambassador.io/config" = ''
                apiVersion: ambassador/v0
                kind:  Module
                name:  tls
                config:
                  server:
                    enabled: True
                    secret: ${config.tls.certsSecret}
                    alpn_protocols: h2
              '';
            };
          };
          spec = {
            type = "LoadBalancer";
            ports = [{
              name = "https";
              port = 443;
              targetPort = "https";
            }];
            selector.app = module.name;
          };
        };

        ambassador-admin = mkIf config.exposeAdmin {
          metadata = {
            name = module.name + "-admin";
            labels.app = module.name + "-admin";
          };
          spec = {
            ports = [{
              name = "admin";
              port = 80;
              targetPort = "admin";
            }];
            selector.app = module.name;
          };
        };
      };

      kubernetes.resources.podDisruptionBudgets.ambassador = {
        metadata = {
          name = module.name;
          labels.app = module.name;
        };
        spec = {
          maxUnavailable = if config.replicas < 2 then config.replicas else "50%";
          selector.matchLabels.app = module.name;
        };
      };
    };
  };
}
