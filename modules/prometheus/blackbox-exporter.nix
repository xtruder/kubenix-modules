{ config, lib, k8s, pkgs, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.prometheus-blackbox-exporter.module = {config, module, ...}: {
    options = {
      image = mkOption {
        description = "Prometheus blackbox exporter image to use";
        type = types.str;
        default = "prom/blackbox-exporter:v0.12.0";
      };

      replicas = mkOption {
        description = "Number of prometheus blackbox exporter replicas to run";
        type = types.int;
        default = 1;
      };

      extraArgs = mkOption {
        description = "Prometheus blackbox exporter server additional args";
        default = [];
        type = types.listOf types.str;
      };

      configuration = mkOption {
        description = "Prometheus blackbox exporter configuration";
        type = mkOptionType {
          name = "deepAttrs";
          description = "deep attribute set";
          check = isAttrs;
          merge = loc: foldl' (res: def: recursiveUpdate res def.value) {};
        };
        default = {};
      };
    };

    config = {
      # default blackbox exporter configuration
      configuration.modules.http_2xx = {
        prober = "http";
        timeout = "5s";
        http = {
          valid_http_versions = ["HTTP/1.1" "HTTP/2"];
          no_follow_redirects = false;
          preferred_ip_protocol = "ip4";
        };
      };

      kubernetes.resources.deployments.prometheus-blackbox-exporter = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          selector.matchLabels.app = module.name;
          template = {
            metadata.labels.app = module.name;
            spec = {
              containers.blackbox-exporter = {
                image = config.image;
                imagePullPolicy = "IfNotPresent";
                args = ["--config.file=/config/blackbox.yaml"] ++ config.extraArgs;
                resources = {
                  limits.memory = "300Mi";
                  requests.memory = "50Mi";
                };
                ports = [{
                  name = "http";
                  containerPort = 9115;
                }];
                securityContext = {
                  runAsNonRoot = true;
                  runAsUser = 1000;
                  readOnlyRootFilesystem = true;
                };
                livenessProbe.httpGet = {
                  path = "/health";
                  port = "http";
                };
                readinessProbe.httpGet = {
                  path = "/health";
                  port = "http";
                };
                volumeMounts = [{
                  mountPath = "/config";
                  name = "config";
                }];
              };

              # reloads blackbox exporter on config changes
              containers.configmap-reload = {
                image = "jimmidyson/configmap-reload:v0.2.2";
                imagePullPolicy = "IfNotPresent";
                args = [
                  "--volume-dir=/config"
                  "--webhook-url=http://localhost:9115/-/reload"
                ];
                volumeMounts = [{
                  mountPath = "/config";
                  name = "config";
                }];
              };
              volumes.config.configMap.name = module.name;
            };
          };
        };
      };

      kubernetes.resources.configMaps.prometheus-blackbox-exporter = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        data."blackbox.yaml" = toYAML config.configuration;
      };

      kubernetes.resources.services.prometheus-blackbox-exporter = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          ports = [{
            name = "http";
            port = 9115;
            protocol = "TCP";
          }];
          selector.app = module.name;
        };
      };
    };
  };
}
