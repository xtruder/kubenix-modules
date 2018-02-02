{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.parity.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Name of the parity image to use";
        type = types.str;
        default = "parity/parity:v1.7.10";
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

      blockedIpRanges = mkOption {
        description = "Blocked IP ranges";
        type = types.listOf types.str;
        default = [
          "0.0.0.0/8" "10.0.0.0/8" "100.64.0.0/10" "169.254.0.0/16"
          "172.16.0.0/12" "192.0.0.0/24" "192.0.2.0/24" "192.88.99.0/24"
          "192.168.0.0/16" "198.18.0.0/15" "198.51.100.0/24" "203.0.113.0/24"
          "224.0.0.0/4" "240.0.0.0/4" "0.0.0.0/8" "10.0.0.0/8" "100.64.0.0/10"
          "169.254.0.0/16" "172.16.0.0/12" "192.0.0.0/24" "192.0.2.0/24"
          "192.88.99.0/24" "192.168.0.0/16" "198.18.0.0/15" "198.51.100.0/24"
          "203.0.113.0/24" "224.0.0.0/4" "240.0.0.0/4" "100.65.186.0/23"
        ];
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
                  "--warp"
                  "--allow-ips=public"
                  "--max-pending-peers=32"
                ];

                lifecycle.postStart.exec.command = ["sh" "-c" ''
                  apt update
                  apt install -y iptables

                  ${concatMapStrings (range: ''
                  iptables -A OUTPUT -o eth0 -m state ! --state ESTABLISHED -p tcp -s 0/0 -d ${range} -j DROP
                  iptables -A OUTPUT -o eth0 -m state ! --state ESTABLISHED -p udp -s 0/0 -d ${range} -j DROP
                  '') config.blockedIpRanges}
                ''];

                resources = {
                  requests.memory = "8000Mi";
                  requests.cpu = "4000m";
                  limits.cpu = "8000Mi";
                  limits.memory = "8000Mi";
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
                    path = "/api/status";
                    port = 8545;
                  };
                  initialDelaySeconds = 30;
                  timeoutSeconds = 30;
                };
                securityContext.capabilities.add = ["NET_ADMIN"];
              };

              #containers.status = {
                #image = "gatehub/ethmonitor";
                #imagePullPolicy = "IfNotPresent";

                #resources = {
                  #requests.memory = "100Mi";
                  #limits.memory = "100Mi";
                  #requests.cpu = "20m";
                #};
              #};
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
