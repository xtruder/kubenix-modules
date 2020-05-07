{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.parity.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Name of the parity image to use";
        type = types.str;
        default = "parity/parity:v2.7.2-stable";
      };

      replicas = mkOption {
        description = "Number of parity replicas";
        type = types.int;
        default = 1;
      };

      chain = mkOption {
        description = "Which eth chain to use";
        type = types.enum ["mainnet" "ethereum" "kovan" "ropsten" "classic" "classic-testnet" "expanse" "dev" "musicoin" "ellaism" "tobalaba"];
      };

      storage = {
        size = mkOption {
          description = "Parity storage size";
          default = if config.chain == "ethereum" then "200G" else "100G";
          type = types.str;
        };

        class = mkOption {
          description = "Parity storage class (should be ssd)";
          default = null;
          type = types.nullOr types.str;
        };
      };

      jsonrpc = {
        apis = mkOption {
          description = "Specify the APIs available through the HTTP JSON-RPC interface using a comma-delimited list of API names.";
          type = types.listOf types.str;
          default = ["eth" "net" "web3"];
        };

        hosts = mkOption {
          description = "List of allowed Host header values.";
          type = types.listOf types.str;
          default = ["all"];
        };

        interfaces = mkOption {
          description = "Network interfaces. Valid values are 'all', 'local' or the ip of the interface you want node to listen to.";
          type = types.listOf types.str;
          default = ["all"];
        };

        cors = mkOption {
          description = "Specify CORS header for HTTP JSON-RPC API responses.";
          type = types.listOf types.str;
          default = ["all"];
        };
      };

      ws = {
        hosts = mkOption {
          description = "List of allowed Host header values. This option will validate the Host header sent by the browser, it is additional security against some attack vectors.";
          type = types.listOf types.str;
          default = ["all"];
        };

        interfaces = mkOption {
          description = "Specify the hostname portion of the WebSockets JSON-RPC server, IP should be an interface's IP address, or all (all interfaces) or local.";
          type = types.listOf types.str;
          default = ["all"];
        };

        origins = mkOption {
          description = "Specify Origin header values allowed to connect.";
          type = types.listOf types.str;
          default = ["all"];
        };
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
              containers.parity = {
                image = config.image;
                args = [
                  "--geth"
                  "--chain=${config.chain}"
                  "--port=30303"
                  "--allow-ips=public"
                  "--max-pending-peers=32"
                  "--jsonrpc-apis=${concatStringsSep "," config.jsonrpc.apis}"
                  "--jsonrpc-cors=${concatStringsSep "," config.jsonrpc.cors}"
                  "--jsonrpc-interface=${concatStringsSep "," config.jsonrpc.interfaces}"
                  "--jsonrpc-hosts=${concatStringsSep "," config.jsonrpc.hosts}"
                  "--ws-origins=${concatStringsSep "," config.ws.origins}"
                  "--ws-hosts=${concatStringsSep "," config.ws.hosts}"
                  "--ws-interface=${concatStringsSep "," config.ws.interfaces}"
                ] ++ config.extraOptions;

                resources = {
                  requests.cpu = config.resources.cpu;
                  requests.memory = config.resources.memory;
                  limits.cpu = config.resources.cpu;
                  limits.memory = config.resources.memory;
                };
                volumeMounts = [{
                  name = "storage";
                  mountPath = "/home/parity/.local/share/io.parity.ethereum";
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

      kubernetes.resources.services.parity = {
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