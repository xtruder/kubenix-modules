{ config, lib, k8s, ... }:

with lib;
with k8s;

{
  config.kubernetes.moduleDefinitions.ghost.module = {module, config, ...}: {
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

      smtp.username = mkSecretOption {
        description = "Smtp username";
        default.key = "username";
      };

      smtp.password = mkSecretOption {
        description = "Smtp password";
        default.key = "password";
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
    };

    config = {
      kubernetes.resources.statefulSets.ghost = {
        metadata = {
          name = module.name;
          labels.app = module.name;
        };
        spec = {
          serviceName = module.name;
          replicas = config.replicas;
          selector.matchLabels.app = module.name;
          template = {
            metadata.labels.app = module.name;
            spec = {
              affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution = [{
                weight = 100;
                podAffinityTerm = {
                  labelSelector.matchExpressions = [{
                    key = "app";
                    operator = "In";
                    values = [ module.name ];
                  }];
                  topologyKey = "kubernetes.io/hostname";
                };
              }];

              containers.ghost = {
                image = config.image;
                env.url.value= "http://ghost.gatehub.net";
                env.GHOST_INSTALL.value = "/ghost/data";

                env.database__client.value = config.database.type;
                env.database__connection__database.value = config.database.name;
                env.database__connection__password = secretToEnv config.database.password;
                env.database__connection__host.value = config.database.host;
                env.database__connection__user = secretToEnv config.database.username;
                

                env.mail__transport.value = "SMTP";
                env.mail__options__service.value = "Mailgun";
                env.mail__options__auth__user = secretToEnv config.smtp.username;
                env.mail__options__auth__pass =  secretToEnv config.smtp.password;

                securityContext.capabilities.add = ["NET_ADMIN"];

                ports = [{
                  containerPort = 2368;
                }];
                volumeMounts = [{
                  name = "data";
                  mountPath = "/ghost/data";
                }];
              };
            };
          };
          volumeClaimTemplates = [{
            metadata.name = "data";
            spec = {
              accessModes = ["ReadWriteOnce"];
              resources.requests.storage = "5G";
            };
          }];
        };
      };

      kubernetes.resources.podDisruptionBudgets.ghost = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec.minAvailable = 1;
        spec.selector.matchLabels.app = module.name;
      };

      kubernetes.resources.services.ghost = {
        metadata.name = module.name;
        metadata.labels.app = module.name;

        spec.selector.app = module.name;

        spec.ports = [{
          name = "http";
          port = 80;
          targetPort = 2368;
        }];
      };
    };
  };
}
