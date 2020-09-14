{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.filebeat.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Name of the filebeat image to use";
        type = types.str;
        default = "docker.elastic.co/beats/filebeat:7.0.0-alpha1";
      };

      namespace = mkOption {
        description = "Name of the namespace where to deploy filebeat";
        type = types.str;
        default = "kube-system";
      };

      replicas = mkOption {
        description = "Number of nginx replicas";
        type = types.int;
        default = 3;
      };

      filebeatConfig = mkOption {
        description = "Filebeat configuration";
        type = mkOptionType {
          name = "deepAttrs";
          description = "deep attribute set";
          check = isAttrs;
          merge = loc: foldl' (res: def: recursiveUpdate res def.value) {};
        };
      };

      filebeatProspectors = mkOption {
        description = "Filebeat prospectors configuration";
        type = types.attrsOf types.attrs;
        default = {};
        example = {
          kubernetes = [{
            type = "log";
            path = ["/var/lib/docker/containers/*/*.log"];
            "json.message_key" = "log";
            "json.keys_uder_root" = true;
            processors = [{
              add_kubernetes_metdata = {
                in_cluster = true;
                namespace = "$${POD_NAMESPACE}";
              };
            }];
          }];
        };
      };
    };

    config = {
      filebeatConfig = {
        "filebeat.config" = {
          prospectors = {
            path = "${path.config}/prospectors.d/*.yml";
            "reload.enable" = true;
          };
          modules = {
            path = "${path.config}/modules.d/*.yml";
            "reload.enable" = false;
          };
        };
      };

      kubernetes.resources.daemonSets.filebeat = {
        metadata.name = name;
        metadata.labels.app = "filebeat";
        spec = {
          template = {
            metadata.labels.app = "filebeat";
            spec = {
              containers.filebeat = {
                image = config.image;

                resources.requests = {
                  cpu = "100m";
                  memory = "50Mi";
                };

                volumeMounts = [{
                  name = "config";
                  mountPath = "/etc/filebeat.yml";
                  readOnly = true;
                  subPath = "filebeat.yml";
                } {
                  name = "prospectors";
                  mountPath = "/usr/share/filebeat/prospectors.d";
                  readOnly = true;
                }];
              };
              volumes.config.configMap = {
                defaultMode = "0600";
                name = "${name}-config";
              };
              volumes.prospectors.configMap = {
                defaultMode = "0600";
                name = "${name}-prospectors";
              };
              volumes.data.emptyDir = {};
            };
          };
        };
      };

      kubernetes.resources.configMaps = {
        filebeat-config = {
          metadata.name = "${name}-config";
          data."filebeat.yml" = toYAML config.filebeatConfig;
        };
        filebeat-prospectors = {
          metadata.name = "${name}-prospectors";
          data = mapAttrs' (name: config:
            nameValuePair "${name}.yml" (toYAML config)
          ) config.filebeatProspectors;
        };
      };

      kubernetes.clusterRoles.filebeat = {
        metadata.name = "filebeat";
        subjects = [{
          kind = "ServiceAccount";
          name = "filebeat";
          namespace = config.namespace;
        }];
        roleRef = {
          kind = "ClusterRole";
          name = "filebeat";
          apiGroup = "rbac.authorization.k8s.io";
        };
      };

      kubernetes.clusterRoleBindings.filebeat = {
        metadata.name = "filebeat";
        labels.app = "filebeat";
        rules = [{
          apiGroups = [""];
          resources = ["namespaces" "pods"];
          verbs = ["get" "watch" "list"];
        }];
      };

      kubernetes.serviceAccounts.filebeat = {
        metadata.name = "filebeat";
        namespace = config.namespace;
        labels.app = "filebeat";
      };
    };
  };
}
