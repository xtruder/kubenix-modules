{ config, lib, k8s, ... }:

with lib;

{
  config.kubernetes.moduleDefinitions.pritunl.module = {module, config, ...}: {
    options = {
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

      enableIpForwarding = mkOption {
        description = "Whether to explicitly enable ip forwarding using init container";
        type = types.bool;
        default = true;
      };

      extraPorts = mkOption {
        description = "Extra ports to expose";
        type = types.listOf types.int;
        default = [];
      };
    };

    config = {
      kubernetes.resources.statefulSets.pritunl = {
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

              initContainers = mkIf config.enableIpForwarding [{
                name = "enable-ip-forward";
                image = "busybox";
                command = ["sh" "-c" "echo 1 > /proc/sys/net/ipv4/ip_forward"];
                securityContext.privileged = true;
              }];

              containers.pritunl = {
                image = config.image;
                env.PRITUNL_MONGODB_URI.value = config.mongodbUri;

                securityContext.capabilities.add = ["NET_ADMIN"];

                ports = [{
                  containerPort = 80;
                } {
                  containerPort = 443;
                } {
                  containerPort = 1194;
                }] ++ map (port: {containerPort = port;}) config.extraPorts;
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

      kubernetes.resources.podDisruptionBudgets.pritunl = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec.minAvailable = 1;
        spec.selector.matchLabels.app = module.name;
      };

      kubernetes.resources.services.pritunl = {
        metadata.name = module.name;
        metadata.labels.app = module.name;

        spec.selector.app = module.name;

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
  };
}
