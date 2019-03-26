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

    #   mongodbUri = mkOption {
    #     description = "URI for mongodb database";
    #     type = types.str;
    #     default = "mongodb://mongo/ghost";
    #   };

      extraPorts = mkOption {
        description = "Extra ports to expose";
        type = types.listOf types.int;
        default = [];
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
                env.url.value= "http://ghost.staging.gatehub.net";
                # env.NODE_ENV.value = "production";
                # env.MYSQL_CLIENT.value = config.database.type;
                # env.MYSQL_DATABASE.value = config.database.name;
                # env.MYSQL_PASSWORD = secretToEnv config.database.password;
                # env.MYSQL_HOST.value = config.database.host;
                # env.MYSQL_USER = secretToEnv config.database.username;
                # env.GHOST_INSTALL.value = "/var/lib/ghost";
                env.GHOST_INSTALL.value = "/ghost/data";
                # env.GHOST_CONTENT.value = "/ghost/data/content";

                env.database__client.value = config.database.type;
                env.database__connection__database.value = config.database.name;
                env.database__connection__password = secretToEnv config.database.password;
                env.database__connection__host.value = config.database.host;
                env.database__connection__user = secretToEnv config.database.username;
                

                env.mail__transport.value = "SMTP";
                env.mail__options__service.value = "Mailgun";
                env.mail__options__auth__user.value = "ghost@gatehub.net";
                env.mail__options__auth__pass.value = "QMcRQX5kMeO34YosDthZ";

                securityContext.capabilities.add = ["NET_ADMIN"];

                ports = [{
                  containerPort = 2368;
                } ] ++ map (port: {containerPort = port;}) config.extraPorts;
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
              resources.requests.storage = "1G";
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
        }] ++ map (port: {
          name = "${toString port}";
          port = port;
          targetPort = port;
        }) config.extraPorts;
      };
    };
  };
}
