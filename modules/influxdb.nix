{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

let
  cfg = config.args.services.influxdb;
in
{
  imports = [
    kubenix.k8s
  ];

  options.args = {
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
    submodule = {
      name = "influxdb";
      version = "1.0.0";
      description = "";
    };
    kubernetes.api.statefulsets.influxdb = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        replicas = 1;
        serviceName = name;
        template = {
          metadata.labels.app = name;
          spec = {
            containers.influxdb = {
              image = config.args.image;

              env = {
                INFLUXDB_HTTP_AUTH_ENABLED = mkIf config.args.auth.enable {
                  value = "true";
                };
                INFLUXDB_ADMIN_USER =
                  mkIf (config.args.auth.adminUsername != null) (secretToEnv config.args.auth.adminUsername);
                INFLUXDB_ADMIN_PASSWORD =
                  mkIf (config.args.auth.adminPassword != null) (secretToEnv config.args.auth.adminPassword);
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
            resources.requests.storage = config.args.storage.size;
            storageClassName = config.args.storage.class;
          };
        }];
      };
    };

    kubernetes.api.services.influxdb = {
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
}