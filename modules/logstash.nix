{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

{
  imports = [
    kubenix.k8s
  ];

  options.args = {
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
    submodule = {
      name = "logstash";
      version = "1.0.0";
      description = "";
    };
    kubernetes.api."${config.kind}s".logstash = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        selector.matchLabels.app = name;
        template = {
          metadata.name = name;
          metadata.labels.app = name;
          spec = {
            containers.logstash = {
              image = config.args.image;
              command = [
                "logstash" "-f" "/config/logstash.conf"
                "--config.args.reload.automatic"
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
        }; 
      } // optionalAttrs (config.kind != "daemonSet") {
        replicas = 1;
      };
    };

    kubernetes.api.configmaps.logstash = {
      metadata.name = name;
      metadata.labels.app = name;
      data."logstash.conf" = config.args.configuration;
    };
  };
}