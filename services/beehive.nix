{ config, lib, k8s, ... }:

with lib;

{
  config.kubernetes.moduleDefinitions.beehive.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Docker image to use";
        type = types.str;
        default = "xtruder/beehive";
      };

      extraPorts = mkOption {
        description = "Extra beehive exposed TCP ports";
        example = [65000];
        type = types.listOf types.int;
        default = [];
      };
    };

    config = {
      kubernetes.resources.deployments.beehive = {
        metadata = {
          name = name;
          labels.app = name;
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = name;
          template = {
            metadata = {
              labels.app = name;
            };
            spec = {
              containers.beehive = {
                image = config.image;

                volumeMounts = [{
                  name = "config";
                  mountPath = "/conf";
                }];

                ports = [{
                  containerPort = 8181;
                }] ++ map (port: {containerPort = port;}) config.extraPorts;
              };

              volumes.config.persistentVolumeClaim.claimName = name;
            };
          };
        };
      };

      kubernetes.resources.services.beehive = {
        metadata.name = name;
        metadata.labels.app = name;

        spec.selector.app = name;

        spec.ports = [{
          name = "http";
          port = 80;
          targetPort = 8181;
        }] ++ map (port: {
          name = "${toString port}";
          port = port;
          targetPort = port;
        }) config.extraPorts;
      };

      kubernetes.resources.persistentVolumeClaims.beehive.spec = {
        accessModes = ["ReadWriteOnce"];
        resources.requests.storage = "1G";
      };
    };
  };
}
