{ name, args, config, pkgs, lib, kubenix, k8s, ...}:

with lib;
with k8s;

{
  imports = [
    kubenix.modules.submodule
    kubenix.modules.k8s
    kubenix.modules.docker
  ];

  options.submodule.args = {
    image = mkOption {
      description = "Docker image to use";
      type = types.str;
      default = "mariadb";
    };

    rootPassword = mkSecretOption {
      description = "MariaDB root password";
      default.key = "password";
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

    initdb = mkOption {
      description = "Initialization scripts or sql files";
      type = types.attrsOf types.lines;
      default = {};
    };

    extraArgs = mkOption {
      description = "List of extra mariadb args";
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
      name = "mariadb";
      version = "1.0.0";
      description = "Mariadb SQL database";
    };

    submodule.args.extraArgs = ["ignore-db-dir=lost+found"];

    docker.images.mariadb.image = pkgs.dockerTools.pullImage {
      imageName = "mariadb";
      imageDigest = "sha256:fb69aaa343a69826d4fb00809b8eb340a660cec3651a946dfd87f2113e0af627";
      sha256 = "1cmrynz60888015ks5k5fdl115dkg06jbh6x7r75zn6w2j6byyaf";
      finalImageTag = "10.4.3";
    };

    kubernetes.api.deployments.mariadb = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = name;
        template = {
          metadata.labels.app = name;
          spec = {
            containers.mariadb = {
              image = config.docker.images.mariadb.path;
              imagePullPolicy = "IfNotPresent";
              args = map (v: "--${v}") args.extraArgs;
              env = {
                MYSQL_ROOT_PASSWORD = secretToEnv args.rootPassword;
                MYSQL_DATABASE.value = args.mysql.database;
                MYSQL_USER = mkIf (args.mysql.user != null) (secretToEnv args.mysql.user);
                MYSQL_PASSWORD = mkIf (args.mysql.password != null) (secretToEnv args.mysql.password);
              };
              ports = [{
                name = "mariadb";
                containerPort = 3306;
              }];
              volumeMounts."/var/lib/mysql".name = "data";
              volumeMounts."/docker-entrypoint-initdb.d" =
                mkIf (args.initdb != {}) { name = "initdb"; };
            };
            volumes.data.persistentVolumeClaim.claimName = name;
            volumes.initdb = mkIf (args.initdb != {}) {
              configMap.name = name;
            };
          };
        };
      };
    };

    kubernetes.api.configmaps.mariadb = mkIf (args.initdb != {}) {
      metadata.name = name;
      metadata.labels.app = name;
      data = args.initdb;
    };

    kubernetes.api.poddisruptionbudgets.mariadb = {
      metadata.name = name;
      metadata.labels.app = name;
      spec.maxUnavailable = 1;
      spec.selector.matchLabels.app = name;
    };

    kubernetes.api.services.mariadb = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        ports = [{
          port = 3306;
          name = "mariadb";
        }];
        selector.app = name;
      };
    };

    kubernetes.api.persistentvolumeclaims.mariadb = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        accessModes = ["ReadWriteOnce"];
        resources.requests.storage = args.storage.size;
        storageClassName = args.storage.class;
      };
    };
  };
}
