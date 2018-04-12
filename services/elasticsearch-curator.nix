{ config, lib, k8s, pkgs, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.elasticsearch-curator.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Elasticsearc image";
        type = types.str;
        default = "bobrik/curator:5.4.0";
      };

      hosts = mkOption {
        description = "Elasticsearch hosts";
        default = ["elasticsearch"];
        type = types.listOf types.str;
      };

      port = mkOption {
        description = "Elasticsearch port";
        default = 9200;
        type = types.int;
      };

      ssl = mkOption {
        description = "Whether currator should use ssl or not";
        default = false;
        type = types.bool;
      };

      username = mkOption {
        description = "Simple auth username";
        default = null;
        type = types.nullOr types.str;
      };

      password = mkOption {
        description = "Simple auth password";
        default = null;
        type = types.nullOr types.str;
      };

      aws = {
        key = mkOption {
          description = "Aws key";
          type = types.nullOr types.str;
          default = null;
        };

        secretKey = mkOption {
          description = "Aws secret key";
          type = types.nullOr types.str;
          default = null;
        };

        region = mkOption {
          description = "Aws region";
          type = types.nullOr types.str;
          default = null;
        };
      };

      schedule = mkOption {
        description = "Curator job schedule";
        type = types.str;
        default = "* * * * *";
      };

      actions = mkOption {
        description = "List of actions to run";
        type = types.listOf types.attrs;
      };
    };

    config = {
      kubernetes.resources.cronJobs.elasticsearch-curator = {
        metadata.name = name;
        spec = {
          concurrencyPolicy = "Forbid";
          schedule = config.schedule;
          jobTemplate = {
            spec.template = {
              spec = {
                containers.curator = {
                  image = config.image;
                  args = ["--config" "/etc/curator/config.yaml" "/etc/curator/actions.yaml"];
                  volumeMounts = [{
                    name = "config";
                    mountPath = "/etc/curator";
                  }];
                  resources = {
                    requests.memory = "256Mi";
                    requests.cpu = "50m";
                    limits.memory = "512Mi";
                    limits.cpu = "50m";
                  };
                };
                restartPolicy = "OnFailure";
                volumes.config.configMap.name = name;
              };
            };
          };
        };
      };

      kubernetes.resources.configMaps.curator = {
        metadata.name = name;
        data."config.yaml" = toYAML {
          client = {
            inherit (config) hosts port;
            use_ssl = config.ssl;
            aws_key = config.aws.key;
            aws_secret_key = config.aws.secretKey;
            aws_region = config.aws.region;
          } // (optionalAttrs (config.username != null && config.password != null) {
            http_auth = "${config.username}:${config.password}";
          });
          logging = {
            loglevel = "INFO";
            logformat = "json";
          };
        };
        data."actions.yaml" = toYAML {
          actions = listToAttrs (imap (i: action:
          nameValuePair (toString i) action
          ) config.actions);
        };
      };
    };
  };
}
