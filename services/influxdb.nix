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

      adminUsername = mkSecretOption {
        description = "Influx admin username to pre-create. If this is unset, no admin user is created";
        default = null;
      };

      adminPassword = mkSecretOption {
        description = "Influx admin password to pre-create. If this is unset, no admin user is created";
        default = null;
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
                  INFLUXDB_ADMIN_USER = mkIf (config.adminUsername != null) (secretToEnv config.adminUsername);
                  INFLUXDB_ADMIN_PASSWORD = mkIf (config.adminPassword != null) (secretToEnv config.adminPassword);
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
