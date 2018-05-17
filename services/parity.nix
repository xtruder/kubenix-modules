{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.parity.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Name of the parity image to use";
        type = types.str;
        default = "parity/parity:v1.10.4";
      };

      replicas = mkOption {
        description = "Number of parity replicas";
        type = types.int;
        default = 1;
      };

      storage = {
        size = mkOption {
          description = "Parity storage size";
          default = "45G";
          type = types.str;
        };

        class = mkOption {
          description = "Parity storage class";
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
        type = types.enum ["classic" "homestead" "ropsten"];
        default = "homestead";
      };

      peerPort = mkOption {
        description = "Node port to listen for p2p traffic";
        type = types.int;
        default = 30303;
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
          template = {
            metadata.labels.app = name;
            spec = {
              containers.parity = {
                image = config.image;
                command = ["/parity/parity"
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
                  requests.cpu = "4000m";
                  requests.memory = "4000Mi";
                  limits.cpu = "4000m";
                  limits.memory = "4000Mi";
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
                    path = "/api/health";
                    port = 8545;
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
