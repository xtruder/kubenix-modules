{ config, lib, k8s, ... }:

with lib;
with k8s;

{
  config.kubernetes.moduleDefinitions.projectsend.module = {module, config, ...}: {
    options = {
      image = mkOption {
        description = "Docker image to use";
        type = types.str;
        default = "linuxserver/projectsend";
      };

      replicas = mkOption {
        description = "Number of projectsend replicas to run";
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
          default = "projectsend";
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
      kubernetes.resources.statefulSets.projectsend = {
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

              containers.projectsend = {
                image = config.image;
                # env.DB_NAME = config.database.name;
                # env.DB_HOST = config.database.host; 
                # env.DB_USER = secretToEnv config.database.username;
                # env.DB_PASS = secretToEnv config.database.password;

                

                ports = [{
                  containerPort = 80;
                }];
                volumeMounts = [{
                  name = "data";
                  mountPath = "/projectsend/data";
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

      kubernetes.resources.podDisruptionBudgets.projectsend = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec.minAvailable = 1;
        spec.selector.matchLabels.app = module.name;
      };

      kubernetes.resources.services.projectsend = {
        metadata.name = module.name;
        metadata.labels.app = module.name;

        spec.selector.app = module.name;

        spec.ports = [{
          name = "http";
          port = 80;
          targetPort = 80;
        }];
      };
    };
  };
}
