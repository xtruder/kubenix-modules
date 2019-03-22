{ config, lib, k8s, images, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.rippled.module = {config, module, ...}: let
    name = module.name;
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
type=${config.db.type}
path=/data
compression=1
${optionalString (config.onlineDelete != null)
  "online_delete=${toString config.onlineDelete}"}
advisory_delete=0
open_files=2000
filter_bits=12
cache_mb=256
file_size_mb=8
file_size_mult=2

[ips]
${concatStringsSep "\n" config.ips}

${optionalString (config.privatePeer) ''
[peer_private]
1
''}

[validators_file]
validators.txt

${optionalString (config.validationSeed != null && !config.validator.enable) ''
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
${toString config.validationQuorum}

[sntp_servers]
time.windows.com
time.apple.com
time.nist.gov
pool.ntp.org

[rpc_startup]
{ "command": "log_level", "severity": "${config.logLevel}"  }

${optionalString (config.cluster.enable) ''
[ips_fixed]
${concatStringsSep "\n" (map (v: v.host + " " + (toString v.port)) config.cluster.peers)}

[cluster_nodes]
${concatStringsSep "\n" (map (v: v.validationPublicKey + " " + v.name) config.cluster.peers)}
''}

${config.extraConfig}
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

  cmd = concatStringsSep " " (["rippled" "--conf" "/etc/rippled/rippled.conf"] ++ config.extraArgs);

  in {
    options = {
      image = mkOption {
        description = "Name of the rippled image to use";
        type = types.str;
        default = config.kubernetes.dockerRegistry + (builtins.unsafeDiscardStringContext "/${images.rippled.imageName}:${images.rippled.imageTag}");
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
          if config.ledgerHistory == "full" then null
          else config.ledgerHistory;
      };

      ledgerHistory = mkOption {
        description = "How much history to fetch";
        type = types.either (types.enum ["full"]) types.int;
        # retention time * seconds in a day / 3.5s avg per block
        default = toInt (head (splitString "." (toString (config.retentionTime * 86400 / 3.5))));
      };

      ips = mkOption {
        description = "List of ips where to find other servers speaking ripple protocol";
        type = types.listOf types.str;
        default =
          if config.testnet
          then ["r.altnet.rippletest.net 51235"]
          else ["r.ripple.com 51235"];
      };

      privatePeer = mkOption {
        description = "Whether to keep the node as private (peers wont forward the IP )";
        type = types.bool;
        default = false;
      };

      testnet = mkOption {
        description = "Whether to run node on testnet";
        type = types.bool;
        default = false;
      };

      validators = mkOption {
        description = "Rippled validator list file";
        type = types.lines;
        default =
          if !(config.testnet)
          then builtins.readFile (builtins.fetchurl {
            url = "https://ripple.com/validators.txt";
            sha256 = "0lsnh7pclpxl627qlvjfqjac97z3glwjv9h08lqcr11bxb6rafdk";
          })
          else ''
          [validator_list_sites]
          http://vl.altnet.rippletest.net

          [validator_list_keys]
          ED264807102805220DA0F312E71FC2C69E1552C9C5790F6C25E3729DEB573D5860
          '';
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
          # 12G(for NuDB) or 8G (for rocksdb) per day on average plus 10G extra
          default = "${toString (config.retentionTime * (if config.db.type == "NuDB" then 12 else 8) + 10)}G";
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
        default = if config.autovalidator.enable then 1 else 3;
      };

      standalone = mkOption {
        description = "Whether to run with no peers";
        type = types.bool;
        default = false;
      };

      startFresh = mkOption {
        description = "Whether to start from fresh ledger";
        type = types.bool;
        default = false;
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
            name = "${module.name}-validator-token";
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

      extraArgs = mkOption {
        description = "Extra rippled arguments";
        type = types.listOf types.str;
        default = [];
      };
    };

    config = {
      extraArgs = mkIf config.standalone ["--standalone"];
      standalone = mkDefault config.autovalidator.enable;
      startFresh = mkDefault config.autovalidator.enable;

      kubernetes.resources.statefulSets.rippled = {
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
              initContainers = [{
                name = "init-rippled";
                image = config.image;
                imagePullPolicy = "IfNotPresent";
                env = mkIf config.validator.enable {
                  RIPPLE_VALIDATOR_TOKEN = mkIf config.validator.enable (secretToEnv config.validator.token);
                };
                command = ["sh" "-c" ''
                  cp /etc/rippled-init/validators.txt /etc/rippled/validators.txt
                  cp /etc/rippled-init/rippled.conf /etc/rippled/rippled.conf
                  ${optionalString (config.validator.enable) ''
                  echo "[validator_token]" >> /etc/rippled/rippled.conf
                  echo "$RIPPLE_VALIDATOR_TOKEN" >> /etc/rippled/rippled.conf
                  ''}
                  ${optionalString (config.cluster.enable) ''
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
                }] ++ (optionals config.cluster.enable [{
                  name = "node-seed";
                  mountPath = "/node-seed";
                }]);
              }];
              securityContext.fsGroup = 1000;
              containers.rippled = {
                image = config.image;
                imagePullPolicy = "IfNotPresent";
                command = ["sh" "-c" ''
                  ${optionalString config.startFresh ''
                  if [ ! -f /data/.ledger-initialized ]; then
                    touch /data/.ledger-initialized
                    exec ${cmd} --start
                  fi
                  ''}

                  exec ${cmd}
                ''];

                resources.requests = resources.${config.nodeSize};
                resources.limits = resources.${config.nodeSize};

                readinessProbe = {
                  exec.command = ["sh" "-c" ''
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
              containers.autovalidator = mkIf config.autovalidator.enable {
                image = config.image;
                imagePullPolicy = "Always";
                command = ["sh" "-c" ''
                  while true; do
                    rippled --conf /etc/rippled/rippled.conf ledger_accept
                    sleep ${toString config.autovalidator.validationInterval}
                  done
                ''];
                volumeMounts = [{
                  name = "config";
                  mountPath = "/etc/rippled";
                } {
                  name = "storage";
                  mountPath = "/data";
                }];
              };
              volumes = {
                config-init.configMap = {
                  defaultMode = k8s.octalToDecimal "0600";
                  name = "${name}-config";
                };
                config.emptyDir = {};
              } // (optionalAttrs (config.cluster.enable) {
                node-seed.secret.secretName = config.cluster.nodeSeedSecret;
              });
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
        data."validators.txt" = config.validators;
      };

      kubernetes.resources.services = ((listToAttrs (map(i: (nameValuePair "${module.name}-${toString i}" {
        metadata.name = "${module.name}-${toString i}";
        metadata.labels.name = module.name;
        spec = {
          type = "ClusterIP";
          selector = {
            app = "${module.name}";
            "statefulset.kubernetes.io/pod-name" = "${module.name}-${toString i}";
          };
          ports = [{
            name = "p2p";
            port = 32238;
          }];
        };
      })) (range 0 (config.replicas - 1)))) // (optionalAttrs (config.peerPort != null) {
        "${module.name}" = {
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
              nodePort = config.peerPort;
            }];
          };
        };
      }));

      kubernetes.resources.podDisruptionBudgets.rippled = {
        metadata.name = name;
        metadata.labels.app = name;
        spec.maxUnavailable = 1;
        spec.selector.matchLabels.app = name;
      };
    };
  };
}
