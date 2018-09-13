{ config, lib, k8s, pkgs, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.prometheus-pushgateway.module = {config, module, ...}: {
    options = {
      image = mkOption {
        description = "Image to use for prometheus pushgateway";
        type = types.str;
        default = "prom/pushgateway:v0.4.0";
      };

      replicas = mkOption {
        description = "Number of prometheus gateway replicas";
        type = types.int;
        default = 1;
      };
    };

    config = {
      kubernetes.resources.deployments.prometheus-pushgateway = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          replicas = config.replicas;
          selector.matchLabels.app = module.name;
          template = {
            metadata.name = module.name;
            metadata.labels.app = module.name;
            spec = {
              containers.prometheus-pushgateway = {
                image = config.image;
                ports = [{
                  name = "prometheus-push";
                  containerPort = 9091;
                }];
                readinessProbe = {
                  httpGet = {
                    path = "/#/status";
                    port = 9091;
                  };
                  initialDelaySeconds = 10;
                  timeoutSeconds = 10;
                };
                resources = {
                  requests = {
                    memory = "128Mi";
                    cpu = "10m";
                  };
                  limits = {
                    memory = "128Mi";
                    cpu = "10m";
                  };
                };
              };
            };
          };
        };
      };

      kubernetes.resources.services.prometheus-pushgateway = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        metadata.annotations."prometheus.io/probe" = "pushgateway";
        metadata.annotations."prometheus.io/scrape" = "true";
        spec = {
          ports = [{
            name = "prometheus-push";
            port = 9091;
            targetPort = 9091;
            protocol = "TCP";
          }];
          selector.app = module.name;
        };
      };
    };
  };
}
