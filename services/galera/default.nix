{ name, lib, config, k8s, pkgs, ... }:

with lib;
with k8s;

{
  kubernetes.moduleDefinitions.galera.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Docker image to use";
        type = types.str;
        default = "mariadb:10.3";
      };

      metricsImage = mkOption {
        description = "Docker image for metrics";
        type = types.str;
        default = "prom/mysqld-exporter@sha256:a1eda24a95f09a817f2cf39a7fa3d506df88e76ebdc08c0293744ebaa546e3ab";
      };

      replicas = mkOption {
        type = types.int;
        default = 1;
        description = "Number of mysql replicas";
      };

      rootPassword = mkSecretOption {
        description = "Root password";
        default.key = "password";
      };

      database = mkOption {
        description = "Database to pre create";
        type = types.nullOr types.str;
        default = null;
      };

      user = mkOption {
        description = "Databse user";
        type = types.nullOr types.str;
        default = null;
      };

      password = mkSecretOption {
        description = "Database password";
        default = null;
      };

      storage = {
        enable = mkOption {
          description = "Whether to enable persistent storage for mysql";
          type = types.bool;
          default = false;
        };

        size = mkOption {
          description = "Storage size";
          type = types.str;
          default = "1000m";
        };

        class = mkOption {
          description = "Storage class";
          type = types.nullOr types.str;
          default = null;
        };
      };
    };

    config = {
      kubernetes.resources.statefulSets.mysql = mkMerge [
        (loadYAML ./statefulset.yaml)
        {
          metadata.name = name;
          metadata.labels.app = name;
          spec.replicas = config.replicas;
          spec.serviceName = "${name}-cluster";
          spec.template.metadata.labels.app = name;
          spec.template.spec.initContainers.init-config = {
            image = config.image;
          };
          spec.template.spec.containers.metrics = {
            image = config.metricsImage;
          };
          spec.template.spec.containers.mysql = {
            image = config.image;
            env = {
              MYSQL_DATABASE.value = mkIf (config.database != null) config.database;
              MYSQL_USER.value = mkIf (config.user != null) config.user;
              MYSQL_PASSWORD = mkIf (config.password != null) config.password;
            };
            volumeMounts."mysql-init" = {
              name = "mysql-init";
              mountPath = "/docker-entrypoint-initdb.d";
              readOnly = true;
            };
          };
          spec.template.spec.volumes.mysql-init = {
            secret.secretName = "${name}-init";
          };
          spec.template.spec.volumes.conf = {
            configMap.name = "${name}-conf-d";
          };
          spec.volumeClaimTemplates = mkIf config.storage.enable [{
            metadata.name = "mysql";
            spec = {
              accessModes = ["ReadWriteOnce"];
              storageClassName = config.storage.class;
              resources.requests.storage = config.storage.size;
            };
          }];
        }
      ];

      kubernetes.resources.secrets.mysql-init = {
        metadata.name = "${name}-init";
        data."init.sql" = k8s.toBase64 ''
          grant all privileges on *.* to root@'\''''''%'\'''''' identified by '\''''''${config.rootPassword.value}'\'''''';
        '';
      };

      kubernetes.resources.configMaps.conf-d = mkMerge [
        (loadYAML ./configmap.yaml)
        {
          metadata.name = "${name}-conf-d";
          data."galera.cnf" = ''
            [galera]
            wsrep_on=${if config.replicas == 1 then "OFF" else "ON"}
            wsrep_provider="/usr/lib/galera/libgalera_smm.so"
            #init#wsrep_new_cluster=true#init#
            #init#wsrep_provider_options="pc.bootstrap=true"#init#
            wsrep_cluster_address="gcomm://${concatMapStringsSep "," (x: "${name}-${toString x}.${name}-cluster") (range 0 (config.replicas - 1))}"
            binlog_format=ROW
            default_storage_engine=InnoDB
            innodb_autoinc_lock_mode=2
            wsrep-sst-method=rsync

            bind-address=0.0.0.0
          '';
        }
      ];

      kubernetes.resources.services.mysql = mkMerge [
        (loadYAML ./svc.yaml)
        {
          metadata.name = name;
          metadata.labels.app = name;
          spec.selector.app = name;
        }
      ];

      kubernetes.resources.services.mysql-cluster = mkMerge [
        (loadYAML ./svc-headless.yaml)
        {
          metadata.name = "${name}-cluster";
          metadata.labels.app = name;
          spec.selector.app = name;
        }
      ];

      kubernetes.resources.serviceAccounts.mysql = mkMerge [
        (loadYAML ./sa.yaml)
        { metadata.name = name; }
      ];

      kubernetes.resources.roles.mysql = mkMerge [
        (loadYAML ./role.yaml)
        { metadata.name = name; }
      ];

      kubernetes.resources.clusterRoleBindings.mysql = mkMerge [
        (loadYAML ./rolebinding.yaml)
        {
          metadata.name = name;
          roleRef.name = name;
          subjects = mkForce [{
            kind = "ServiceAccount";
            name = name;
          }];
        }
      ];
    };
  };
}
