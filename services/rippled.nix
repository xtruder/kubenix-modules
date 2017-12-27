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
type=rocksdb
path=/data
compression=1
online_delete=48000
advisory_delete=0
open_files=2000
filter_bits=12
cache_mb=256
file_size_mb=8
file_size_mult=2

[ips]
r.ripple.com 51235

[validators]
n949f75evCHwgyP4fPVgaHqNHxUVN15PsJEZ3B3HnXPcPjcZAoy7  RL1
n9MD5h24qrQqiyBC8aeqqCWvpiBiYQ3jxSr91uiDvmrkyHRdYLUj  RL2
n9L81uNCaPgtUJfaHh89gmdvXKAmSt5Gdsw2g1iPWaPkAHW5Nm4C  RL3
n9KiYM9CgngLvtRCQHZwgC2gjpdaZcCcbt3VboxiNFcKuwFVujzS  RL4
n9LdgEtkmGB9E2h3K4Vp7iGUaKuq23Zr32ehxiU8FWY7xoxbWTSA  RL5

${optionalString (config.validationSeed != null) ''
[validation_seed]
${config.validationSeed}
''}

[node_size]
${config.nodeSize}

[ledger_history]
12400

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
    small = {
      cpu = "500m";
      memory = "2000Mi";
    };

    medium = {
      cpu = "1000m";
      memory = "8000Mi";
    };

    large = {
      cpu = "2000m";
      memory = "16000Mi";
    };

    huge = {
      cpu = "4000m";
      memory = "24000Mi";
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

      storage = {
        size = mkOption {
          description = "Rippled storage size";
          default = "69G";
          type = types.str;
        };

        class = mkOption {
          description = "Rippled storage class";
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
