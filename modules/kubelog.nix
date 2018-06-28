{ name, lib, config, k8s, pkgs, ... }:

with k8s;
with lib;

{
  imports = [./logstash.nix];

  config.kubernetes.moduleDefinitions.kubelog.module = {name, module, config, ...}: {
    options = {
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
      kubernetes.modules.logstash = {
        name = "${name}-logstash";
        module = "logstash";
        namespace = module.namespace;

        configuration = {
          image = "gatehub/logstash";
          kind = "daemonSet";

          kubernetes.resources.daemonSets.logstash = {
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
  };
}
