{ config, lib, k8s, pkgs, ... }:

with k8s;
with lib;

{
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
        default.default = {};
        type = types.attrsOf (types.submodule ({name, config, ... }: {
          options = {
            name = mkOption {
              description = "Unique name of the receiver";
              type = types.str;
              default = name;
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
