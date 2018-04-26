{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.bitcoind.module = {name, config, ...}: let
  bitcoindConfig = ''
##
## bitcoin.conf configuration file. Lines beginning with # are comments.
##
 
# Network-related settings:

# Run on the test network instead of the real bitcoin network.
testnet=${ toString config.testnet }

# Run a regression test network
regtest=${ toString config.regtest }

# Connect via a SOCKS5 proxy
#proxy=127.0.0.1:9050

# Bind to given address and always listen on it. Use [host]:port notation for IPv6
#bind=<addr>

# Bind to given address and whitelist peers connecting to it. Use [host]:port notation for IPv6
#whitebind=<addr>

# Use as many addnode= settings as you like to connect to specific peers
#addnode=69.164.218.197
#addnode=10.0.0.2:8333

# Alternatively use as many connect= settings as you like to connect ONLY to specific peers
#connect=69.164.218.197
#connect=10.0.0.1:8333

# Listening mode, enabled by default except when 'connect' is being used
#listen=1

# Maximum number of inbound+outbound connections.
#maxconnections=

#
# JSON-RPC options (for controlling a running Bitcoin/bitcoind process)
#

# server=1 tells Bitcoin-Qt and bitcoind to accept JSON-RPC commands
#server=0

# Bind to given address to listen for JSON-RPC connections. Use [host]:port notation for IPv6.
# This option can be specified multiple times (default: bind to all interfaces)
#rpcbind=<addr>

# If no rpcpassword is set, rpc cookie auth is sought. The default `-rpccookiefile` name
# is .cookie and found in the `-datadir` being used for bitcoind. This option is typically used
# when the server and client are run as the same user.
#
# If not, you must set rpcuser and rpcpassword to secure the JSON-RPC api. The first
# method(DEPRECATED) is to set this pair for the server and client:
#rpcuser=Ulysseys
#rpcpassword=YourSuperGreatPasswordNumber_DO_NOT_USE_THIS_OR_YOU_WILL_GET_ROBBED_385593
#
# The second method `rpcauth` can be added to server startup argument. It is set at initialization time
# using the output from the script in share/rpcauth/rpcauth.py after providing a username:
#
# ./share/rpcauth/rpcauth.py alice
# String to be appended to bitcoin.conf:
# rpcauth=alice:f7efda5c189b999524f151318c0c86$d5b51b3beffbc02b724e5d095828e0bc8b2456e9ac8757ae3211a5d9b16a22ae
# Your password:
# DONT_USE_THIS_YOU_WILL_GET_ROBBED_8ak1gI25KFTvjovL3gAM967mies3E=
#
# On client-side, you add the normal user/password pair to send commands:
#rpcuser=alice
#rpcpassword=DONT_USE_THIS_YOU_WILL_GET_ROBBED_8ak1gI25KFTvjovL3gAM967mies3E=
#
# You can even add multiple entries of these to the server conf file, and client can use any of them:
# rpcauth=bob:b2dd077cb54591a2f3139e69a897ac$4e71f08d48b4347cf8eff3815c0e25ae2e9a4340474079f55705f40574f4ec99

# How many seconds bitcoin will wait for a complete RPC HTTP request.
# after the HTTP connection is established. 
#rpcclienttimeout=30

# By default, only RPC connections from localhost are allowed.
# Specify as many rpcallowip= settings as you like to allow connections from other hosts,
# either as a single IPv4/IPv6 or with a subnet specification.

# NOTE: opening up the RPC port to hosts outside your local trusted network is NOT RECOMMENDED,
# because the rpcpassword is transmitted over the network unencrypted.

# server=1 tells Bitcoin-Qt to accept JSON-RPC commands.
# it is also read by bitcoind to determine if RPC should be enabled 
#rpcallowip=10.1.1.34/255.255.255.0
#rpcallowip=1.2.3.4/24
#rpcallowip=2001:db8:85a3:0:0:8a2e:370:7334/96

# Listen for RPC connections on this TCP port:
rpcport=${toString config.rpcPort}

# You can use Bitcoin or bitcoind to send commands to Bitcoin/bitcoind
# running on another host using this option:
#rpcconnect=127.0.0.1

# Create transactions that have enough fees so they are likely to begin confirmation within n blocks (default: 6).
# This setting is over-ridden by the -paytxfee option.
#txconfirmtarget=n

# Miscellaneous options

# Pre-generate this many public/private key pairs, so wallet backups will be valid for
# both prior transactions and several dozen future transactions.
#keypool=100

# Pay an optional transaction fee every time you send bitcoins.  Transactions with fees
# are more likely than free transactions to be included in generated blocks, so may
# be validated sooner.
#paytxfee=0.00

# Enable pruning to reduce storage requirements by deleting old blocks. 
# This mode is incompatible with -txindex and -rescan.
# 0 = default (no pruning).
# 1 = allows manual pruning via RPC.
# >=550 = target to stay under in MiB. 
#prune=550

# User interface options

# Start Bitcoin minimized
#min=1

# Minimize to the system tray
#minimizetotray=1

# Log to console
printtoconsole=1
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

      rpcPort = mkOption {
        description = "Bitcoind RPC port";
        default = 8332;
        type = types.int;
      };

      testnet = mkOption {
        description = "Testnet";
        default = true;
        type = types.bool;
      };

      regtest = mkOption {
        description = "Regtest";
        default = false;
        type = types.bool;
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
          default = "200Gi";
        };
      };
    };

    config = {
      kubernetes.resources.statefulSets.bitcoind = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          replicas = config.replicas;
          serviceName = name;
          podManagementPolicy = "Parallel";
          template = {
            metadata.labels.app = name;
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
                  cpu = "1000m";
                  memory = "2048Mi";
                };
                resources.limits = {
                  cpu = "1000m";
                  memory = "2048Mi";
                };
              };
              volumes.config.configMap.name = "${name}-config";
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
        metadata.name = "${name}-config";
        data."bitcoin.conf" = bitcoindConfig;
      };

      kubernetes.resources.services.bitcoind = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          type = "NodePort";
          selector.app = name;
          ports = [{
            name = "rpc";
            port = config.rpcPort;
          } {
            name = "p2p";
            port = 8333;
          }];
        };
      };
    };
  };
}
