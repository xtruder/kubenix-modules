{ config, k8s, lib, ... }:

with k8s;
with lib;

{
  kubernetes.moduleDefinitions.k8s-snapshot-rule.module = {config, module, ...}: {
    options = {
      deltas = mkOption {
        description = "List of snapshot deltas";
        type = types.listOf types.str;
      };

      backend = mkOption {
        description = "Snapshot backend";
        type = types.enum ["google" "aws"];
      };

      disk = mkOption {
        description = "Disk options";
        type = types.attrs;
      };
    };

    config = {
      kubernetes.resources.customResourceDefinitions."snapshotrules.k8s-snapshots.elsdoerfer.com" = {
        spec = {
          group = "k8s-snapshots.elsdoerfer.com";
          version = "v1";
          scope = "Namespaced";
          names = {
            plural = "snapshotrules";
            singular = "snapshotrule";
            kind = "SnapshotRule";
            shortNames = ["sr"];
          };
        };
      };

      kubernetes.customResources.snapshotRules.rule = {
        metadata.name = module.name;
        spec = {
          deltas = toString config.deltas;
          backend = config.backend;
          disk = config.disk;
        };
      };
    };
  };

  kubernetes.moduleDefinitions.k8s-snapshot.module = {config, module, ...}: {
    options = {
      image = mkOption {
        description = "Image to use for k8s-snapshot";
        type = types.str;
        default = "elsdoerfer/k8s-snapshots:v2.0";
      };
    };

    config = {
      kubernetes.resources.deployments.k8s-snapshot = {
        metadata = {
          name = module.name;
          labels.app = module.name;
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "k8s-snapshot";
          template = {
            metadata.labels.app = "k8s-snapshot";
            spec = {
              serviceAccountName = module.name;

              containers.k8s-snapshot = {
                image = config.image;
              };
            };
          };
        };
      };

      kubernetes.resources.serviceAccounts.k8s-snapshot = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
      };

      kubernetes.resources.clusterRoles.k8s-snapshot = {
        apiVersion = "rbac.authorization.k8s.io/v1";
        rules = [{
          apiGroups = ["k8s-snapshots.elsdoerfer.com"];
          resources = [
            "snapshotrules"
          ];
          verbs = ["get" "list" "watch"];
        } {
          apiGroups = [""];
          resources = ["namespaces" "pods" "persistentvolumeclaims" "persistentvolumes"];
          verbs = ["get" "watch" "list"];
        }];
      };

      kubernetes.resources.clusterRoleBindings.k8s-snapshot = {
        apiVersion = "rbac.authorization.k8s.io/v1";
        metadata.name = module.name;
        metadata.labels.app = module.name;
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "k8s-snapshot";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = "k8s-snapshot";
          namespace = module.namespace;
        }];
      };
    };
  };
}
