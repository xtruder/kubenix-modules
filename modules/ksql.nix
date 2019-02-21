{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

{
  imports = [
    kubenix.k8s
  ];

  options.args = {
    image = mkOption {
      description = "Ksql image to use";
      type = types.str;
      default = config.args.kubernetes.dockerRegistry + "/${images.ksql.image.fullName}";
    };

    replicas = mkOption {
      description = "Number of ksql replicas to run";
      type = types.int;
      default = 3;
    };

    bootstrap = {
      servers = mkOption {
        description = "Kafka bootstrap servers";
        type = types.listOf types.str;
        default = ["kafka-0.kafka:9093" "kafka-1.kafka:9093" "kafka-2.kafka:9093"];
      };
    };

    opts = mkOption {
      description = "Kafka options";
      type = types.attrs;
    };
  };

  config = {
    submodule = {
      name = "ksql";
      version = "1.0.0";
      description = "";
    };
    opts = {
      "bootstrap.servers" = concatStringsSep "," config.args.bootstrap.servers;
      listeners = "PLAINTEXT://0.0.0.0.${name}:8088";
      "ui.enabled" = true;
      "ksql.streams.replication.factor" = 3;
      "ksql.sink.replicas" = 3;
      "ksql.streams.state.dir" = "/data";
    };

    kubernetes.api.statefulsets.ksql = {
      spec = {
        serviceName = name;
        replicas = config.args.replicas;
        podManagementPolicy = "Parallel";
        template = {
          metadata.labels.app = name;
          spec = {
            containers.ksql = {
              image = config.args.image;
              imagePullPolicy = "Always";
              resources.requests = {
                memory = "1Gi";
                cpu = "500m";
              };
              ports = [{
                containerPort = 8088;
                name = "server";
              }];
              command = ["/bin/ksql-server-start" "/etc/ksql/ksql-server.properties"];
              env = {
                JMX_PORT.value = "1099"; # expose metrics
                KSQL_OPTS = concatStringsSep " " (mapAttrsToList (name: value:
                  "-D${name}=${
                    if isBool value then
                    if value then "true" else "false"
                    else toString value
                  }"
                ) config.opts); # define options
              };
              volumeMounts = [{
                name = "datadir";
                mountPath = "/data";
              }];
            };
          };
        };
        volumeClaimTemplates = [{
          metadata.name = "datadir";
          spec = {
            accessModes = ["ReadWriteOnce"];
            resources.requests.storage = "10Gi";
          };
        }];
      };
    };

    kubernetes.api.services.ksql = {
      metadata.name = name;
      metadata.labels.app = name;

      spec = {
        clusterIP = "None";
        ports = [{
          port = 8088;
          name = "server";
        }];
        selector.app = name;
      };
    };
  };
}