{ name, lib, config, k8s, ... }:

with lib;
with k8s;

{
  kubernetes.moduleDefinitions.rabbitmq.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Docker image to use";
        type = types.str;
        default = "rabbitmq:3.6.6-management-alpine";
      };

      replicas = mkOption {
        description = "Number of rabbitmq replicas to run";
        type = types.int;
        default = 3;
      };

      defaultUser = mkOption {
        type = types.str;
        description = "Default rabbitmq user";
        default = "guest";
      };

      defaultPassword = mkSecretOption {
        description = "Default rabbitmq password";
        default.key = "password";
      };

      erlangCookie = mkSecretOption {
        description = "Rabbitmq erlang cookie secret";
        default.key = "cookie";
      };

      storage = {
        enable = mkOption {
          description = "Whether to enable persistent storage for rabbitmq";
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
      kubernetes.resources.statefulSets.rabbitmq = mkMerge [
        (loadYAML ./rabbitmq-statfulset.yaml)
        {
          metadata.name = name;
          metadata.labels.app = name;
          spec.replicas = config.replicas;
          spec.serviceName = "${name}-cluster";
          spec.template.metadata.labels.app = name;
          spec.template.spec.containers.rabbitmq = {
            image = config.image;
            env = {
              RABBITMQ_DEFAULT_USER.value = config.defaultUser;
              RABBITMQ_DEFAULT_PASS = secretToEnv config.defaultPassword;
              RABBITMQ_ERLANG_COOKIE = secretToEnv config.erlangCookie;
              APP_NAME.value = name;
            };
            volumeMounts.storage = mkIf config.storage.enable {
              name = "storage";
              mountPath = "/var/lib/rabbitmq";
            };
          };
          spec.template.spec.containers.rabbitmq-prom-exporter = {
            env = {
              RABBIT_PASSWORD = secretToEnv config.defaultPassword;
              RABBIT_USER.value = config.defaultUser;
            };
          };
          spec.volumeClaimTemplates = mkIf config.storage.enable [{
            metadata.name = "storage";
            spec = {
              accessModes = ["ReadWriteOnce"];
              storageClassName = config.storage.class;
              resources.requests.storage = config.storage.size;
            };
          }];
        }
      ];

      kubernetes.resources.services.rabbitmq-cluster = mkMerge [
        (loadYAML ./rabbitmq-svc-headless.yaml)
        {
          metadata.name = "${name}-cluster";
          metadata.labels.app = name;
          spec.selector.app = name;
        }
      ];

      kubernetes.resources.services.rabbitmq = mkMerge [
        (loadYAML ./rabbitmq-svc.yaml)
        {
          metadata.name = name;
          metadata.labels.app = name;
          spec.selector.app = name;
        }
      ];

      kubernetes.resources.serviceAccounts.rabbitmq = mkMerge [
        (loadYAML ./rabbitmq-sa.yaml)
        { metadata.name = name; }
      ];

      kubernetes.resources.roles.rabbitmq = mkMerge [
        (loadYAML ./rabbitmq-role.yaml)
        { metadata.name = name; }
      ];

      kubernetes.resources.clusterRoleBindings.rabbitmq = mkMerge [
        (loadYAML ./rabbitmq-rolebinding.yaml)
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
