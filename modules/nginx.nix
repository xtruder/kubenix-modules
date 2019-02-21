{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

{
  imports = [
    kubenix.k8s
  ];

  options.args = {
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
    }
  };

  config = {
    submodule = {
      name = "nginx";
      version = "1.0.0";
      description = "";
    };
    kubernetes.api.deployments.nginx = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        replicas = config.args.replicas;
        selector.matchLabels.app = name;
        template = {
          metadata.labels.app = name;
          spec = {
            serviceAccountName = name;
            containers.nginx = {
              image = config.args.image;
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

              volumeMounts = mkIf (config.args.configuration != null) [{
                name = "config";
                mountPath = "/etc/nginx/nginx.conf";
                subPath = "nginx.conf";
              }];
            };
            volumes = mkIf (config.args.configuration != null) {
              config.args.configMap.name = name;
            };
          };
        };
      };
    };

    kubernetes.api.serviceaccounts.nginx = {
      metadata.name = name;
      metadata.labels.app = name;
    };

    kubernetes.api.configmaps = mkIf (config.args.configuration != null) {
      nginx = {
        metadata.name = name;
        data."nginx.conf" = config.args.configuration;
      };
    };

    kubernetes.api.services.nginx = {
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
}