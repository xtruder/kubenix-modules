{ config, lib, k8s, ... }:

with k8s;
with lib;

let
  moduleToAttrs = value:
    if isAttrs value
    then mapAttrs (n: v: moduleToAttrs v) (filterAttrs (n: v: !(hasPrefix "_" n) && v != null) value)

    else if isList value
    then map (v: moduleToAttrs v) value

    else value;
in {
  config.kubernetes.moduleDefinitions.grafana.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Version of grafana to use";
        default = "grafana/grafana:6.1.6";
        type = types.str;
      };

      replicas = mkOption {
        description = "Number of grafana replicas to run";
        type = types.int;
        default = 1;
      };

      resources = {
        requests = mkOption {
          description = "Resource requests configuration";
          type = with types; nullOr (submodule ({name, config, ...}: {
            options = {
              cpu = mkOption {
                description = "Requested CPU";
                type = str;
                default = "100m";
              };

              memory = mkOption {
                description = "Requested memory";
                type = str;
                default = "100Mi";
              };
            };
          }));
          default = {};
        };

        limits = mkOption {
          description = "Resource limits configuration";
          type = with types; nullOr (submodule ({name, config, ...}: {
            options = {
              cpu = mkOption {
                description = "CPU limit";
                type = str;
                default = "200m";
              };

              memory = mkOption {
                description = "Memory limit";
                type = str;
                default = "200Mi";
              };
            };
          }));
          default = {};
        };
      };

      rootUrl = mkOption {
        description = "Grafana root url";
        type = types.str;
      };

      adminPassword = mkSecretOption {
        description = "Grafana admin password";
        default.key = "password";
      };

      db = {
        type = mkOption {
          description = "Database type";
          default = null;
          type = types.enum [null "sqlite3" "mysql" "postgres"];
        };

        path = mkOption {
          description = "Database path";
          type = types.nullOr types.str;
          default = null;
        };

        host = mkOption {
          description = "Database host";
          type = types.nullOr types.str;
          default = null;
        };

        name = mkOption {
          description = "Database name";
          type = types.nullOr types.str;
          default = null;
        };

        user = mkSecretOption {
          description = "Database user";
          default = null;
        };

        password = mkSecretOption {
          description = "Database password";
          default = null;
        };
      };

      provisioning = {
        datasources = mkOption {
          description = "Attribute set of datasources to provision";
          type = types.attrsOf (types.submodule ({name, config, ...}: {
            options = {
              name = mkOption {
                description = "Datasource name";
                type = types.str;
                default = name;
              };

              type = mkOption {
                description = "Datasource type";
                type = types.str;
              };

              access = mkOption {
                description = "Datasource access mode";
                type = types.enum ["proxy" "direct"];
                default = "proxy";
              };

              editable = mkOption {
                description = "Whether to allow edit dashboard from the UI";
                type = types.bool;
                default = false;
              };

              orgId = mkOption {
                description = "Datasource organization ID";
                type = types.int;
                default = 1;
              };

              url = mkOption {
                description = "Datasource url";
                type = types.str;
                default = "";
              };

              user = mkOption {
                description = "Datasource database user";
                type = types.str;
                default = "";
              };

              password = mkOption {
                description = "Datasource password";
                type = types.str;
                default = "";
              };

              database = mkOption {
                description = "Datasource database";
                type = types.str;
                default = "";
              };

              basicAuth = mkOption {
                description = "Whether enable/disable datasource basic auth";
                type = types.bool;
                default = false;
              };

              basicAuthUser = mkOption {
                description = "Datasource basic auth user";
                type = types.str;
                default = "";
              };

              basicAuthPassword = mkOption {
                description = "Datasource basic auth password";
                type = types.str;
                default = "";
              };

              withCredentials = mkOption {
                description = "Whether to pass credentials";
                type = types.bool;
                default = true;
              };

              isDefault = mkOption {
                description = "Whether this is a default datasource";
                type = types.bool;
                default = config.name == "default";
              };

              jsonData = mkOption {
                description = "Additional configuration json data";
                type = types.attrs;
                default = {};
              };
            };
          }));
          default = {};
        };

        notifiers = mkOption {
          description = "Attribute set of notifiers to provision";
          type = types.attrsOf (types.submodule ({name, config, ...}: {
            options = {
              name = mkOption {
                description = "Notifier name";
                type = types.str;
                default = name;
              };

              type = mkOption {
                description = "Notifier type";
                type = types.enum [
                  "slack" "pushover" "victorops" "kafka" "LINE" "pagerduty"
                  "sensu" "prometheus-alertmanager" "teams" "dingding" "email"
                  "hipchat" "opsgenie" "telegram" "threema" "webhook"
                ];
              };

              uid = mkOption {
                description = "Notifier uid";
                type = types.str;
                default = "";
              };

              orgId = mkOption {
                description = "Notifier organization ID";
                type = types.int;
                default = 1;
              };

              orgName = mkOption {
                description = "Notifier organization name";
                type = types.str;
                default = "";
              };

              isDefault = mkOption {
                description = "Whether this is default notifier";
                type = types.bool;
                default = config.name == "default";
              };

              settings = mkOption {
                description = "Notifier settings";
                type = types.attrs;
                default = {};
              };
            };
          }));
          default = {};
        };

        dashboardProviders = mkOption {
          description = "Attribute set of dashboard sources to provision";
          type = types.attrsOf (types.submodule ({name, config, ...}: {
            options = {
              name = mkOption {
                description = "Dashboards provider name";
                type = types.str;
                default = name;
              };

              orgId = mkOption {
                description = "Organization ID";
                type = types.int;
                default = 1;
              };

              disableDeletion = mkOption {
                description = "Whether to disable dasboard deletion";
                type = types.bool;
                default = false;
              };

              updateIntervalSeconds = mkOption {
                description = "Dashboard update interval";
                type = types.int;
                default = 10;
              };

              dashboards = mkOption {
                description = "Attribute set of dashboards";
                type = types.attrsOf (types.either types.attrs types.path);
                default = {};
              };
            };
          }));
          default = {};
        };
      };

      storage = {
        size = mkOption {
          description = "Grafana storage size";
          default = "1Gi";
          type = types.str;
        };

        class = mkOption {
          description = "Grafana storage class";
          type = types.nullOr types.str;
          default = null;
        };
      };

      extraConfig = mkOption {
        description = "Grafana extra configuration options";
        type = types.attrsOf types.attrs;
        default = {};
      };
    };

    config = (mkMerge [{
      kubernetes.resources.deployments.grafana = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          replicas = config.replicas;
          strategy.type = "Recreate";
          selector.matchLabels.app = name;
          template = {
            metadata.name = name;
            metadata.labels.app = name;
            spec = {
              securityContext.fsGroup = 472;
              containers.grafana = {
                image = config.image;
                env = {
                  GF_SERVER_ROOT_URL.value = config.rootUrl;
                  GF_SECURITY_ADMIN_USER.value = "admin";
                  GF_SECURITY_ADMIN_PASSWORD = secretToEnv config.adminPassword;
                  GF_PATHS_DATA.value = "/data";
                  GF_USERS_ALLOW_SIGN_UP.value = "false";
                  GF_AUTH_BASIC_ENABLED.value = "true";
                  GF_AUTH_ANONYMOUS_ENABLED.value = "true";
                  GF_DATABASE_TYPE.value = config.db.type;
                  GF_DATABASE_PATH.value = mkIf (config.db.path != null) config.db.path;
                  GF_DATABASE_HOST.value = config.db.host;
                  GF_DATABASE_NAME.value = config.db.name;
                  GF_DATABASE_USER = mkIf (config.db.user != null) (secretToEnv config.db.user);
                  GF_DATABASE_PASSWORD = mkIf (config.db.password != null) (secretToEnv config.db.password);
                } // (mapAttrs' (name: val: nameValuePair ("GF_" + name) val) config.extraConfig);

                ports = [{
                  containerPort = 3000;
                  name = "grafana";
                }];
                volumeMounts = [{
                  name = "storage";
                  mountPath = "/data";
                  readOnly = false;
                } {
                  name = "datasources";
                  mountPath = "/etc/grafana/provisioning/datasources";
                  readOnly = false;
                } {
                  name = "notifiers";
                  mountPath = "/etc/grafana/provisioning/notifiers";
                  readOnly = false;
                } {
                  name = "dashboard-providers";
                  mountPath = "/etc/grafana/provisioning/dashboards";
                  readOnly = false;
                }] ++ flatten (mapAttrsToList (_: provider:
                  mapAttrsToList (n: dashboard: {
                    name = "dashboard-${provider.name}-${n}";
                    mountPath = "/grafana-dashboard-definitions/${provider.name}/${n}.json";
                    subPath = "dashboard.yaml";
                    readOnly = false;
                  }) provider.dashboards
                ) config.provisioning.dashboardProviders);

                resources = {
                  requests = mkIf (config.resources.requests != null) config.resources.requests;
                  limits = mkIf (config.resources.limits != null) config.resources.limits;
                };

                readinessProbe = {
                  httpGet = {
                    path = "/api/health";
                    port = 3000;
                  };
                  periodSeconds = 1;
                  timeoutSeconds = 1;
                  successThreshold = 1;
                  failureThreshold = 10;
                };
              };
              volumes = [{
                name = "datasources";
                configMap.name = "${name}-datasources";
              } {
                name = "notifiers";
                configMap.name = "${name}-notifiers";
              } {
                name = "dashboard-providers";
                configMap.name = "${name}-dashboard-providers";
              }] ++ flatten (mapAttrsToList (_: provider:
                mapAttrsToList (n: dashboard: {
                  name = "dashboard-${provider.name}-${n}";
                  configMap.name = "${name}-dashboard-${provider.name}-${n}";
                }) provider.dashboards
              ) config.provisioning.dashboardProviders);
            };
          };
        };
      };

      kubernetes.resources.services.grafana = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          ports = [{
            name = "http";
            port = 80;
            targetPort = 3000;
          }];
          selector.app = name;
        };
      };

      kubernetes.resources.configMaps = mkMerge ([{
        grafana-datasources = {
          metadata.name = "${name}-datasources";
          metadata.labels.app = name;
          data."datasources.yaml" = builtins.toJSON {
            apiVersion = 1;
            datasources = attrValues (moduleToAttrs config.provisioning.datasources);
          };
        };

        grafana-notifiers = {
          metadata.name = "${name}-notifiers";
          metadata.labels.app = name;
          data."notifiers.yaml" = builtins.toJSON {
            notifiers = mapAttrsToList (_: notifier: {
              inherit (notifier) name type uid settings;
              org_id = notifier.orgId;
              org_name = notifier.orgName;
              id_default = notifier.isDefault;
            }) config.provisioning.notifiers;
          };
        };

        grafana-dashboard-providers = {
          metadata.name = "${name}-dashboard-providers";
          metadata.labels.app = name;
          data."dashboards.yaml" = builtins.toJSON {
            apiVersion = 1;
            providers = mapAttrsToList (_: provider: {
              inherit (provider) name orgId disableDeletion updateIntervalSeconds;
              folder = "";
              type = "file";
              options.path = "/grafana-dashboard-definitions/${provider.name}";
            }) config.provisioning.dashboardProviders;
          };
        };
      }] ++ flatten (mapAttrsToList (_: provider:
        mapAttrsToList (n: dashboard: {
          "grafana-dashboard-${provider.name}-${n}" = {
            metadata.name = "${name}-dashboard-${provider.name}-${n}";
            metadata.labels.app = name;
            data."dashboard.yaml" =
              if isAttrs dashboard
              then builtins.toJSON dashboard
              else builtins.readFile dashboard;
          };
        }) provider.dashboards
      ) config.provisioning.dashboardProviders));
    } (mkIf (config.db.type != "sqlite3") {
      kubernetes.resources.deployments.grafana = {
        spec.template.spec.volumes.storage.emptyDir = {};
      };
    }) (mkIf (config.db.type == "sqlite3") {
      kubernetes.resources.deployments.grafana = {
        spec.template.spec.volumes.storage.persistentVolumeClaim.claimName = name;
      };

      kubernetes.resources.persistentVolumeClaims.grafana = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          accessModes = ["ReadWriteOnce"];
          storageClassName = config.storage.class;
          resources.requests.storage = config.storage.size;
        };
      };
    })]);
  };
}
