{ name, lib, config, k8s, pkgs, ... }:

with lib;
with k8s;

{
  config.kubernetes.moduleDefinitions.galera.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Docker image to use";
        type = types.str;
        default = "xtruder/k8s-mariadb-cluster";
      };

      replicas = mkOption {
        description = "Number of mariadb replicas";
        type = types.int;
        default = 3;
      };

      rootPassword = mkSecretOption {
        description = "MariaDB root password";
        default.key = "password";
      };

      discoveryService = mkOption {
        description = "Etcd discovery service";
        type = types.str;
        default = "etcd-client:2379";
      };

      xtrabackupPassword = mkSecretOption {
        description = "MariaDB xtra backup password";
        default.key = "password";
      };

      clusterName = mkOption {
        description = "Name of mariadb cluster";
        type = types.str;
        default = name;
      };

      mysql = {
        database = mkOption {
          description = "Name of the mysql database to pre-create";
          type = types.nullOr types.str;
          default = null;
        };

        user = mkSecretOption {
          description = "Mysql user to pre-create";
          default.key = "username";
        };

        password = mkSecretOption {
          description = "Mysql password to pre-create";
          default.key = "password";
        };
      };

      storage = {
        class = mkOption {
          description = "Name of the storage class to use";
          type = types.nullOr types.str;
          default = null;
        };

        size = mkOption {
          description = "Storage size";
          type = types.str;
          default = "10Gi";
        };
      };
    };

    config = {
      kubernetes.resources.services.galera = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          ports = [{
            port = 3306;
            name = "mysql";
          }];
          clusterIP = "None";
          selector.app = name;
        };
      };

      kubernetes.resources.statefulSets.galera = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          serviceName = name;
          podManagementPolicy = "Parallel";
          replicas = config.replicas;
          template = {
            metadata.labels.app = name;
            spec = {
              containers.galera = {
                image = config.image;
                env = {
                  MYSQL_ROOT_PASSWORD = secretToEnv config.rootPassword;
                  DISCOVERY_SERVICE.value = config.discoveryService;
                  XTRABACKUP_PASSWORD = secretToEnv config.xtrabackupPassword;
                  CLUSTER_NAME.value = config.clusterName;
                  MYSQL_DATABASE.value = config.mysql.database;
                  MYSQL_USER = secretToEnv config.mysql.user;
                  MYSQL_PASSWORD = secretToEnv config.mysql.password;
                };
                ports = [{
                  name = "mysql";
                  containerPort = 3306;
                }];
                readinessProbe = {
                  exec.command = ["/healthcheck.sh" "--readiness"];
                  initialDelaySeconds = 120;
                  periodSeconds = 1;
                };
                livenessProbe = {
                  exec.command = ["/healthcheck.sh" "--liveness"];
                  initialDelaySeconds = 120;
                  periodSeconds = 1;
                };
                volumeMounts = [{
                  name = "mysql-datadir";
                  mountPath = "/var/lib/mysql";
                }];
              };
            };
          };
          volumeClaimTemplates = [{
            metadata.name = "mysql-datadir";
            spec = {
              accessModes = ["ReadWriteOnce"];
              storageClassName = mkIf (config.storage.class != null) config.storage.class;
              resources.requests.storage = config.storage.size;
            };
          }];
        };
      };
    };
  };
}
