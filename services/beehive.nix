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

                ports = [{containerPort = 8181;}];
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
        }];
      };

      kubernetes.resources.persistentVolumeClaims.beehive.spec = {
        accessModes = ["ReadWriteOnce"];
        resources.requests.storage = "1G";
      };
    };
  };
}
