{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.dashd.module = {name, config, ...}: let
  in {
    options = {
      image = mkOption {
        description = "Name of the dashd image to use";
        type = types.str;
        default = "dashpay/dashd";
      };

      replicas = mkOption {
        description = "Number of dashd replicas";
        type = types.int;
        default = 1;
      };

      testnet = mkOption {
        description = "Testnet";
        default = true;
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
      kubernetes.resources.statefulSets.dashd = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          replicas = config.replicas;
          serviceName = name;
          podManagementPolicy = "Parallel";
          template = {
            metadata.labels.app = name;
            spec = {
              securityContext.fsGroup = 1000;

              containers.dasd = {
                image = config.image;
                env.TESTNET.value = toString config.testnet;

                volumeMounts = [{
                  name = "storage";
                  mountPath = "/dash";
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
            };
          };
          volumeClaimTemplates = [{
            metadata.name = "storage";
            spec = {
              accessModes = ["ReadWriteOnce"];
              storageClassName = mkIf (config.storage.class != null) config.storage.class;
              resources.requests.storage = config.storage.size;
            };
          }];
        };
      };

      kubernetes.resources.services.dashd = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          type = "NodePort";
          selector.app = name;
          ports = [{
            name = "rpc";
            port = 9999;
          } {
            name = "p2p";
            port = 9998;
          }];
        };
      };
    };
  };
}
