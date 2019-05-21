{ config, lib, k8s, ... }:

with lib;
with k8s;

{
  config.kubernetes.moduleDefinitions.ghost.module = {module, config, ...}: let
    name = module.name;
  in {
    options = {
      image = mkOption {
        description = "Docker image to use";
        type = types.str;
        default = "ghost:2-alpine";
      };

      replicas = mkOption {
        description = "Number of ghost replicas to run";
        type = types.int;
        default = 1;
      };

      url = mkOption {
        type = types.str;
        description = "URL of the blog";
      };

      mail = {
        enable = mkOption {
          description = "Whether to enable mails";
          type = types.bool;
          default = false;
        };

        service = mkOption {
          description = "Service to use for sending mails";
          type = types.str;
        };

        auth = {
          user = mkSecretOption {
            description = "Mail username";
            default.key = "username";
          };

          pass = mkSecretOption {
            description = "Mail password";
            default.key = "password";
          };
        };
      };

      database = {
        type = mkOption {
          description = "Database type";
          type = types.enum ["mysql"];
          default = "mysql";
        };

        name = mkOption {
          description = "Database name";
          type = types.str;
          default = "ghost";
        };

        host = mkOption {
          description = "Database host";
          type = types.str;
          default = "mysql";
        };

        port = mkOption {
          description = "Database port";
          type = types.int;
          default = 3306;
        };

        username = mkSecretOption {
          description = "Database user";
          default.key = "username";
        };

        password = mkSecretOption {
          description = "Database password";
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
      kubernetes.resources.deployments.ghost = {
        metadata = {
          name = name;
          labels.app = name;
        };
        spec = {
          replicas = config.replicas;
          strategy.type = "Recreate";
          selector.matchLabels.app = name;
          template = {
            metadata.labels.app = name;
            spec = {
              affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution = [{
                weight = 100;
                podAffinityTerm = {
                  labelSelector.matchExpressions = [{
                    key = "app";
                    operator = "In";
                    values = [ name ];
                  }];
                  topologyKey = "kubernetes.io/hostname";
                };
              }];

              containers.ghost = {
                image = config.image;

                env = mkMerge [{
                  url.value = config.url;
                  database__client.value = config.database.type;
                  database__connection__database.value = config.database.name;
                  database__connection__password = secretToEnv config.database.password;
                  database__connection__host.value = config.database.host;
                  database__connection__user = secretToEnv config.database.username;
                } (mkIf config.mail.enable {
                  mail__transport.value = "SMTP";
                  mail__options__service.value = config.mail.service;
                  mail__options__auth__user = secretToEnv config.mail.auth.user;
                  mail__options__auth__pass = secretToEnv config.mail.auth.pass;
                })];

                ports = [{
                  containerPort = 2368;
                }];
                volumeMounts = [{
                  name = "content";
                  mountPath = "/var/lib/ghost/content";
                }];
              };

              volumes.content.persistentVolumeClaim.claimName = name;
            };
          };
        };
      };

      kubernetes.resources.podDisruptionBudgets.ghost = {
        metadata.name = name;
        metadata.labels.app = name;
        spec.maxUnavailable = if config.replicas < 2 then config.replicas else "50%";
        spec.selector.matchLabels.app = name;
      };

      kubernetes.resources.persistentVolumeClaims.ghost = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          accessModes = ["ReadWriteOnce"];
          resources.requests.storage = config.storage.size;
          storageClassName = config.storage.class;
        };
      };

      kubernetes.resources.services.ghost = {
        metadata.name = name;
        metadata.labels.app = name;

        spec.selector.app = name;

        spec.ports = [{
          name = "http";
          port = 80;
          targetPort = 2368;
        }];
      };
    };
  };
}
