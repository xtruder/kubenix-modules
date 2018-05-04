{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.cloud-sql-proxy.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Docker image to use";
        type = types.str;
        default = "gcr.io/cloudsql-docker/gce-proxy:1.11";
      };

      port = mkOption {
        description = "Port which to expose from the container";
        type = types.int;
        default = 3306;
      };

      instances = mkOption {
        description = "Cloud SQL Proxy instances to connect to";
        type = types.listOf types.string;
        default = [];
      };

      credentials = {
        username = mkSecretOption {
          description = "Google Cloud SQL username to use";
          default = null;
        };
        password = mkSecretOption {
          description = "Google Cloud SQL password to use";
          default = null;
        };
      };
    };

    config = {
      kubernetes.resources.deployments.cloud-sql-proxy = {
        metadata = {
          name = name;
          labels.app = name;
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = name;
          template = {
            metadata = {
              labels.app = name;
            };
            spec = {
              containers.cloud_sql_proxy = {
                image = config.image;

                env = {
                  DB_USER = mkIf (config.credentials.username != null) (secretToEnv config.credentials.username);
                  DB_PASSWORD = mkIf (config.credentials.password != null) (secretToEnv config.credentials.password);
                };

                args = ["/cloud_sql_proxy" "-instances" (concatStringsSep "," config.instances) "-credential_file" "/secrets/cloudsql/credentials.json"];

                volumeMounts = [{
                  name = "cloudsql-instance-credentials";
                  mountPath = "/secrets/cloudsql";
                  readOnly = true;
                }];
              };
              volumes = [{
                name = "cloudsql-instance-credentials";
                secret.secretName = "cloudsql-instance-credentials";
              }];
            };
          };
        };
      };

      kubernetes.resources.services.cloud-sql-proxy = {
        metadata.name = name;
        metadata.labels.app = name;

        spec.selector.app = name;

        spec.ports = [{
          port = config.port;
          targetPort = 3306;
        }];
      };
    };
  };
}
