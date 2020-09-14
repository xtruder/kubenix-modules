{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.nix-remote-builder.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Image to use";
        type = types.str;
        default = config.kubernetes.dockerRegistry + "/${images.nix-remote-builder.imageName}:${images.nix-remote-builder.imageTag}";
      };

      replicas = mkOption {
        description = "Number of nix-remote builder replicas to run";
        type = types.int;
        default = 3;
      };

      authorizedKeys = mkOption {
        description = "List of authorized keys";
        type = types.listOf types.str;
        default = [];
      };

      sshKey = mkSecretOption {
        description = "SSH private key to use for nix remote builder";
      };

      resources = {
        requests = {
          cpu = mkOption {
            description = "Nix remote builder cpu requirements";
            default = "2000m";
            type = types.str;
          };

          memory = mkOption {
            description = "Nix remote builder memory requirements";
            default = "1Gi";
            type = types.str;
          };
        };

        limits = {
          cpu = mkOption {
            description = "Nix remote builder cpu limits";
            default = "4000m";
            type = types.str;
          };

          memory = mkOption {
            description = "Nix remote builder memory limits";
            default = "2Gi";
            type = types.str;
          };
        };
      };
    };

    config = {
      # config maps where authorized keys are stored
      kubernetes.resources.configMaps.nix-remote-builder = {
        metadata = {
          name = module.name;
        };
        data = {
          authorized_keys = concatStringsSep "\n" config.authorizedKeys;
        };
      };

      kubernetes.resources.statefulSets.nix-remote-builder = {
        spec = {
          serviceName = module.name;
          replicas = config.replicas;
          podManagementPolicy = "Parallel";
          template = {
            metadata.labels.app = module.name;
            spec = {
              containers.nix-remote-builder = {
                image = config.image;
                imagePullPolicy = "IfNotPresent";
                resources = {
                  requests = {
                    memory = config.resources.requests.memory;
                    cpu = config.resources.requests.cpu;
                  };
                  limits = {
                    memory = config.resources.limits.memory;
                    cpu = config.resources.limits.cpu;
                  };
                };
                ports = [{
                  containerPort = 22;
                  name = "ssh";
                }];
                command = [
                  "/bin/kafka-server-start" "/etc/kafka/server.properties"
                ];
                env = {
                  KAFKA_OPTS.value = "-Dlogging.level=INFO";
                  KAFKA_JMX_OPTS.value = "-Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false";
                  JMX_PORT.value = "9999";
                };
                volumeMounts = [{
                  name = "config";
                  mountPath = "/etc/kafka/log4j.properties";
                  subPath = "log4j.properties";
                } {
                  name = "share";
                  mountPath = "/etc/kafka/server.properties";
                  subPath = "server.properties";
                } {
                  name = "datadir";
                  mountPath = "/data";
                }];
              };
              volumes.config.configMap.name = module.name;
              volumes.share.emptyDir = {};
            };
          };
          volumeClaimTemplates = [{
            metadata.name = "datadir";
            spec = {
              accessModes = ["ReadWriteOnce"];
              resources.requests.storage = "10Gi";
            };
          }];
        };
      };


    };
  };
}
