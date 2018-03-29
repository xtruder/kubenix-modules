{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.nginx.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Name of the nginx image to use";
        type = types.str;
        default = "nginx";
      };

      replicas = mkOption {
        description = "Number of nginx replicas";
        type = types.int;
        default = 1;
      };

      configuration = mkOption {
        description = "Nginx configuration";
        type = types.nullOr types.lines;
        default = null;
      };
    };

    config = {
      kubernetes.resources.deployments.nginx = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          replicas = config.replicas;
          selector.matchLabels.app = name;
          template = {
            metadata.labels.app = name;
            spec = {
              containers.nginx = {
                image = config.image;
                ports = [{
                  name = "http";
                  containerPort = 80;
                } {
                  name = "https";
                  containerPort = 443;
                }];

                resources.requests = {
                  cpu = "100m";
                  memory = "50Mi";
                };

                volumeMounts = mkIf (config.configuration != null) [{
                  name = "config";
                  mountPath = "/etc/nginx/nginx.conf";
                  subPath = "nginx.conf";
                }];
              };
              volumes = mkIf (config.configuration != null) {
                config.configMap.name = name;
              };
            };
          };
        };
      };

      kubernetes.resources.configMaps = mkIf (config.configuration != null) {
        nginx = {
          metadata.name = name;
          data."nginx.conf" = config.configuration;
        };
      };

      kubernetes.resources.services.nginx = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          ports = [{
            name = "http";
            port = 80;
          } {
            name = "https";
            port = 443;
          }];
          selector.app = name;
        };
      };
    };
  };
}
