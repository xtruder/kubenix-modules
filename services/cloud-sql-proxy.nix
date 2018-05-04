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

      instances = mkOption {
        description = "Cloud SQL Proxy instances to connect to";
        type = types.listOf types.string;
        default = [];
      };

      dbCredentials = {
        username = mkSecretOption {
          description = "Google Cloud SQL username to use";
          default = null;
        };
        password = mkSecretOption {
          description = "Google Cloud SQL password to use";
          default = null;
        };
      };

      instanceCredentials = mkOption {
        description = "Google Cloud SQL instance credentials file secret name";
        type = types.string;
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
              containers.cloud-sql-proxy = {
                image = config.image;

                env = {
                  DB_USER = mkIf (config.dbCredentials.username != null) (secretToEnv config.dbCredentials.username);
                  DB_PASSWORD = mkIf (config.dbCredentials.password != null) (secretToEnv config.dbCredentials.password);
                };

                args = ["/cloud_sql_proxy" "-instances" (concatStringsSep "," config.instances) "-credential_file" "/secrets/cloudsql/credentials.json"];

                ports = [{
                  name = "cloud-sql-proxy";
                  containerPort = 3306;
                }];

                volumeMounts = [{
                  name = "cloudsql-instance-credentials";
                  mountPath = "/secrets/cloudsql";
                  readOnly = true;
                }];
              };
              volumes = [{
                name = "cloudsql-instance-credentials";
                secret.secretName = "${config.instanceCredentials}";
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
          name = "cloud-sql-proxy";
          port = 3306;
        }];
      };
    };
  };
}
