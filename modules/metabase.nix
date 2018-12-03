{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.metabase.module = {config, module, ...}: let
    name = module.name;
  in {
    options = {
      image = mkOption {
        description = "Name of the metabase image to use";
        type = types.str;
        default = "metabase/metabase:v0.30.1";
      };

      replicas = mkOption {
        description = "Number of metabase replicas to run";
        type = types.int;
        default = 1;
      };

      database = {
        type = mkOption {
          description = "Type of metabase database to use";
          type = types.enum ["h2" "mysql" "postgres"];
          default = "h2";
        };

        host = mkOption {
          description = "Metabase DB host";
          type = types.nullOr types.str;
          default = null;
        };

        port = mkOption {
          description = "Metabase DB port";
          type = types.nullOr types.int;
          default = null;
        };

        dbName = mkOption {
          description = "Metabase DB name";
          type = types.str;
          default = "metabase";
        };

        user = mkSecretOption {
          description = "Metabase DB username";
          default = null;
        };

        pass = mkSecretOption {
          description = "Metabase DB password";
          default = null;
        };

        encryptionSecretKey = mkSecretOption {
          description = "Metabase DB encryption secret key";
          default = null;
        };
      };

      password = {
        complexity = mkOption {
          description = "Metabase password complexity";
          type = types.enum ["weak" "normal" "string"];
          default = "normal";
        };

        length = mkOption {
          description = "Metabase password length";
          type = types.int;
          default = 6;
        };
      };

      storage = {
        enable = mkEnableOption "enable storage";

        size = mkOption {
          description = "Metabase storage size";
          type = types.str;
          default = "10Gi";
        };

        class = mkOption {
          description = "Storage class to use";
          type = types.nullOr types.str;
          default = null;
        };
      };

      timezone = mkOption {
        description = "Timezone to use";
        type = types.str;
        default = "UTC";
      };
    };

    config = {
      storage.enable = mkDefault (config.database.type == "h2");

      kubernetes.resources.deployments.metabase = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          selector.matchLabels.app = name;
          replicas = config.replicas;
          template = {
            metadata.labels.app = name;
            spec = {
              containers.metabase = {
                image = config.image;
                imagePullPolicy = "Always";
                env = {
                  MB_JETTY_HOST.value = "0.0.0.0";
                  MB_JETTY_PORT.value = "3000";
                  MB_DB_TYPE.value = config.database.type;
                  MB_ENCRYPTION_SECRET_KEY = mkIf (config.database.encryptionSecretKey != null) (secretToEnv config.database.encryptionSecretKey);
                  MB_DB_HOST = mkIf (config.database.host != null) {value = config.database.host;};
                  MB_DB_PORT = mkIf (config.database.port != null) {value = toString config.database.port;};
                  MB_DB_DBNAME.value = config.database.dbName;
                  MB_DB_USER = mkIf (config.database.user != null) (secretToEnv config.database.user);
                  MB_DB_PASS = mkIf (config.database.pass != null) (secretToEnv config.database.pass);
                  MB_DB_FILE.value = "/metabase-data";
                  MB_PASSWORD_COMPLEXITY.value = config.password.complexity;
                  MB_PASSWORD_LENGTH.value = toString config.password.length;
                  JAVA_TIMEZONE.value = config.timezone;
                  MB_EMOJI_IN_LOGS.value = "false";
                };
                ports = [{
                  containerPort = 3000;
                  name = "http";
                }];
                livenessProbe = {
                  httpGet = {
                    path = "/";
                    port = 3000;
                  };
                  initialDelaySeconds = 120;
                  timeoutSeconds = 5;
                  failureThreshold = 6;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/";
                    port = 3000;
                  };
                  initialDelaySeconds = 30;
                  timeoutSeconds = 5;
                  failureThreshold = 6;
                };
                resources = {
                  limits = {
                    cpu = "1000m";
                    memory = "4096Mi";
                  };
                  requests = {
                    cpu = "1000m";
                    memory = "4096Mi";
                  };
                };
                volumeMounts."/data" = mkIf config.storage.enable {
                  name = "storage";
                  mountPath = "/metabase-data";
                };
              };
              volumes.storage = mkIf config.storage.enable {
                persistentVolumeClaim.claimName = name;
              };
            };
          };
        };
      };

      kubernetes.resources.services.metabase = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          selector.app = name;
          ports = [{
            port = 80;
            targetPort = 3000;
            name = "http";
          }];
        };
      };

      kubernetes.resources.persistentVolumeClaims.metabase = mkIf config.storage.enable {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          accessModes = ["ReadWriteOnce"];
          storageClassName = config.storage.class;
          resources.requests.storage = config.storage.size;
        };
      };
    };
  };
}
