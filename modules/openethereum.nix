{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.openethereum.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Name of the openethereum image to use";
        type = types.str;
        default = "openethereum/openethereum:v3.0.0";
      };

      replicas = mkOption {
        description = "Number of node replicas";
        type = types.int;
        default = 1;
      };

      storage = {
        size = mkOption {
          description = "Node storage size";
          default = if config.chain == "ethereum" then "200G" else "100G";
          type = types.str;
        };

        class = mkOption {
          description = "Node storage class (should be ssd)";
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
        type = types.enum ["classic" "ethereum" "ropsten" "kovan"];
      };

      resources = {
        cpu = mkOption {
          description = "CPU resource requirements";
          type = types.str;
          default =
            if config.chain == "classic" || config.chain == "ethereum"
            then "4000m" else "1000m";
        };

        memory = mkOption {
          description = "Memory resource requiements";
          type = types.str;
          default =
            if config.chain == "classic" || config.chain == "ethereum"
            then "6000Mi" else "1000Mi";
        };
      };

      extraOptions = mkOption {
        description = "Extra node options";
        default = [];
        type = types.listOf types.str;
      };
    };

    config = {
      kubernetes.resources.statefulSets.openethereum = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          selector.matchLabels.app = name;
          replicas = config.replicas;
          serviceName = name;
          podManagementPolicy = "Parallel";
          updateStrategy.type = "RollingUpdate";
          template = {
            metadata.labels.app = name;
            spec = {
              securityContext.fsGroup = 1000;
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
              containers.openethereum = {
                image = config.image;
                args = [
                  "--jsonrpc-apis=${concatStringsSep "," config.jsonrpc.apis}"
                  ''--jsonrpc-cors="*"''
                  "--jsonrpc-interface=all"
                  "--geth"
                  "--chain=${config.chain}"
                  "--jsonrpc-hosts=${concatStringsSep "," config.jsonrpc.hosts}"
                  "--port=30303"
                  "--allow-ips=public"
                  "--max-pending-peers=32"
                ] ++ config.extraOptions;

                resources = {
                  requests.cpu = config.resources.cpu;
                  requests.memory = config.resources.memory;
                  limits.cpu = config.resources.cpu;
                  limits.memory = config.resources.memory;
                };
                volumeMounts = [{
                  name = "storage";
                  mountPath = "/home/openethereum/.local/share/io.parity.ethereum";
                }];
                ports = [
                  { containerPort = 8545; }
                  { containerPort = 8546; }
                  { containerPort = 30303; }
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

      kubernetes.resources.services.openethereum = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          selector.app = name;
          ports = [{
            name = "json-rpc-http";
            port = 8545;
          } {
            name = "json-rpc-ws";
            port = 8546;
          } {
            name = "p2p";
            port = 30303;
          }];
        };
      };
    };
  };
}