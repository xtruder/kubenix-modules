{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.rippled.module = {name, config, ...}: let
  rippledConfig = ''
[server]
port_peer
port_rpc
port_ws_public

[port_peer]
ip=0.0.0.0
port=${toString config.peerPort}
protocol=peer
admin=127.0.0.1

[port_rpc]
ip=127.0.0.1
port=5005
protocol=http
admin=127.0.0.1

[port_ws_public]
ip=0.0.0.0
port=5006
protocol=ws,wss
admin=127.0.0.1

[database_path]
/data

[node_db]
type=${config.db.type}
path=/data
compression=1
online_delete=${toString config.onlineDelete}
advisory_delete=0
open_files=2000
filter_bits=12
cache_mb=256
file_size_mb=8
file_size_mult=2

[ips]
${concatStringsSep "\n" config.ips}

[validators_file]
validators.txt

${optionalString (config.validationSeed != null) ''
[validation_seed]
${config.validationSeed}
''}

[node_size]
${config.nodeSize}

[ledger_history]
${toString config.ledgerHistory}

[fetch_depth]
full

[validation_quorum]
3

[sntp_servers]
time.windows.com
time.apple.com
time.nist.gov
pool.ntp.org

[rpc_startup]
{ "command": "log_level", "severity": "error" }

${config.extraConfig}
  '';

  resources = {
    tiny = {
      cpu = "1000m";
      memory = "4000Mi";
    };

    low = {
      cpu = "4000m";
      memory = "8000Mi";
    };

    medium = {
      cpu = "6000m";
      memory = "16000Mi";
    };

    huge = {
      cpu = "7000m";
      memory = "32000Mi";
    };
  };

  in {
    options = {
      image = mkOption {
        description = "Name of the rippled image to use";
        type = types.str;
        default = "gatehub/rippled";
      };

      replicas = mkOption {
        description = "Number of nginx replicas";
        type = types.int;
        default = 1;
      };

      retentionTime = mkOption {
        description = "Rippled average retention time in days";
        type = types.int;
        default = 1;
      };

      onlineDelete = mkOption {
        description = "How much ledger history is kept";
        type = types.int;
        # retention time * seconds in a day / 3.5s avg per block
        default =
          toInt (head (splitString "." (toString (config.retentionTime * 86400 / 3.5))));
      };

      ledgerHistory = mkOption {
        description = "How much history to fetch";
        type = types.int;
        default = config.onlineDelete;
      };

      ips = mkOption {
        description = "List of ips where to find other servers speaking ripple protocol";
        type = types.listOf types.str;
        default = ["r.ripple.com 51235"];
      };

      validatorFile = mkOption {
        description = "Rippled validator list file";
        type = types.package;
        default = builtins.fetchurl {
          url = "https://ripple.com/validators.txt";
          sha256 = "0lsnh7pclpxl627qlvjfqjac97z3glwjv9h08lqcr11bxb6rafdk";
        };
      };

      db = {
        type = mkOption {
          description = "Type of the database used";
          type = types.enum ["NuDB" "RocksDB"];
          default = if config.validationSeed != null then "RocksDB" else "NuDB";
        };
      };

      storage = {
        size = mkOption {
          description = "Rippled storage size";
          # 12G per day on average plus 10G extra
          default = "${toString (config.retentionTime * 12 + 10)}G";
          type = types.str;
        };

        class = mkOption {
          description = "Rippled storage class (should be ssd)";
          default = null;
          type = types.nullOr types.str;
        };
      };

      nodeSize = mkOption {
        description = "Rippled node size";
        default = "small";
        type = types.enum ["small" "medium" "large" "huge"];
      };

      validationSeed = mkOption {
        description = "Rippled validation seed";
        default = null;
        type = types.nullOr types.str;
      };

      peerPort = mkOption {
        description = "Rippled peer port";
        default = 32235;
        type = types.int;
      };

      extraConfig = mkOption {
        description = "Extra rippled config";
        default = "";
        type = types.lines;
      };
    };

    config = {
      kubernetes.resources.statefulSets.rippled = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          replicas = config.replicas;
          serviceName = name;
          podManagementPolicy = "Parallel";
          template = {
            metadata.labels.app = name;
            spec = {
              containers.rippled = {
                image = config.image;
                command = ["/opt/ripple/bin/rippled" "--conf" "/etc/rippled/rippled.conf"];

                resources.requests = resources.${config.nodeSize};
                resources.limits = resources.${config.nodeSize};

                readinessProbe = {
                  exec.command = ["/bin/sh" "-c" ''
                    /opt/ripple/bin/rippled server_info | grep complete_ledgers | grep -v empty
                  ''];
                  initialDelaySeconds = 60;
                  periodSeconds = 30;
                };

                volumeMounts = [{
                  name = "config";
                  mountPath = "/etc/rippled";
                  readOnly = true;
                } {
                  name = "storage";
                  mountPath = "/data";
                }];
              };
              volumes.config.configMap = {
                defaultMode = k8s.octalToDecimal "0600";
                name = "${name}-config";
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

      kubernetes.resources.configMaps.rippled = {
        metadata.name = "${name}-config";
        data."rippled.conf" = rippledConfig;
        data."validators.txt" = builtins.readFile config.validatorFile;
      };

      kubernetes.resources.services.rippled = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          type = "NodePort";
          selector.app = name;
          ports = [{
            name = "websockets-alt";
            port = 5006;
          } {
            name = "websockets";
            port = 443;
            targetPort = 5006;
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
