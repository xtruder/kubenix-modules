{ config, lib, k8s, pkgs, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.prometheus.module = {config, module, ...}: let
    prometheusConfig = {
      global = {
        external_labels = config.externalLabels;
        scrape_interval = "1m";
        evaluation_interval = "1m";
      };

      rule_files = ["/etc/config/*.rules" "/etc/config/*.alerts"];

      scrape_configs = [

        # Scrape config for prometheus itself
        {
          job_name = "prometheus";
          static_configs = [{
            targets = ["localhost:9090"];
          }];
        }
      ] ++ config.extraScrapeConfigs;

      alerting = optionalAttrs (config.alertmanager.enable) {
        alertmanagers = [{
            static_configs = [{
              targets = [config.alertmanager.host];
            }];
        }];
      };
    };

    validateRulesAndAlerts = files: mapAttrs (n: f: let
      file = if isString f then (builtins.toFile "${n}" f) else f;
    in builtins.readFile (pkgs.runCommand "prometheus-check-${n}" {
      buildInputs = [pkgs.prometheus];
    } ''
      cp ${file} ${n}
      promtool check rules ${n}
      cp ${file} $out
    '')) files;
  in {
    options = {
      image = mkOption {
        description = "Docker image to use for prometheus";
        type = types.str;
        default = "prom/prometheus:v2.2.1";
      };

      replicas = mkOption {
        description = "Number of prometheus replicas to run";
        type = types.int;
        default = 2;
      };

      alertmanager = {
        enable = mkOption {
          description = "Whether to enable prometheus alertmanager";
          default = false;
          type = types.bool;
        };

        host = mkOption {
          description = "Alertmanager host";
          default = "${module.name}-alertmanager:9093";
          type = types.str;
        };
      };

      externalLabels = mkOption {
        description = "Attribute set of global labels";
        type = types.attrs;
        default = {};
      };

      rules = mkOption {
        description = "Attribute set of prometheus recording rules to deploy";
        type = types.attrsOf (types.either types.path types.str);
        default = {};
      };

      alerts = mkOption {
        description = "Attribute set of alert rules to deploy";
        type = types.attrsOf (types.either types.path types.str);
        default = {};
      };

      tsdb = {
        retention = mkOption {
          description = "TSDB retention time";
          default = "30d";
          type = types.str;
        };
      };

      storage = {
        size = mkOption {
          description = "Prometheus storage size";
          default = "20Gi";
          type = types.str;
        };

        class = mkOption {
          description = "prometheus storage class";
          type = types.nullOr types.str;
          default = null;
        };
      };

      extraArgs = mkOption {
        description = "Prometheus server additional options";
        default = [];
        type = types.listOf types.str;
      };

      extraConfig = mkOption {
        description = "Prometheus extra config";
        type = types.attrs;
        default = {};
      };

      extraScrapeConfigs = mkOption {
        description = "Prometheus extra scrape configs";
        type = types.listOf types.attrs;
        default = [];
      };
    };

    config = {
      kubernetes.resources.statefulSets.prometheus = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          serviceName = module.name;
          replicas = config.replicas;
          selector.matchLabels.app = module.name;
          podManagementPolicy = "Parallel";
          template = {
            metadata.name = module.name;
            metadata.labels.app = module.name;
            spec = {
              serviceAccountName = module.name;
              volumes.config.configMap.name = module.name;

              containers.server-reload = {
                image = "jimmidyson/configmap-reload:v0.2.2";
                args = [
                  "--volume-dir=/etc/config"
                  "--webhook-url=http://localhost:9090/-/reload"
                ];
                volumeMounts = [{
                  name = "config";
                  mountPath = "/etc/config";
                  readOnly = true;
                }];
              };

              containers.prometheus = {
                image = config.image;
                args = [
                  "--config.file=/etc/config/prometheus.json"
                  "--storage.tsdb.path=/data"
                  "--storage.tsdb.retention=${config.tsdb.retention}"
                  "--web.console.libraries=/etc/prometheus/console_libraries"
                  "--web.console.templates=/etc/prometheus/consoles"
                ] ++ config.extraArgs;
                ports = [{
                  name = "prometheus";
                  containerPort = 9090;
                }];
                resources = {
                  requests = {
                    memory = "4096Mi";
                    cpu = "500m";
                  };
                  limits = {
                    memory = "4096Mi";
                    cpu = "500m";
                  };
                };
                volumeMounts = [{
                  name = "storage";
                  mountPath = "/data";
                } {
                  name = "config";
                  mountPath = "/etc/config";
                  readOnly = true;
                }];
                readinessProbe = {
                  httpGet = {
                    path = "/status";
                    port = 9090;
                  };
                  initialDelaySeconds = 30;
                  timeoutSeconds = 30;
                };
              };

              securityContext = {
                fsGroup = 2000;
                runAsNonRoot = true;
                runAsUser = 1000;
              };
            };
          };

          volumeClaimTemplates = [{
            metadata.name = "storage";
            spec = {
              accessModes = ["ReadWriteOnce"];
              resources.requests.storage = config.storage.size;
              storageClassName = mkIf (config.storage.class != null) config.storage.class;
            };
          }];
        };
      };

      kubernetes.resources.serviceAccounts.prometheus.metadata.name = module.name;

      kubernetes.resources.podDisruptionBudgets.prometheus = {
        metadata.name = module.name;
        spec.maxUnavailable = 1;
        spec.selector.matchLabels.app = module.name;
      };

      kubernetes.resources.services.prometheus = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          ports = [{
            name = "prometheus";
            port = 9090;
            targetPort = 9090;
            protocol = "TCP";
          }];
          selector.app = module.name;
        };
      };

      kubernetes.resources.configMaps =  {
        prometheus = {
          metadata.name = module.name;
          metadata.labels.app = module.name;
          data = {
            "prometheus.json" = builtins.toJSON prometheusConfig;
          } // (mapAttrs (n: f:
            if isString f then f
            else builtins.readFile f
          ) (validateRulesAndAlerts (config.rules // config.alerts)));
        };
      };

      kubernetes.resources.clusterRoleBindings.prometheus = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = module.name;
        metadata.labels.app = module.name;
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

      kubernetes.resources.clusterRoles.prometheus = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = module.name;
        metadata.labels.app = module.name;
        rules = [{
          apiGroups = [""];
          resources = [
            "nodes"
            "nodes/metrics"
            "nodes/proxy"
            "services"
            "endpoints"
            "pods"
          ];
          verbs = ["get" "list" "watch"];
        } {
          apiGroups = [""];
          resources = [
            "configmaps"
          ];
          verbs = ["get"];
        } {
          nonResourceURLs = ["/metrics"];
          verbs = ["get"];
        }];
      };
    };
  };
}
