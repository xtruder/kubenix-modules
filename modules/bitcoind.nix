{ config, lib, k8s, ... }:

with k8s;
with lib;

let
  b2s = value: if value then "1" else "0";
in {
  config.kubernetes.moduleDefinitions.bitcoind.module = {config, module, ...}: let
    bitcoindConfig = ''
      ##
      ## bitcoin.conf configuration file. Lines beginning with # are comments.
      ##

      # [core]
      # Network-related settings:

      # Run on the test network instead of the real bitcoin network
      testnet=${b2s config.testnet}

      # Run a regression test network
      regtest=${b2s config.regtest}

      #
      # JSON-RPC options (for controlling a running Bitcoin/bitcoind process)
      #

      # server=1 tells Bitcoin-Qt and bitcoind to accept JSON-RPC commands
      server=${b2s config.server}

      # Log to console
      printtoconsole=1
      
      # Index all the transactions
      txindex=1
      
      # Enable replace By Fee
      walletrbf=1

      # [rpc]
      # Authentication
      rpcauth=${toString config.rpcAuth}      

      [main]
      port=18332
      rpcport=18333
      rpcallowip=0.0.0.0/0
      rpcbind=0.0.0.0

      [test]
      port=18332
      rpcport=18333
      rpcallowip=0.0.0.0/0
      rpcbind=0.0.0.0

      [regtest]
      port=18332
      rpcport=18333
      rpcallowip=0.0.0.0/0
      rpcbind=0.0.0.0
      
    '';
  in {
    options = {
      image = mkOption {
        description = "Name of the bitcoind image to use";
        type = types.str;
        default = "kylemanna/bitcoind";
      };

      replicas = mkOption {
        description = "Number of bitcoind replicas";
        type = types.int;
        default = 1;
      };

      server = mkOption {
        description = "Whether to enable RPC server";
        default = true;
        type = types.bool;
      };

      testnet = mkOption {
        description = "Whether to run in testnet mode";
        default = true;
        type = types.bool;
      };

      regtest = mkOption {
        description = "Whether to run in regtest mode";
        default = false;
        type = types.bool;
      };

      rpcAuth = mkOption {
        description = "Rpc auth. The field comes in the format: <USERNAME>:<SALT>$<HASH>";
        type = types.str;
      };

      storage = {
        class = mkOption {
          description = "Name of the storage class to use";
          type = types.nullOr types.str;
          default = null;
        };

        size = mkOption {
          description = "Storage size";
          type = types.str;
          default = if config.testnet || config.regtest then "30Gi" else "250Gi";
        };
      };
    };

    config = {
      kubernetes.resources.statefulSets.bitcoind = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          replicas = config.replicas;
          serviceName = module.name;
          podManagementPolicy = "Parallel";
          template = {
            metadata.labels.app = module.name;
            spec = {
              initContainers = [{
                name = "copy-bitcoind-config";
                image = "busybox";
                command = ["sh" "-c" "cp /config/bitcoin.conf /bitcoin/.bitcoin/bitcoin.conf"];
                volumeMounts = [{
                  name = "config";
                  mountPath = "/config";
                } {
                  name = "data";
                  mountPath = "/bitcoin/.bitcoin/";
                }];
              }];
              containers.bitcoind = {
                image = config.image;

                volumeMounts = [{
                  name = "data";
                  mountPath = "/bitcoin/.bitcoin/";
                }];

                resources.requests = {
                  cpu = "2000m";
                  memory = "2048Mi";
                };
                resources.limits = {
                  cpu = "2000m";
                  memory = "2048Mi";
                };

                ports = [{
                  name = "rpc-mainnet";
                  containerPort = 8332;
                } {
                  name = "rpc-testnet";
                  containerPort = 18332;
                } {
                  name = "rpc-regtest";
                  containerPort = 18444;
                } {
                  name = "p2p-mainnet";
                  containerPort = 8333;
                } {
                  name = "p2p-testnet";
                  containerPort = 18333;
                }];
              };
              volumes.config.configMap.name = "${module.name}-config";
            };
          };
          volumeClaimTemplates = [{
            metadata.name = "data";
            spec = {
              accessModes = ["ReadWriteOnce"];
              storageClassName = mkIf (config.storage.class != null) config.storage.class;
              resources.requests.storage = config.storage.size;
            };
          }];
        };
      };

      kubernetes.resources.configMaps.bitcoind = {
        metadata.name = "${module.name}-config";
        data."bitcoin.conf" = bitcoindConfig;
      };

      kubernetes.resources.services.bitcoind = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          selector.app = module.name;
          ports = [{
            name = "rpc-mainnet";
            port = 8332;
          } {
            name = "rpc-testnet";
            port = 18332;
          } {
            name = "rpc-regtest";
            port = 18444;
          } {
            name = "p2p-mainnet";
            port = 8333;
          } {
            name = "p2p-testnet";
            port = 18333;
          }];
        };
      };

      kubernetes.resources.podDisruptionBudgets.bitcoind = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec.maxUnavailable = 1;
        spec.selector.matchLabels.app = module.name;
      };
    };
  };
}
