{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;
   
    let
      configFiles = (mapAttrs' (n: v:
        let
          file = "${configMapName}.json";
          configMapName = "${name}-${removeSuffix ".json" n}";
          value = (if isAttrs v then builtins.toJSON v else builtins.readFile v);
        in
          nameValuePair file {
            inherit configMapName value;
          }
      ) (config.resources));
    in
{
  imports = [
    kubenix.k8s
  ];

  options.args = {
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
      default = (length (attrNames config.args.resources)) > 0;
    };

    resources = mkOption {
      description = "Attribute set of grafana resources to deploy (each resource key must end with resource type and an file ext, example: <some name>-<resource>.json)";
      example = literalExample ''
      {
        "pods-dashboard.json" = ./prometheus/pods-dashboard.json;
        "prometheus-datasource.json" = {};
      }
      '';
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
    submodule = {
      name = "grafana";
      version = "1.0.0";
      description = "";
    };

    kubernetes.api.deployments.grafana = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        replicas = config.args.replicas;
        strategy.type = "Recreate";
        selector.matchLabels.app = name;
        template = {
          metadata.name = name;
          metadata.labels.app = name;
          spec = {
            securityContext.fsGroup = 472;
            containers.grafana = {
              image = config.args.image;
              env = {
                GF_SERVER_ROOT_URL.value = config.args.rootUrl;
                GF_SECURITY_ADMIN_USER.value = "admin";
                GF_SECURITY_ADMIN_PASSWORD = secretToEnv config.args.adminPassword;
                GF_PATHS_DATA.value = "/data";
                GF_USERS_ALLOW_SIGN_UP.value = "false";
                GF_AUTH_BASIC_ENABLED.value = "true";
                GF_AUTH_ANONYMOUS_ENABLED.value = "true";
                GF_DATABASE_TYPE.value = config.args.db.type;
                GF_DATABASE_PATH.value = mkIf (config.args.db.path != null) config.args.db.path;
                GF_DATABASE_HOST.value = config.args.db.host;
                GF_DATABASE_NAME.value = config.args.db.name;
                GF_DATABASE_USER = mkIf (config.args.db.user != null) (secretToEnv config.args.db.user);
                GF_DATABASE_PASSWORD = mkIf (config.args.db.password != null) (secretToEnv config.args.db.password);
              } // (mapAttrs' (name: val: nameValuePair ("GF_" + name) val) config.args.extraConfig);

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

    kubernetes.api.services.grafana = {
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
    kubernetes.api.deployments.grafana = {
      spec.template.spec.volumes.storage.emptyDir = {};
    };
  }) (mkIf (config.db.type == "sqlite3") {
    kubernetes.api.deployments.grafana = {
      spec.template.spec.volumes.storage.persistentVolumeClaim.claimName = name;
    };

    kubernetes.api.persistentvolumeclaims.grafana = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        accessModes = ["ReadWriteOnce"];
        storageClassName = config.args.storage.class;
        resources.requests.storage = config.args.storage.size;
      };
    };
  }) (mkIf config.enableWatcher {
    kubernetes.api.deployments.grafana = {
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
            GRAFANA_PASSWORD = secretToEnv config.args.adminPassword;
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
          volumeMounts = mapAttrsToList (n: v: {
            name = v.configMapName;
            mountPath = "/var/grafana-resources/${n}";
            subPath = n;
            readOnly = true;
          }) configFiles;
        };
        volumes = mapAttrs' (n: v: nameValuePair v.configMapName {
          configMap.name = v.configMapName;
        }) configFiles;
      };
    };

    kubernetes.api.configmaps = mapAttrs' (n: v:
      nameValuePair v.configMapName {
        metadata.name = v.configMapName;
        metadata.labels.app = name;
        data."${n}" = v.value;
      }
    ) configFiles;
  })]);
}