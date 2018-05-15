{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.grafana.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Version of grafana to use";
        default = "grafana/grafana:5.1.2";
        type = types.str;
      };

      replicas = mkOption {
        description = "Number of grafana replicas to run";
        type = types.int;
        default = 1;
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

      enableWatcher = mkOption {
        description = "Whether to enable grafana watcher";
        type = types.bool;
        default = (length (attrNames config.resources)) > 0;
      };

      resources = mkOption {
        description = "Attribute set of grafana resources to deploy";
        default = {};
      };

      storage = {
        size = mkOption {
          description = "Elasticsearch storage size";
          default = "1Gi";
          type = types.str;
        };

        class = mkOption {
          description = "Elasticsearh datanode storage class";
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
                }];

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

                readinessProbe.httpGet = {
                  path = "/login";
                  port = 3000;
                };

                livenessProbe.httpGet = {
                  path = "/login";
                  port = 3000;
                };
              };
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
    }) (mkIf config.enableWatcher {
      kubernetes.resources.deployments.grafana = {
        spec.template.spec = {
          containers.watcher = {
            /* It subscribes to filesystem changes in a given directory,
            reads files matching *-datasource.json and *-dashboard.json
            and imports the datasources and dashboards to a given Grafana
            instance via Grafana's REST API */
            image = "quay.io/coreos/grafana-watcher:v0.0.8";
            args = [
              "--watch-dir=/var/grafana-resources"
              "--grafana-url=http://localhost:3000"
            ];
            env = {
              GRAFANA_USER.value = "admin";
              GRAFANA_PASSWORD = secretToEnv config.adminPassword;
            };
            resources = {
              requests = {
                memory = "16Mi";
                cpu = "50m";
              };
              limits = {
                memory = "32Mi";
                cpu = "100m";
              };
            };
            volumeMounts = [{
              name = "resources";
              mountPath = "/var/grafana-resources";
            }];
          };
          volumes.resources.configMap.name = name;
        };
      };

      kubernetes.resources.configMaps.grafana-resources = {
        metadata.name = name;
        metadata.labels.app = name;
        data = mapAttrs (name: value:
          if isAttrs value then builtins.toJSON value
          else builtins.readFile value
        ) config.resources;
      };
    })]);
  };
}
