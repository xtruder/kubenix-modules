{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.core-geth.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Name of the image to use";
        type = types.str;
        default = "etclabscore/core-geth:version-1.11.11";
      };

      replicas = mkOption {
        description = "Number of node replicas";
        type = types.int;
        default = 1;
      };

      chain = mkOption {
        description = "Which eth chain to use";
        type = types.enum ["ethereum" "kovan" "ropsten" "classic"];
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

      http = {
        enable = mkEnableOption " the HTTP-RPC server";

        addr = mkOption {
          description = "HTTP-RPC server listening interface";
          type = types.str;
          default = "0.0.0.0";
        };
        
        api = mkOption {
          description = "API's offered over the HTTP-RPC interface.";
          type = types.listOf types.str;
          default = ["eth" "net" "web3"];
        };

        vhosts = mkOption {
          description = "Comma separated list of virtual hostnames from which to accept requests (server enforced). Accepts '*' wildcard.";
          type = types.listOf types.str;
          default = ["*"];
        };

        corsdomain = mkOption {
          description = "Comma separated list of domains from which to accept cross origin requests (browser enforced).";
          type = types.listOf types.str;
          default = ["*"];
        };
      };

      ws = {
        enable = mkEnableOption " the WS-RPC server";

        addr = mkOption {
          description = "WS-RPC server listening interface";
          type = types.str;
          default = "0.0.0.0";
        };

        origins = mkOption {
          description = "Origins from which to accept websockets requests";
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
        description = "Extra node options";
        default = [];
        type = types.listOf types.str;
      };
    };

    config = {
      kubernetes.resources.statefulSets.core-geth = {
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
              containers.core-geth = {
                image = config.image;
                args = 
                  (if config.chain == "ethereum" then [] else ["--${config.chain}"])
                  ++ [
                    "--port 30303"
                    "--maxpendpeers 32"
                  ]
                  ++ (if config.http.enable then [
                    "--http"
                    "--http.addr ${config.http.addr}"
                    "--http.api ${concatStringsSep "," config.http.api}"
                    "--http.corsdomain ${concatStringsSep "," config.http.corsdomain}"
                    "--http.vhosts ${concatStringsSep "," config.http.vhosts}"
                  ] else [])
                  ++ (if config.ws.enable then [
                    "--ws"
                    "--ws.addr ${config.ws.addr}"
                    "--ws.origins ${concatStringsSep "," config.ws.origins}"
                  ] else [])
                  ++ config.extraOptions;

                resources = {
                  requests.cpu = config.resources.cpu;
                  requests.memory = config.resources.memory;
                  limits.cpu = config.resources.cpu;
                  limits.memory = config.resources.memory;
                };
                volumeMounts = [{
                  name = "storage";
                  mountPath = "/root/.ethereum";
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

      kubernetes.resources.services.core-geth = {
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