{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

{
  imports = [
    kubenix.k8s
  ];

  options.args = {
    outputConfig = mkOption {
      description = "Logstash output config";
      type = types.lines;
    };

    filterConfig = mkOption {
      description = "Extra filter config";
      type = types.lines;
      default = "";
    };
  };

  config = {
    submodule = {
      name = "kubelog";
      version = "1.0.0";
      description = "";
    };
    kubernetes.modules.logstash = {
      name = "${name}-logstash";
      module = "logstash";
      namespace = module.namespace;

      configuration = {
        image = "gatehub/logstash";
        kind = "daemonSet";

        kubernetes.api.daemonsets.logstash = {
          spec.template.spec = {
            containers.logstash.volumeMounts = [{
              name = "log-containers";
              mountPath = "/var/log/containers";
            } {
              name = "log-pods";
              mountPath = "/var/log/pods";
            } {
              name = "docker-containers";
              mountPath = "/var/lib/docker/containers";
            } {
              name = "data";
              mountPath = "/data";
            }];

            volumes = [{
              name = "log-containers";
              hostPath = {
                path = "/var/log/containers";
              };
            } {
              name = "log-pods";
              hostPath = {
                path = "/var/log/pods";
              };
            } {
              name = "docker-containers";
              hostPath = {
                path = "/var/lib/docker/containers";
              };
            } {
              name = "data";
              hostPath = {
                path = "/var/log/kubernetes/logstash";
              };
            }];
          };
        };


        configuration = ''
        input {
          file {
            path => "/var/log/containers/*.log"
            sincedb_path => "/data/sincedb"
          }
        }

        filter {
          date {
            match => [ "time", "ISO8601"  ]
            remove_field => ["time"]
          }

          kubernetes {}

          if [kubernetes][container_name] == "logstash" {
            drop { }
          }

          json {
            source => "message"
            target => "data"
          }

          json {
            source => "[data][log]"
            target => "data"
          }

          ${config.filterConfig}
        }

        output {
          ${config.outputConfig}
        }
        '';
      };
    };
  };
}