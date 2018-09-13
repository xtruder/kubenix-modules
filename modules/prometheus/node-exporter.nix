{ config, lib, k8s, pkgs, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.prometheus-node-exporter.module = {config, module, ...}: {
    options = {
      image = mkOption {
        description = "Prometheus node export image to use";
        type = types.str;
        default = "prom/node-exporter:v0.15.2";
      };

      ignoredMountPoints = mkOption {
        description = "Regex for ignored mount points";
        type = types.str;

        # this is ugly negative regex that ignores everyting except /host/.*
        default = "^/(([h][^o]?(/.+)?)|([h][o][^s]?(/.+)?)|([h][o][s][^t]?(/.+)?)|([^h]?[^o]?[^s]?[^t]?(/.+)?)|([^h][^o][^s][^t](/.+)?))$";
      };

      ignoredFsTypes = mkOption {
        description = "Regex of ignored filesystem types";
        type = types.str;
        default = "^(proc|sys|cgroup|securityfs|debugfs|autofs|tmpfs|sysfs|binfmt_misc|devpts|overlay|mqueue|nsfs|ramfs|hugetlbfs|pstore)$";
      };

      extraPaths = mkOption {
        description = "Extra node-exporter host paths";
        default = {};
        type = types.attrsOf (types.submodule ({name, config, ...}: {
          options = {
            hostPath = mkOption {
              description = "Host path to mount";
              type = types.path;
            };

            mountPath = mkOption {
              description = "Path where to mount";
              type = types.path;
              default = "/host/${name}";
            };
          };
        }));
      };

      extraArgs = mkOption {
        description = "Prometheus node exporter extra arguments";
        type = types.listOf types.str;
        default = [];
      };
    };

    config = {
      kubernetes.resources.daemonSets.prometheus-node-exporter = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          selector.matchLabels.app = module.name;
          template = {
            metadata.name = module.name;
            metadata.labels.app = module.name;
            metadata.annotations."prometheus.io/scrape" = "true";
            spec = {
              containers.node-exporter = {
                image = config.image;
                args = [
                  "--path.procfs=/host/proc"
                  "--path.sysfs=/host/sys"
                  "--collector.filesystem.ignored-mount-points=${config.ignoredMountPoints}"
                  "--collector.filesystem.ignored-fs-types=${config.ignoredFsTypes}"
                ] ++ config.extraArgs;
                ports = [{
                  name = "metrics";
                  containerPort = 9100;
                }];
                livenessProbe = {
                  httpGet = {
                    path = "/metrics";
                    port = 9100;
                  };
                  initialDelaySeconds = 30;
                  timeoutSeconds = 15;
                };
                volumeMounts = [{
                  name = "proc";
                  mountPath = "/host/proc";
                  readOnly = true;
                } {
                  name = "sys";
                  mountPath = "/host/sys";
                  readOnly = true;
                }] ++ (mapAttrsToList (name: path: {
                  inherit name;
                  inherit (path) mountPath;
                  readOnly = true;
                }) config.extraPaths);
              };
              hostPID = true;
              volumes = {
                proc.hostPath.path = "/proc";
                sys.hostPath.path = "/sys";
              }// (mapAttrs (name: path: {
                hostPath.path = path.hostPath;
              }) config.extraPaths);
            };
          };
        };
      };

      kubernetes.resources.services.prometheus-node-exporter = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          ports = [{
            name = "node-exporter";
            port = 9100;
            targetPort = 9100;
            protocol = "TCP";
          }];
          selector.app = module.name;
        };
      };
    };
  };
}
