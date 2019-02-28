{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.parity.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Name of the parity image to use";
        type = types.str;
        default = "parity/parity:v2.2.11";
      };

      replicas = mkOption {
        description = "Number of parity replicas";
        type = types.int;
        default = 1;
      };

      storage = {
        size = mkOption {
          description = "Parity storage size";
          default = if config.chain == "homestead" then "200G" else "100G";
          type = types.str;
        };

        class = mkOption {
          description = "Parity storage class (should be ssd)";
          default = null;
          type = types.nullOr types.str;
        };
      };

      jsonrpc.apis = mkOption {
        description = "List of exposed RPC apis";
        type = types.listOf types.str;
        default = ["eth" "net" "web3"];
      };

      jsonrpc.hosts = mkOption {
        description = "Which hosts are allowed to connect to json rpc";
        type = types.listOf types.str;
        default = ["all"];
      };

      chain = mkOption {
        description = "Which eth chain to use";
        type = types.enum ["classic" "homestead" "ropsten" "kovan"];
        default = "homestead";
      };

      peerPort = mkOption {
        description = "Node port to listen for p2p traffic";
        type = types.int;
        default = 30303;
      };

      resources = {
        cpu = mkOption {
          description = "CPU resource requirements";
          type = types.str;
          default =
            if config.chain == "classic" || config.chain == "homestead"
            then "4000m" else "1000m";
        };

        memory = mkOption {
          description = "Memory resource requiements";
          type = types.str;
          default =
            if config.chain == "classic" || config.chain == "homestead"
            then "4000Mi" else "1000Mi";
        };
      };

      extraOptions = mkOption {
        description = "Extra parity options";
        default = [];
        type = types.listOf types.str;
      };
    };

    config = {
      kubernetes.resources.statefulSets.parity = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          replicas = config.replicas;
          serviceName = name;
          podManagementPolicy = "Parallel";
          updateStrategy.type = "RollingUpdate";
          template = {
            metadata.labels.app = name;
            spec = {
              containers.ethmonitor = {
                image = "gatehub/ethmonitor";
                env.ETH_NODE_URL.value = "http://localhost:8545";
                ports = [
                  { containerPort = 3000; }
                ];
                resources = {
                  requests.cpu = "50m";
                  requests.memory = "128Mi";
                  limits.cpu = "100m";
                  limits.memory = "128Mi";
                };
              };
              containers.parity = {
                image = config.image;
                args = [
                  "--jsonrpc-apis=${concatStringsSep "," config.jsonrpc.apis}"
                  ''--jsonrpc-cors="*"''
                  "--jsonrpc-interface=all"
                  "--geth"
                  "--chain=${config.chain}"
                  "--jsonrpc-hosts=${concatStringsSep "," config.jsonrpc.hosts}"
                  "--port=${toString config.peerPort}"
                  "--allow-ips=public"
                  "--max-pending-peers=32"
                ];

                resources = {
                  requests.cpu = config.resources.cpu;
                  requests.memory = config.resources.memory;
                  limits.cpu = config.resources.cpu;
                  limits.memory = config.resources.memory;
                };
                volumeMounts = [{
                  name = "storage";
                  mountPath = "/root/.local/share/io.parity.ethereum";
                }];
                ports = [
                  { containerPort = 8545; }
                  { containerPort = config.peerPort; }
                ];
                readinessProbe = {
                  httpGet = {
                    path = "/";
                    port = 3000;
                  };
                  initialDelaySeconds = 30;
                  timeoutSeconds = 30;
                };
                securityContext.capabilities.add = ["NET_ADMIN"];
              };
            };
          };
          volumeClaimTemplates = [{
            metadata.name = "storage";
            spec = {
              accessModes = ["ReadWriteOnce"];
              resources.requests.storage = config.storage.size;
              storageClassName = mkIf (config.storage.class != null)
                config.storage.class;
            };
          }];
        };
      };

      kubernetes.resources.services.parity = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          type = "NodePort";
          selector.app = name;
          ports = [{
            name = "parity";
            port = 8545;
          } {
            name = "p2p";
            port = config.peerPort;
            nodePort = config.peerPort;
          }];
        };
      };
    };
  };
}
