{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

{
  imports = [
    kubenix.k8s
  ];

  options.args = {
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
    submodule = {
      name = "elasticsearch-curator";
      version = "1.0.0";
      description = "";
    };
    kubernetes.api.cronjobs.elasticsearch-curator = {
      metadata.name = name;
      spec = {
        concurrencyPolicy = "Forbid";
        schedule = config.args.schedule;
        jobTemplate = {
          spec.template = {
            spec = {
              containers.curator = {
                image = config.args.image;
                args = ["--config" "/etc/curator/config.args.yaml" "/etc/curator/actions.yaml"];
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

    kubernetes.api.configmaps.curator = {
      metadata.name = name;
      data."config.yaml" = toYAML {
        client = {
          inherit (config) hosts port;
          use_ssl = config.args.ssl;
          aws_key = config.args.aws.key;
          aws_secret_key = config.args.aws.secretKey;
          aws_region = config.args.aws.region;
        } // (optionalAttrs (config.args.username != null && config.args.password != null) {
          http_auth = "${config.args.username}:${config.args.password}";
        });
        logging = {
          loglevel = "INFO";
          logformat = "json";
        };
      };
      data."actions.yaml" = toYAML {
        actions = listToAttrs (imap (i: action:
        nameValuePair (toString i) action
        ) config.args.actions);
      };
    };
  };
}