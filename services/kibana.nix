{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.kibana.module = {name, config, ...}: let
    scheme = if config.elasticsearch.ssl then "https" else "http";

    url =
      if (config.elasticsearch.username!=null && config.elasticsearch.password!=null)
      then
        "${scheme}://${config.elasticsearch.username}:${config.elasticsearch.password}@${config.elasticsearch.host}:${toString config.elasticsearch.port}"
      else
        "${scheme}://${config.elasticsearch.host}:${toString config.elasticsearch.port}";
  in {
    options = {
      image = mkOption {
        description = "Name of the kibana image to use";
        type = types.str;
        default = "docker.elastic.co/kibana/kibana-oss:6.0.1";
      };

      replicas = mkOption {
        description = "Number of kibana replicas";
        type = types.int;
        default = 1;
      };

      elasticsearch = {
        host = mkOption {
          description = "Elasticsearch url";
          default = "elasticsearch";
          type = types.str;
        };

        port = mkOption {
          description = "Elasticsearch port";
          default = 9200;
          type = types.int;
        };

        ssl = mkOption {
          description = "Enable Elasticsearch https";
          default = false;
          type = types.bool;
        };

        username = mkOption {
          description = "Elasticsearch username";
          type = types.nullOr types.str;
          default = null;
        };

        password = mkOption {
          description = "Elasticsearch password";
          type = types.nullOr types.str;
          default = null;
        };
      };
    };

    config = {
      kubernetes.resources.deployments.kibana = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          replicas = config.replicas;
          template = {
            metadata.labels.app = name;
            spec = {
              containers.kibana = {
                image = config.image;
                command = ["/usr/share/kibana/bin/kibana" "-e" "${url}"];
                ports = [{ containerPort = 5601; }];

                resources.requests.memory = "256Mi";
                resources.limits.memory = "256Mi";
              };
            };
          };
        };
      };

      kubernetes.resources.services.kibana = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          ports = [{
            name = "http";
            port = 80;
            targetPort = 5601;
          }];
          selector.app = name;
        };
      };
    };
  };
}
