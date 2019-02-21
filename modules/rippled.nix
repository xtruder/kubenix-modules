{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

let
  name = name;
  rippledConfig = ''
[server]
port_peer
port_rpc
port_ws_public

[port_peer]
ip=0.0.0.0
port=32238
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
type=${config.args.db.type}
path=/data
compression=1
${optionalString (config.args.onlineDelete != null)
"online_delete=${toString config.args.onlineDelete}"}
advisory_delete=0
open_files=2000
filter_bits=12
cache_mb=256
file_size_mb=8
file_size_mult=2

[ips]
${concatStringsSep "\n" config.args.ips}

${optionalString (config.args.privatePeer) ''
[peer_private]
1
''}

[validators_file]
validators.txt

${optionalString (config.args.validationSeed != null && !config.args.validator.enable) ''
[validation_seed]
${config.args.validationSeed}
''}

[node_size]
${config.args.nodeSize}

[ledger_history]
${toString config.args.ledgerHistory}

[fetch_depth]
full

[validation_quorum]
${toString config.args.validationQuorum}

[sntp_servers]
time.windows.com
time.apple.com
time.nist.gov
pool.ntp.org

[rpc_startup]
{ "command": "log_level", "severity": "${config.args.logLevel}"  }

${optionalString (config.args.cluster.enable) ''
[ips_fixed]
${concatStringsSep "\n" (map (v: v.host + " " + (toString v.port)) config.args.cluster.peers)}

[cluster_nodes]
${concatStringsSep "\n" (map (v: v.validationPublicKey + " " + v.name) config.args.cluster.peers)}
''}

${config.args.extraConfig}
'';

resources = {
  tiny = {
    cpu = "1000m";
    memory = "1000Mi";
  };

  small = {
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
  imports = [
    kubenix.k8s
  ];

  options.args = {
    image = mkOption {
      description = "Name of the rippled image to use";
      type = types.str;
      default = config.args.kubernetes.dockerRegistry + (builtins.unsafeDiscardStringContext "/${images.rippled.imageName}:${images.rippled.imageTag}");
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
      type = types.nullOr types.int;
      default =
        if config.args.ledgerHistory == "full" then null
        else config.args.ledgerHistory;
    };

    ledgerHistory = mkOption {
      description = "How much history to fetch";
      type = types.either (types.enum ["full"]) types.int;
      # retention time * seconds in a day / 3.5s avg per block
      default = toInt (head (splitString "." (toString (config.args.retentionTime * 86400 / 3.5))));
    };

    ips = mkOption {
      description = "List of ips where to find other servers speaking ripple protocol";
      type = types.listOf types.str;
      default = ["r.ripple.com 51235"];
    };

    privatePeer = mkOption {
      description = "Whether to keep the node as private (peers wont forward the IP )";
      type = types.bool;
      default = false;
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
        default = if config.args.validationSeed != null then "RocksDB" else "NuDB";
      };
    };

    storage = {
      size = mkOption {
        description = "Rippled storage size";
        # 12G(for NuDB) or 8G (for rocksdb) per day on average plus 10G extra
        default = "${toString (config.args.retentionTime * (if config.args.db.type == "NuDB" then 12 else 8) + 10)}G";
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
      default = "low";
      type = types.enum ["tiny" "low" "medium" "huge"];
    };

    validationSeed = mkOption {
      description = "Rippled validation seed";
      default = null;
      type = types.nullOr types.str;
    };

    peerPort = mkOption {
      description = "Rippled peer port";
      default = null;
      type = types.nullOr types.int;
    };

    logLevel = mkOption {
      description = "Rippled log level";
      type = types.enum ["fatal" "error" "warn" "info" "debug" "trace"];
      default = "info";
    };

    validationQuorum = mkOption {
      description = "Rippled validation quorum";
      type = types.int;
      default = if config.args.autovalidator.enable then 1 else 3;
    };

    autovalidator = {
      enable = mkEnableOption "auto validator";

      validationInterval = mkOption {
        description = "Auto validator validation interval in seconds";
        type = types.int;
        default = 2;
      };
    };

    validator = {
      enable = mkEnableOption "validator";

      token = mkSecretOption {
        description = "Validator token to use for ledger validation";
        default = {
          key = "token";
          name = "${name}-validator-token";
        };
      };
    };

    cluster = {
      enable = mkEnableOption "cluster";

      peers = mkOption {
        description = "List of peers to form a cluster with";
        type = types.listOf (types.submodule ({name, ...}: {
          options = {
            name = mkOption {
              default = name;
            };
            host = mkOption {
              description = "Peer's host address";
              type = types.str;
            };
            port = mkOption {
              description = "Peer's port";
              type = types.int;
              default = 32238;
            };
            validationPublicKey = mkOption {
              description = "Peer's public validation key";
            };
          };
        }));
        default = [];
      };

      nodeSeedSecret = mkOption {
        description = "";
        default = "node-seed";
      };
    };

    extraConfig = mkOption {
      description = "Extra rippled config";
      default = "";
      type = types.lines;
    };
  };

  config = {
    submodule = {
      name = "rippled";
      version = "1.0.0";
      description = "";
    };
      kubernetes.api.statefulsets.rippled = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          updateStrategy.type = "RollingUpdate";
          replicas = config.args.replicas;
          serviceName = name;
          podManagementPolicy = "Parallel";
          template = {
            metadata.labels.app = name;
            spec = {
              initContainers = [{
                name = "init-validator";
                image = "busybox";
                imagePullPolicy = "IfNotPresent";
                env = mkIf config.args.validator.enable {
                  RIPPLE_VALIDATOR_TOKEN = mkIf config.args.validator.enable (secretToEnv config.args.validator.token);
                };
                command = ["sh" "-c" ''
                  cp /etc/rippled-init/validators.txt /etc/rippled/validators.txt
                  cp /etc/rippled-init/rippled.conf /etc/rippled/rippled.conf
                  ${optionalString (config.args.validator.enable) ''
                  echo "[validator_token]" >> /etc/rippled/rippled.conf
                  echo "$RIPPLE_VALIDATOR_TOKEN" >> /etc/rippled/rippled.conf
                  ''}
                  ${optionalString (config.args.cluster.enable) ''
                  echo "[node_seed]" >> /etc/rippled/rippled.conf
                  ORDINAL=''${HOSTNAME##*-}
                  cat /node-seed/token-''$ORDINAL >> /etc/rippled/rippled.conf;
                  ''}
                ''];
                volumeMounts = [{
                  name = "config";
                  mountPath = "/etc/rippled";
                } {
                  name = "config-init";
                  mountPath = "/etc/rippled-init";
                }] ++ (optionals config.args.cluster.enable [{
                  name = "node-seed";
                  mountPath = "/node-seed";
                }]);
              }];
              securityContext.fsGroup = 1000;
              containers.rippled = {
                image = config.args.image;
                imagePullPolicy = "Always";
                command = ["rippled" "--conf" "/etc/rippled/rippled.conf"] ++
                  (optionals (config.args.autovalidator.enable) ["-a" "--start"]);

                resources.requests = resources.${config.args.nodeSize};
                resources.limits = resources.${config.args.nodeSize};

                readinessProbe = {
                  exec.command = ["/bin/sh" "-c" ''
                    rippled --conf /etc/rippled/rippled.conf server_info | grep complete_ledgers | grep -v empty
                  ''];
                  initialDelaySeconds = 60;
                  periodSeconds = 30;
                };

                volumeMounts = [{
                  name = "config";
                  mountPath = "/etc/rippled";
                } {
                  name = "storage";
                  mountPath = "/data";
                }];
              };
              containers.autovalidator = mkIf config.args.autovalidator.enable {
                image = config.args.image;
                imagePullPolicy = "Always";
                command = ["sh" "-c" ''
                  while true; do
                    rippled --conf /etc/rippled/rippled.conf ledger_accept
                    sleep ${toString config.args.autovalidator.validationInterval}
                  done
                ''];
                volumeMounts = [{
                  name = "config";
                  mountPath = "/etc/rippled";
                }];
              };
              volumes = {
                config-init.configMap = {
                  defaultMode = k8s.octalToDecimal "0600";
                  name = "${name}-config";
                };
                config.emptyDir = {};
              } // (optionalAttrs (config.args.cluster.enable) {
                node-seed.secret.secretName = config.args.cluster.nodeSeedSecret;
              });
            };
          };
          volumeClaimTemplates = [{
            metadata.name = "storage";
            spec = {
              accessModes = ["ReadWriteOnce"];
              resources.requests.storage = config.args.storage.size;
              storageClassName = mkIf (config.args.storage.class != null)
                config.args.storage.class;
            };
          }];
        };
      };

      kubernetes.api.configmaps.rippled = {
        metadata.name = "${name}-config";
        data."rippled.conf" = rippledConfig;
        data."validators.txt" = builtins.readFile config.args.validatorFile;
      };

      kubernetes.api.services = ((listToAttrs (map(i: (nameValuePair "${name}-${toString i}" {
        metadata.name = "${name}-${toString i}";
        metadata.labels.name = name;
        spec = {
          type = "ClusterIP";
          selector = {
            app = "${name}";
            "statefulset.kubernetes.io/pod-name" = "${name}-${toString i}";
          };
          ports = [{
            name = "p2p";
            port = 32238;
          }];
        };
      })) (range 0 (config.replicas - 1)))) // (optionalAttrs (config.peerPort != null) {
        "${name}" = {
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
              port = 32238;
              nodePort = config.args.peerPort;
            }];
          };
        };
      }));

      kubernetes.api.poddisruptionbudgets.rippled = {
        metadata.name = name;
        metadata.labels.app = name;
        spec.maxUnavailable = 1;
        spec.selector.matchLabels.app = name;
      };
    };
  };
}