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
      default = "jippi/pritunl";
    };

    replicas = mkOption {
      description = "Number of pritunl replicas to run";
      type = types.int;
      default = 1;
    };

    mongodbUri = mkOption {
      description = "URI for mongodb database";
      type = types.str;
      default = "mongodb://mongo/pritunl";
    };

    extraPorts = mkOption {
      description = "Extra ports to expose";
      type = types.listOf types.int;
      default = [];
    };
  };

  config = {
    submodule = {
      name = "pritunl";
      version = "1.0.0";
      description = "";
    };
    kubernetes.api.statefulsets.pritunl = {
      metadata = {
        name = name;
        labels.app = name;
      };
      spec = {
        serviceName = name;
        replicas = config.args.replicas;
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

            containers.pritunl = {
              image = config.args.image;
              env.PRITUNL_MONGODB_URI.value = config.args.mongodbUri;

              securityContext.capabilities.add = ["NET_ADMIN"];

              ports = [{
                containerPort = 80;
              } {
                containerPort = 443;
              } {
                containerPort = 1194;
              }] ++ map (port: {containerPort = port;}) config.args.extraPorts;
              volumeMounts = [{
                name = "workdir";
                mountPath = "/var/lib/pritunl";
              }];
            };
          };
        };
        volumeClaimTemplates = [{
          metadata.name = "workdir";
          spec = {
            accessModes = ["ReadWriteOnce"];
            resources.requests.storage = "1G";
          };
        }];
      };
    };

    kubernetes.api.poddisruptionbudgets.pritunl = {
      metadata.name = name;
      metadata.labels.app = name;
      spec.minAvailable = 1;
      spec.selector.matchLabels.app = name;
    };

    kubernetes.api.services.pritunl = {
      metadata.name = name;
      metadata.labels.app = name;

      spec.selector.app = name;

      spec.ports = [{
        name = "http";
        port = 80;
        targetPort = 80;
      } {
        name = "https";
        port = 443;
        targetPort = 443;
      } {
        name = "vpn";
        port = 1194;
        targetPort = 1194;
      }] ++ map (port: {
        name = "${toString port}";
        port = port;
        targetPort = port;
      }) config.extraPorts;
    }; 
  };
}