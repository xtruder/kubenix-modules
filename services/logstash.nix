{ config, lib, k8s, ... }:

with lib;
with k8s;

{
  kubernetes.moduleDefinitions.logstash.module = { name, module, config, ... }: {
    options = {
      image = mkOption {
        description = "Logstash image to use";
        type = types.str;
        default = "logstash";
      };

      configuration = mkOption {
        description = "Logstash configuration file content";
        type = types.lines;
      };

      kind = mkOption {
        description = "Kind of ";
        default = "deployment";
        type = types.enum ["deployment" "daemonSet"];
      };
    };

    config = {
      kubernetes.resources."${config.kind}s".logstash = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          selector.matchLabels.app = name;
          template = {
            metadata.name = name;
            metadata.labels.app = name;
            spec = {
              containers.logstash = {
                image = config.image;
                command = [
                  "logstash" "-f" "/config/logstash.conf"
                  "--config.reload.automatic"
                ];
                resources = {
                  requests.memory = "512Mi";
                  limits.memory = "1024Mi";
                };
                volumeMounts.config = {
                  name = "config";
                  mountPath = "/config";
                };
              };
              volumes.config = {
                configMap.name = name;
              };
            };
          } // optionalAttrs (config.kind != "daemonSet") {
            spec.replicas = 1;
          };
        };
      };

      kubernetes.resources.configMaps.logstash = {
        metadata.name = name;
        metadata.labels.app = name;
        data."logstash.conf" = config.configuration;
      };
    };
  };
}
