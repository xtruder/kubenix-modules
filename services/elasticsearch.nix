{ config, lib, k8s, ... }:

with k8s;
with lib;

let
  b2s = value: if value then "true" else "false";
in {
  config.kubernetes.moduleDefinitions.elasticsearch.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Elasticsearch image to use";
        type = types.str;
        default = "quay.io/pires/docker-elasticsearch-kubernetes:5.5.0";
      };

      name = mkOption {
        description = "Name of the elasticsearch cluster";
        type = types.str;
        default = name;
      };

      plugins = mkOption {
        description = "List of elasticsearch plugins to install";
        type = types.listOf types.str;
        default = [];
        example = ["repository-gcs" "repository-s3"];
      };

      numberOfMasters = mkOption {
        description = "Minimal number of master";
        type = types.int;
        default = (findFirst (cfg: elem "master" cfg.roles) {replicas = 1;} (attrValues config.nodeSets)).replicas - 1;
      };

      nodeSets = mkOption {
        description = "Attribute set of node sets";
        default = {
          master.roles = ["master" "data" "ingest" "client"];
        };
        type = types.attrsOf (types.submodule ({name, ...}: {
          options = {
            name = mkOption {
              description = "Node role name";
              default = name;
            };

            replicas = mkOption {
              type = types.int;
              default = 1;
              description = "Number of node set replicas";
            };

            roles = mkOption {
              description = "List of node roles";
              type = types.listOf (types.enum ["master" "data" "ingest" "client"]);
              default = [];
            };

            memory = mkOption {
              description = "Default memory reserved for all node types";
              default = 2048;
              type = types.int;
            };

            cpu = mkOption {
              description = "Default CPU reserved for all node types";
              default = "1000m";
              type = types.str;
            };

            storage = {
              enable = mkEnableOption "elasticsearch persistent storage";

              size = mkOption {
                description = "Elasticsearch storage size";
                default = "100Gi";
                type = types.str;
              };

              class = mkOption {
                description = "Elasticsearh datanode storage class";
                type = types.nullOr types.str;
                default = null;
              };
            };
          };
        }));
      };
    };

    config = mkMerge [{
      kubernetes.resources.services.elasticsearch-discovery = {
        metadata.name = "${name}-discovery";
        metadata.labels.component = name;
        spec.selector.component = name;
        spec.selector.master = "true";
        spec.ports = [{
          name = "transport";
          port = 9300;
          protocol = "TCP";
        }];
      };

      kubernetes.resources.services.elasticsearch = {
        metadata.name = name;
        metadata.labels.component = name;
        spec.selector.component = name;
        spec.selector.client = "true";
        spec.ports = [{
          name = "http";
          port = 9200;
          protocol = "TCP";
        }];
      };
    } {
      kubernetes.resources = mkMerge (mapAttrsToList (namea: cfg: let
        group = if cfg.storage.enable then "statefulSets" else "deployments";
        kind = if cfg.storage.enable then "StatefulSet" else "Deployment";
        isMaster = elem "master" cfg.roles;
        isClient = elem "client" cfg.roles;
      in {
        podDisruptionBudgets.${cfg.name} = {
          metadata.name = "${name}-${cfg.name}";
          spec = {
            maxUnavailable = 1;
            selector.matchLabels = {
              component = name;
              role = cfg.name;
            };
          };
        };

        ${group}.${cfg.name} = {
          inherit kind;
          metadata = {
            name = "${name}-${cfg.name}";
            labels.component = name;
          };
          spec = {
            replicas = cfg.replicas;
            template = {
              metadata.labels = {
                component = name;
                role = cfg.name;
                master = if isMaster then "true" else "false";
                client = if isClient then "true" else "false";
              };
              spec = {
                initContainers = [{
                  name = "init-sysctl";
                  image = "busybox";
                  imagePullPolicy = "IfNotPresent";
                  command = ["sysctl" "-w" "vm.max_map_count=262144"];
                  securityContext.privileged = true;
                }];
                containers.elasticsearch = {
                  securityContext = {
                    privileged = false;
                    capabilities.add = ["IPC_LOCK" "SYS_RESOURCE"];
                  };
                  image = config.image;
                  imagePullPolicy = "Always";
                  env = {
                    NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
                    NODE_NAME.valueFrom.fieldRef.fieldPath = "metadata.name";
                    CLUSTER_NAME.value = config.name;
                    NUMBER_OF_MASTERS.value = toString config.numberOfMasters;
                    NODE_MASTER.value = b2s (elem "master" cfg.roles);
                    NODE_DATA.value = b2s (elem "data" cfg.roles);
                    NODE_INGEST.value = b2s (elem "ingest" cfg.roles);
                    HTTP_ENABLE.value = b2s (elem "client" cfg.roles);
                    ES_JAVA_OPTS.value = "-Xms${toString (cfg.memory * 3 / 4)}m -Xmx${toString (cfg.memory * 3 / 4)}m";
                    DISCOVERY_SERVICE.value = "${name}-discovery";
                    ES_PLUGINS_INSTALL.value = toString config.plugins;
                  };

                  resources = {
                    requests.memory = "${toString cfg.memory}Mi";
                    requests.cpu = cfg.cpu;
                    limits.cpu = cfg.cpu;
                  };

                  ports = [{
                    containerPort = 9300;
                    name = "transport";
                    protocol = "TCP";
                  }] ++ (optional (elem "client" cfg.roles) {
                    containerPort = 9200;
                    name = "http";
                    protocol = "TCP";
                  });

                  livenessProbe = mkIf (!isMaster) {
                    tcpSocket.port = 9300;
                  };
                  readinessProbe = mkIf isClient {
                    httpGet = {
                      path = "/_cluster/health";
                      port = 9200;
                    };
                    initialDelaySeconds = 20;
                    timeoutSeconds = 5;
                  };

                  volumeMounts = [{
                    name = "storage";
                    mountPath = "/data";
                  }];
                };
              };
              spec.volumes.storage = mkIf (!cfg.storage.enable) {
                emptyDir.medium = "";
              };
            };
          } // (optionalAttrs cfg.storage.enable {
            serviceName = "${name}-discovery";
            volumeClaimTemplates = [{
              metadata.name = "storage";
              spec = {
                accessModes = ["ReadWriteOnce"];
                resources.requests.storage = cfg.storage.size;
                storageClassName = cfg.storage.class;
              };
            }];
          });
        };
      }) config.nodeSets);
    }];
  };
}
