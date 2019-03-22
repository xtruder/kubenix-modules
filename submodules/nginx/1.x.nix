{ config, lib, pkgs, name, kubenix, k8s, ...}:

with lib;
with k8s;

let
  cfg = config.submodule.args;

  image = pkgs.dockerTools.buildLayeredImage {
    name = "nginx";
    contents = [ pkgs.nginx ];
    extraCommands = ''
      mkdir etc
      chmod u+w etc
      echo "nginx:x:1000:1000::/:" > etc/passwd
      echo "nginx:x:1000:nginx" > etc/group
    '';
    config = {
      Cmd = ["nginx" "-c" "/etc/nginx/nginx.conf"];
      ExposedPorts = {
        "80/tcp" = {};
        "443/tcp" = {};
      };
    };
  };
in {
  imports = [
    kubenix.modules.submodule
    kubenix.modules.k8s
    kubenix.modules.docker
  ];

  options.submodule.args = {
    replicas = mkOption {
      description = "Number of nginx replicas";
      type = types.int;
      default = 1;
    };

    configuration = mkOption {
      description = "Nginx configuration";
      type = types.lines;
      default = ''
        user nginx nginx;
        daemon off;
        error_log /dev/stderr info;
        pid /dev/null;

		events {
		  worker_connections  1024;
		}

		http {
		  server {
			listen       80;

			access_log /dev/stdout;

            index index.html;

            location / {
              root /html;
            }

			location /status {
			  stub_status on;
			}
		  }
		}
      '';
    };
  };

  config = {
    submodule = {
      name = "nginx";
      version = "1.0.0";
      description = "";
    };

    docker.images.nginx.image = image;

    kubernetes.api.deployments.nginx = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        replicas = cfg.replicas;
        selector.matchLabels.app = name;
        template = {
          metadata.labels.app = name;
          spec = {
            serviceAccountName = name;
            containers.nginx = {
              image = config.docker.images.nginx.path;
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

              volumeMounts = [{
                name = "config";
                mountPath = "/etc/nginx";
              }];
            };
            volumes.config.configMap.name = name;
          };
        };
      };
    };

    kubernetes.api.serviceaccounts.nginx = {
      metadata.name = name;
      metadata.labels.app = name;
    };

    kubernetes.api.configmaps = {
      nginx = {
        metadata.name = name;
        data."nginx.conf" = cfg.configuration;
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
