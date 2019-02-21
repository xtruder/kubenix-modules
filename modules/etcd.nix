{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

{
  imports = [
    kubenix.k8s
  ];

  options.args = {
    image = mkOption {
      description = "Name of the etcd image to use";
      type = types.str;
      default = "quay.io/coreos/etcd:v3.2.3";
    };

    replicas = mkOption {
      description = "Number of etcd replicas to run";
      type = types.int;
      default = 3;
    };

    clusterState = mkOption {
      description = "State of the cluster";
      type = types.enum ["new" "existing"];
      default = "new";
    };

    storage = {
      class = mkOption {
        description = "Etcd storage class";
        type = types.nullOr types.str;
        default = null;
      };

      size = mkOption {
        description = "Etcd storage size";
        type = types.str;
        default = "1Gi";
      };
    };
  };

  config = {
    submodule = {
      name = "etcd";
      version = "1.0.0";
      description = "";
    };
    kubernetes.api.services.etcd-headless = {
      metadata.name = "${name}-headless";
      metadata.labels.app = name;
      spec = {
        ports = [{
          name = "client";
          port = 2379;
        } {
          name = "peer";
          port = 2380;
        }];
        clusterIP = "None";
        selector.app = name;
        publishNotReadyAddresses = true;
      };
    };

    kubernetes.api.services.etcd = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        ports = [{
          name = "client";
          port = 2379;
        } {
          name = "peer";
          port = 2380;
        }];
        selector.app = name;
      };
    };

    kubernetes.api.statefulsets.etcd = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        serviceName = "${name}-headless";
        replicas = config.args..replicas;
        podManagementPolicy = "Parallel";
        template = {
          metadata.name = name;
          metadata.labels.app = name;
          metadata.annotations = {
            "prometheus.io/scrape" = "true";
            "prometheus.io/port" = "2379";
          };
          spec = {
            containers.etcd = {
              image = config.args..image;
              imagePullPolicy = "Always";
              ports = [{
                name = "metrics"; # due to prometheus limitations, port has to be named metrics
                containerPort = 2379;
              } {
                name = "peer";
                containerPort = 2380;
              }];
              env = {
                CLUSTER_SIZE.value = toString config.args..replicas;
                SET_NAME.value = "${name}-headless";
                APP_NAME.value = name;
              };
              volumeMounts = [{
                name = "data";
                mountPath = "/var/run/etcd";
              }];
              resources.requests = {
                cpu = "100m";
                memory = "256Mi";
              };
              command = ["/bin/sh" "-ecx" ''
                IP=$(hostname -i)

                for i in $(seq 0 $((''${CLUSTER_SIZE} - 1))); do
                  while true; do
                    echo "Waiting for ''${APP_NAME}-''${i}.''${SET_NAME} to come up"
                    ping -W 1 -c 1 ''${APP_NAME}-''${i}.''${SET_NAME} > /dev/null && break
                    sleep 1s
                  done
                done

                PEERS=""
                for i in $(seq 0 $((''${CLUSTER_SIZE} - 1))); do
                    PEERS="''${PEERS}''${PEERS:+,}''${APP_NAME}-''${i}=http://''${APP_NAME}-''${i}.''${SET_NAME}:2380"
                done

                # start etcd. If cluster is already initialized the `--initial-*` options will be ignored.
                exec etcd --name ''${HOSTNAME} \
                  --listen-peer-urls http://''${IP}:2380 \
                  --listen-client-urls http://''${IP}:2379,http://127.0.0.1:2379 \
                  --advertise-client-urls http://''${HOSTNAME}.''${SET_NAME}:2379 \
                  --initial-advertise-peer-urls http://''${HOSTNAME}.''${SET_NAME}:2380 \
                  --initial-cluster-token etcd-cluster-1 \
                  --initial-cluster ''${PEERS} \
                  --initial-cluster-state ${config.clusterState} \
                  --data-dir /var/run/etcd/default.etcd
              ''];
            };
          };
        };
        volumeClaimTemplates = [{
          metadata.name = "data";
          spec = {
            accessModes = ["ReadWriteOnce"];
            resources.requests.storage = config.args..storage.size;
            storageClassName = mkIf (config.args..storage.class != null) config.args..storage.class;
          };
        }];
      };
    };
  };
}
