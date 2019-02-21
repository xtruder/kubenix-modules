{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

{
  imports = [
    kubenix.k8s
  ];

  options.args = {
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
      default = "etcd:2379";
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
        default = null;
      };

      password = mkSecretOption {
        description = "Mysql password to pre-create";
        default = null;
      };
    };

    extraArgs = mkOption {
      description = "Extra arguments passed to mariadb";
      type = types.listOf types.str;
      default = [];
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
    submodule = {
      name = "galera";
      version = "1.0.0";
      description = "";
    };
    kubernetes.api.services.galera = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        ports = [{
          port = 3306;
          name = "mysql";
        }];
        selector.app = name;
      };
    };

    kubernetes.api.statefulSets.galera = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        serviceName = name;
        replicas = config.args.replicas;
        template = {
          metadata.labels.app = name;
          spec = {
            containers.galera = {
              image = config.args.image;
              args = config.args.extraArgs;
              env = {
                MYSQL_ROOT_PASSWORD = secretToEnv config.args.rootPassword;
                DISCOVERY_SERVICE.value = config.args.discoveryService;
                XTRABACKUP_PASSWORD = secretToEnv config.args.xtrabackupPassword;
                CLUSTER_NAME.value = config.args.clusterName;
                MYSQL_DATABASE.value = config.args.mysql.database;
                MYSQL_USER = mkIf (config.args.mysql.user != null) (secretToEnv config.args.mysql.user);
                MYSQL_PASSWORD = mkIf (config.args.mysql.password != null) (secretToEnv config.args.mysql.password);
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
                initialDelaySeconds = 300;
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
            storageClassName = mkIf (config.args.storage.class != null) config.args.storage.class;
            resources.requests.storage = config.args.storage.size;
          };
        }];
      };
    };
  };
}