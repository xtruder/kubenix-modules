{ name, lib, config, k8s, pkgs, ... }:

with k8s;
with lib;

let
  cfg = config.services.influxdb;
in {
  config.kubernetes.moduleDefinitions.influxdb.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Docker image to use";
        type = types.str;
        default = "influxdb:1.5.0";
      };

      auth = {
        enable = mkEnableOption "influxdb auth";

        adminUsername = mkSecretOption {
          description = "Influx admin username to pre-create. If this is unset, no admin user is created";
          default = null;
        };

        adminPassword = mkSecretOption {
          description = "Influx admin password to pre-create. If this is unset, no admin user is created";
          default = null;
        };
      };

      db = {
        name = mkOption {
          description = "Automatically initializes a database with this name.";
          type = types.nullOr types.str;
          default = null;
        };

        user = mkSecretOption {
          description = "Influx database username to grant access.";
          default = null;
        };

        password = mkSecretOption {
          description = "Influx database password to grant access.";
          default = null;
        };
      };

      storage = {
        size = mkOption {
          description = "Size of storage for redis per replica";
          type = types.str;
          default = "10G";
        };

        class = mkOption {
          description = "Storage class to use";
          type = types.nullOr types.str;
          default = null;
        };
      };
    };
    
    config = {
      kubernetes.resources.statefulSets.influxdb = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          replicas = 1;
          serviceName = name;
          template = {
            metadata.labels.app = name;
            spec = {
              containers.influxdb = {
                image = config.image;

                env = {
                  INFLUXDB_HTTP_AUTH_ENABLED = mkIf config.auth.enable {
                    value = "true";
                  };
                  INFLUXDB_ADMIN_USER =
                    mkIf (config.auth.adminUsername != null) (secretToEnv config.auth.adminUsername);
                  INFLUXDB_ADMIN_PASSWORD =
                    mkIf (config.auth.adminPassword != null) (secretToEnv config.auth.adminPassword);
                  INFLUXDB_DB = mkIf (config.db.name != null) {
                    value = config.db.name;
                  };
                  INFLUXDB_USER =
                    mkIf (config.db.user != null) (secretToEnv config.db.user);
                  INFLUXDB_USER_PASSWORD =
                    mkIf (config.db.password != null) (secretToEnv config.db.password);
                };

                ports = [{
                  name = "admin";
                  containerPort = 8083;
                } {
                  name = "http";
                  containerPort = 8086;
                } {
                  name = "udp";
                  protocol = "UDP";
                  containerPort = 8086;
                } {
                  name = "custer";
                  containerPort = 8088;
                }];

                volumeMounts = [{
                  name = "data";
                  mountPath = "/var/lib/influxdb";
                }];

                resources = {
                  requests.memory = "2048Mi";
                  requests.cpu = "200m";
                  limits.memory = "2048Mi";
                  limits.cpu = "200m";
                };
              };
              volumes.data.persistentVolumeClaim.claimName = name;
            };
          };

          volumeClaimTemplates = [{
            metadata.name = "data";
            spec = {
              accessModes = ["ReadWriteOnce"];
              resources.requests.storage = config.storage.size;
              storageClassName = config.storage.class;
            };
          }];
        };
      };

      kubernetes.resources.services.influxdb = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          ports = [{
            name = "admin";
            port = 8083;
          } {
            name = "http";
            port = 8086;
          } {
            name = "udp";
            protocol = "UDP";
            port = 8086;
          } {
            name = "cluster";
            port = 8088;
          }];
          selector.app = name;
        };
      };
    };
  };
}
