{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.prometheus.module = {config, module, ...}: let
    prometheusConfig = {
      global = {
        external_labels = config.externalLabels;
        scrape_interval = "15s";
        evaluation_interval = "30s";
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
    configFiles = (mapAttrs' (n: v:
      let
        file = "${configMapName}.${ext}";
        configMapName = "${module.name}-${removeSuffix ext n}";
        value = (if isAttrs v then builtins.toJSON v else builtins.readFile v);
        ext = last (splitString "." n);
      in
        nameValuePair file {
          inherit configMapName value;
        }
    ) (config.rules // config.alerts));
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
          default = "prometheus-alertmanager:9093";
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
        type = types.attrs;
        default = {};
      };

      alerts = mkOption {
        description = "Attribute set of alert rules to deploy";
        type = types.attrs;
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
              volumes = (mapAttrs' (n: v: nameValuePair v.configMapName {
                configMap.name = v.configMapName;
              }) configFiles) // {
                config.configMap.name = module.name;
              };

              containers.server-reload = {
                image = "jimmidyson/configmap-reload:v0.2.2";
                args = [
                  "--volume-dir=/etc/config"
                  "--webhook-url=http://localhost:9090/-/reload"
                ];
                volumeMounts = (mapAttrsToList (n: v: {
                  name = v.configMapName;
                  mountPath = "/etc/config/${n}";
                  subPath = n;
                  readOnly = true;
                }) configFiles) ++ [{
                  name = "config";
                  mountPath = "/etc/config/prometheus.json";
                  subPath = "prometheus.json";
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
                    memory = "512Mi";
                    cpu = "500m";
                  };
                  limits = {
                    memory = "512Mi";
                    cpu = "500m";
                  };
                };
                volumeMounts = {
                  export = {
                    name = "storage";
                    mountPath = "/data";
                  };
                  config = {
                    name = "config";
                    mountPath = "/etc/config";
                  };
                };
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

      kubernetes.resources.configMaps = (mapAttrs' (n: v:
        nameValuePair v.configMapName {
          metadata.name = v.configMapName;
          metadata.labels.app = module.name;
          data."${n}" = v.value;
        }
      ) configFiles) // {
        prometheus = {
          metadata.name = module.name;
          metadata.labels.app = module.name;
          data = {
            "prometheus.json" = builtins.toJSON prometheusConfig;
          };
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

  config.kubernetes.moduleDefinitions.prometheus-pushgateway.module = {config, module, ...}: {
    options = {
      image = mkOption {
        description = "Image to use for prometheus pushgateway";
        type = types.str;
        default = "prom/pushgateway:v0.4.0";
      };

      replicas = mkOption {
        description = "Number of prometheus gateway replicas";
        type = types.int;
        default = 1;
      };
    };

    config = {
      kubernetes.resources.deployments.prometheus-pushgateway = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          replicas = config.replicas;
          selector.matchLabels.app = module.name;
          template = {
            metadata.name = module.name;
            metadata.labels.app = module.name;
            spec = {
              containers.prometheus-pushgateway = {
                image = config.image;
                ports = [{
                  name = "prometheus-push";
                  containerPort = 9091;
                }];
                readinessProbe = {
                  httpGet = {
                    path = "/#/status";
                    port = 9091;
                  };
                  initialDelaySeconds = 10;
                  timeoutSeconds = 10;
                };
                resources = {
                  requests = {
                    memory = "128Mi";
                    cpu = "10m";
                  };
                  limits = {
                    memory = "128Mi";
                    cpu = "10m";
                  };
                };
              };
            };
          };
        };
      };

      kubernetes.resources.services.prometheus-pushgateway = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        metadata.annotations."prometheus.io/probe" = "pushgateway";
        metadata.annotations."prometheus.io/scrape" = "true";
        spec = {
          ports = [{
            name = "prometheus-push";
            port = 9091;
            targetPort = 9091;
            protocol = "TCP";
          }];
          selector.app = module.name;
        };
      };
    };
  };

  config.kubernetes.moduleDefinitions.kube-state-metrics.module = {config, module, ...}: {
    options = {
      image = mkOption {
        description = "Image to use for kube-state-metrics";
        type = types.str;
        default = "k8s.gcr.io/kube-state-metrics:v1.2.0";
      };
    };

    config = {
      kubernetes.resources.deployments.kube-state-metrics = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          replicas = 1;
          selector.matchLabels.app = module.name;
          template = {
            metadata.name = module.name;
            metadata.labels.app = module.name;
            spec = {
              serviceAccountName = module.name;
              containers.kube-state-metrics = {
                image = config.image;
                ports = [{
                  name = "http-metrics";
                  containerPort = 8080;
                }];
                readinessProbe = {
                  httpGet = {
                    path = "/healthz";
                    port = 8080;
                  };
                  initialDelaySeconds = 5;
                  timeoutSeconds = 5;
                };
                resources = {
                  requests = {
                    memory = "100Mi";
                    cpu = "100m";
                  };
                  limits = {
                    memory = "200Mi";
                    cpu = "200m";
                  };
                };
              };
              containers.addon-resizer = {
                image = "k8s.gcr.io/addon-resizer:1.7";
                resources = {
                  requests = {
                    memory = "30Mi";
                    cpu = "100m";
                  };
                  limits = {
                    memory = "30Mi";
                    cpu = "100m";
                  };
                };
                env = {
                  MY_POD_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
                  MY_POD_NAME.valueFrom.fieldRef.fieldPath = "metadata.name";
                };
                command = [
                  "/pod_nanny"
                  "--container=kube-state-metrics"
                  /* "--cpu=100m"
                  "--extra-cpu=1m"
                  "--memory=100Mi"
                  "--extra-memory=2Mi"
                  "--threshold=5" */
                  "--deployment=${module.name}"
                ];
              };
              /* nodeSelector.node_label_key = "node_label_value"; */
            };
          };
        };
      };

      kubernetes.resources.services.kube-state-metrics = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        metadata.annotations."prometheus.io/scrape" = "true";
        spec = {
          ports = [{
            name = "http-metrics";
            port = 8080;
            protocol = "TCP";
          }];
          selector.app = module.name;
        };
      };

      kubernetes.resources.serviceAccounts.kube-state-metrics.metadata.name = module.name;

      kubernetes.resources.clusterRoles.kube-state-metrics = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = module.name;
        metadata.labels.app = module.name;
        rules = [{
          apiGroups = [""];
          resources = [
            "nodes"
            "pods"
            "services"
            "resourcequotas"
            "replicationcontrollers"
            "limitranges"
            "persistentvolumeclaims"
            "persistentvolumes"
            "namespaces"
            "endpoints"
          ];
          verbs = ["list" "watch"];
        } {
          apiGroups = ["extensions"];
          resources = [
            "daemonsets"
            "deployments"
            "replicasets"
          ];
          verbs = ["list" "watch"];
        } {
          apiGroups = [ "apps" ];
          resources = [ "statefulsets" ];
          verbs = [ "list" "watch" ];
        } {
          apiGroups = [ "batch" ];
          resources = [ "cronjobs" "jobs" ];
          verbs = [ "list" "watch" ];
        } {
          apiGroups = [ "autoscaling" ];
          resources = [ "horizontalpodautoscalers" ];
          verbs = [ "list" "watch" ];
        }];
      };

      kubernetes.resources.clusterRoleBindings.kube-state-metrics = {
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

      kubernetes.resources.roles.kube-state-metrics-resizer = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = module.name;
        metadata.labels.app = module.name;
        rules = [{
          apiGroups = [""];
          resources = ["pods"];
          resourceNames = ["vault"];
          verbs = ["get"];
        } {
          apiGroups = ["extensions"];
          resources = ["deployments"];
          resourceNames = ["kube-state-metrics"];
          verbs = ["get" "update"];
        }];
      };

      kubernetes.resources.roleBindings.kube-state-metrics = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = module.name;
        metadata.labels.app = module.name;
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "Role";
          name = module.name;
        };
        subjects = [{
          kind = "ServiceAccount";
          name = module.name;
        }];
      };
    };
  };

  config.kubernetes.moduleDefinitions.prometheus-node-exporter.module = {config, module, ...}: {
    options = {
      image = mkOption {
        description = "Prometheus node export image to use";
        type = types.str;
        default = "prom/node-exporter:v0.15.2";
      };

      ignoredMountPoints = mkOption {
        description = "Regex for ignored mount points";
        type = types.str;

        # this is ugly negative regex that ignores everyting except /host/.*
        default = "^/(([h][^o]?(/.+)?)|([h][o][^s]?(/.+)?)|([h][o][s][^t]?(/.+)?)|([^h]?[^o]?[^s]?[^t]?(/.+)?)|([^h][^o][^s][^t](/.+)?))$";
      };

      ignoredFsTypes = mkOption {
        description = "Regex of ignored filesystem types";
        type = types.str;
        default = "^(proc|sys|cgroup|securityfs|debugfs|autofs|tmpfs|sysfs|binfmt_misc|devpts|overlay|mqueue|nsfs|ramfs|hugetlbfs|pstore)$";
      };

      extraPaths = mkOption {
        description = "Extra node-exporter host paths";
        default = {};
        type = types.attrsOf (types.submodule ({name, config, ...}: {
          options = {
            hostPath = mkOption {
              description = "Host path to mount";
              type = types.path;
            };

            mountPath = mkOption {
              description = "Path where to mount";
              type = types.path;
              default = "/host/${name}";
            };
          };
        }));
      };

      extraArgs = mkOption {
        description = "Prometheus node exporter extra arguments";
        type = types.listOf types.str;
        default = [];
      };
    };

    config = {
      kubernetes.resources.daemonSets.prometheus-node-exporter = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          selector.matchLabels.app = module.name;
          template = {
            metadata.name = module.name;
            metadata.labels.app = module.name;
            spec = {
              containers.node-exporter = {
                image = config.image;
                args = [
                  "--path.procfs=/host/proc"
                  "--path.sysfs=/host/sys"
                  "--collector.filesystem.ignored-mount-points=${config.ignoredMountPoints}"
                  "--collector.filesystem.ignored-fs-types=${config.ignoredFsTypes}"
                ] ++ config.extraArgs;
                ports = [{
                  name = "node-exporter";
                  containerPort = 9100;
                }];
                livenessProbe = {
                  httpGet = {
                    path = "/metrics";
                    port = 9100;
                  };
                  initialDelaySeconds = 30;
                  timeoutSeconds = 1;
                };
                volumeMounts = [{
                  name = "proc";
                  mountPath = "/host/proc";
                  readOnly = true;
                } {
                  name = "sys";
                  mountPath = "/host/sys";
                  readOnly = true;
                }] ++ (mapAttrsToList (name: path: {
                  inherit name;
                  inherit (path) mountPath;
                  readOnly = true;
                }) config.extraPaths);
              };
              hostPID = true;
              volumes = {
                proc.hostPath.path = "/proc";
                sys.hostPath.path = "/sys";
              }// (mapAttrs (name: path: {
                hostPath.path = path.hostPath;
              }) config.extraPaths);
            };
          };
        };
      };

      kubernetes.resources.services.prometheus-node-exporter = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        metadata.annotations."prometheus.io/scrape" = "true";
        spec = {
          ports = [{
            name = "node-exporter";
            port = 9100;
            targetPort = 9100;
            protocol = "TCP";
          }];
          selector.app = module.name;
        };
      };
    };
  };

  config.kubernetes.moduleDefinitions.prometheus-alertmanager.module = {config, module, ...}: let
    routeOptions = {
      receiver = mkOption {
        description = "Which prometheus alertmanager receiver to use";
        type = types.str;
        default = "default";
      };

      groupBy = mkOption {
        description = "Group by alerts by field";
        default = [];
        type = types.listOf types.str;
      };

      continue = mkOption {
        description = "Whether an alert should continue matching subsequent sibling nodes";
        default = false;
        type = types.bool;
      };

      match = mkOption {
        description = "A set of equality matchers an alert has to fulfill to match the node";
        type = types.attrsOf types.str;
        default = {};
      };

      matchRe = mkOption {
        description = "A set of regex-matchers an alert has to fulfill to match the node.";
        type = types.attrsOf types.str;
        default = {};
      };

      groupWait = mkOption {
        description = "How long to initially wait to send a notification for a group of alerts.";
        type = types.str;
        default = "10s";
      };

      groupInterval = mkOption {
        description = ''
          How long to wait before sending a notification about new alerts that
          are added to a group of alerts for which an initial notification has
          already been sent. (Usually ~5min or more.)
        '';
        type = types.str;
        default = "5m";
      };

      repeatInterval = mkOption {
        description = ''
          How long to wait before sending a notification again if it has already
          been sent successfully for an alert. (Usually ~3h or more).
        '';
        type = types.str;
        default = "3h";
      };

      routes = mkOption {
        type = types.attrsOf (types.submodule {
          options = routeOptions;
        });
        description = "Child routes";
        default = {};
      };
    };

    mkRoute = cfg: {
      receiver = cfg.receiver;
      group_by = cfg.groupBy;
      continue = cfg.continue;
      match = cfg.match;
      match_re = cfg.matchRe;
      group_wait = cfg.groupWait;
      group_interval = cfg.groupInterval;
      repeat_interval = cfg.repeatInterval;
      routes = mapAttrsToList (name: route: mkRoute route) cfg.routes;
    };

    mkInhibitRule = cfg: {
      target_match = cfg.targetMatch;
      target_match_re = cfg.targetMatchRe;
      source_match = cfg.sourceMatch;
      source_match_re = cfg.sourceMatchRe;
      equal = cfg.equal;
    };

    mkReceiver = cfg: {
      name = cfg.name;
    } // optionalAttrs (cfg.type != null) {
      "${cfg.type}_configs" = [cfg.options];
    };

    alertmanagerConfig = {
      global = {
        resolve_timeout = config.resolveTimeout;
      };
      route = mkRoute config.route;
      receivers = mapAttrsToList (name: value: mkReceiver value) config.receivers;
      inhibit_rules = mapAttrsToList (name: value: mkInhibitRule value) config.inhibitRules;
      templates = config.templates;
    };
  in {
    options = {
      image = mkOption {
        description = "Prometheus alertmanager image to use";
        type = types.str;
        default = "prom/alertmanager:v0.15.0-rc.1";
      };

      replicas = mkOption {
        description = "Number of prometheus alertmanager replicas";
        type = types.int;
        default = 2;
      };

      resolveTimeout = mkOption {
        description = ''
          ResolveTimeout is the time after which an alert is declared resolved
          if it has not been updated.
        '';
        type = types.str;
        default = "5m";
      };

      receivers = mkOption {
        description = "Prometheus receivers";
        default = {};
        type = types.attrsOf (types.submodule ({name, config, ... }: {
          options = {
            name = mkOption {
              description = "Unique name of the receiver";
              type = types.str;
              default = module.name;
            };

            type = mkOption {
              description = "Receiver name (defaults to attr name)";
              type = types.nullOr (types.enum ["email" "hipchat" "pagerduty" "pushover" "slack" "opsgenie" "webhook" "victorops"]);
              default = null;
            };

            options = mkOption {
              description = "Reciver options";
              type = types.attrs;
              default = {};
              example = literalExample ''
                {
                  room_id = "System notiffications";
                  auth_token = "token";
                }
              '';
            };
          };
        }));
      };

      route = routeOptions;

      inhibitRules = mkOption {
        description = "Attribute set of alertmanager inhibit rules";
        default = {};
        type = types.attrsOf (types.submodule {
          options = {
            targetMatch = mkOption {
              description = "Matchers that have to be fulfilled in the alerts to be muted";
              type = types.attrsOf types.str;
              default = {};
            };

            targetMatchRe = mkOption {
              description = "Regex matchers that have to be fulfilled in the alerts to be muted";
              type = types.attrsOf types.str;
              default = {};
            };

            sourceMatch = mkOption {
              description = "Matchers for which one or more alerts have to exist for the inhibition to take effect.";
              type = types.attrsOf types.str;
              default = {};
            };

            sourceMatchRe = mkOption {
              description = "Regex matchers for which one or more alerts have to exist for the inhibition to take effect.";
              type = types.attrsOf types.str;
              default = {};
            };

            equal = mkOption {
              description = "Labels that must have an equal value in the source and target alert for the inhibition to take effect.";
              type = types.listOf types.str;
              default = [];
            };
          };
        });
      };

      templates = mkOption {
        description = ''
          Files from which custom notification template definitions are read.
          The last component may use a wildcard matcher, e.g. 'templates/*.tmpl'.
        '';
        type = types.listOf types.path;
        default = [];
      };

      storage = {
        size = mkOption {
          description = "Prometheus alertmanager storage size";
          default = "2Gi";
          type = types.str;
        };

        class = mkOption {
          description = "Prometheus alertmanager storage class";
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
    };

    config = {
      kubernetes.resources.statefulSets.prometheus-alertmanager = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          replicas = config.replicas;
          serviceName = module.name;
          selector.matchLabels.app = module.name;
          template = {
            metadata.name = module.name;
            metadata.labels.app = module.name;
            spec = {
              volumes.config.configMap.name = module.name;

              containers.server-reload = {
                image = "jimmidyson/configmap-reload:v0.2.2";
                args = [
                  "--volume-dir=/etc/config"
                  "--webhook-url=http://localhost:9093/-/reload"
                ];
                volumeMounts = [{
                  name = "config";
                  mountPath = "/etc/config";
                  readOnly = true;
                }];
              };

              containers.alertmanager = {
                image = config.image;
                args = [
                  "--config.file=/etc/config/alertmanager.json"
                  "--storage.path=/data"
                ] ++ config.extraArgs;
                ports = [{
                  name = "alertmanager";
                  containerPort = 9093;
                }];
                livenessProbe = {
                  httpGet = {
                    path = "/";
                    port = 9093;
                  };
                  initialDelaySeconds = 30;
                  timeoutSeconds = 30;
                };
                volumeMounts = {
                  export = {
                    name = "storage";
                    mountPath = "/data";
                  };
                  config = {
                    name = "config";
                    mountPath = "/etc/config";
                    readOnly = true;
                  };
                };
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

      kubernetes.resources.podDisruptionBudgets.prometheus-alertmanager = {
        metadata.name = module.name;
        spec.maxUnavailable = 1;
        spec.selector.matchLabels.app = module.name;
      };

      kubernetes.resources.configMaps.prometheus-alertmanager = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        data."alertmanager.json" = builtins.toJSON alertmanagerConfig;
      };

      kubernetes.resources.services.prometheus-alertmanager = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          ports = [{
            name = "alertmanager";
            port = 9093;
            targetPort = 9093;
            protocol = "TCP";
          }];
          selector.app = module.name;
        };
      };
    };
  };
}
