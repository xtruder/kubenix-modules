{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

{
  imports = [
    kubenix.k8s
  ];

  options.args = {
    image = mkOption {
      description = "Docker image to use";
      type = types.str;
      default = "xtruder/beehive";
    };

    url = mkOption {
      description = "Beehive url where frontend is exposed";
      type = types.str;
      default = "http://beehive";
    };

    extraPorts = mkOption {
      description = "Extra beehive exposed TCP ports";
      example = [65000];
      type = types.listOf types.int;
      default = [];
    };
  };

  config = {
    submodule = {
      name = "beehive";
      version = "1.0.0";
      description = "";
    };
    kubernetes.api.deployments.beehive = {
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
              image = config.args.image;

              args = ["beehive" "-canonicalurl" config.args.url];

              volumeMounts = [{
                name = "config";
                mountPath = "/conf";
              }];

              ports = [{
                containerPort = 8181;
              }] ++ map (port: {containerPort = port;}) config.args.extraPorts;
            };

            volumes.config.persistentVolumeClaim.claimName = name;
          };
        };
      };
    };

    kubernetes.api.services.beehive = {
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
      }) config.args.extraPorts;
    };

    kubernetes.api.persistentvolumeclaims.beehive.spec = {
      accessModes = ["ReadWriteOnce"];
      resources.requests.storage = "1G";
    };
  };
}