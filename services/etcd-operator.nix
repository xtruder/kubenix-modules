{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  kubernetes.moduleDefinitions.etcd-backup.module = {name, config, ...}: {
    options = {
      etcdEndpoints = mkOption {
        description = "Etcd endpoints";
        type = types.listOf types.str;
      };

      storageType = mkOption {
        description = "Backup stroage type";
        type = types.enum ["S3"];
        default = "S3";
      };

      s3 = {
        path = mkOption {
          description = "Full S3 path";
          type = types.str;
        };

        awsSecret = mkOption {
          description = "AWS secret for backup";
          type = types.str;
        };
      };
    };

    config = {
      kubernetes.resources.customResourceDefinitions.etcdbackups = {
        kind = "CustomResourceDefinition";
        apiVersion = "apiextensions.k8s.io/v1beta1";
        metadata.name = "etcdbackups.etcd.database.coreos.com";
        spec = {
          group = "etcd.database.coreos.com";
          version = "v1beta2";
          scope = "Namespaced";
          names = {
            plural = "etcdbackups";
            kind = "EtcdBackup";
          };
        };
      };

      kubernetes.customResources.etcdbackups.etcd-backup = {
        metadata.name = name;
        spec = {
          etcdEndpoints = concatStringsSep "," config.etcdEndpoints;
          storageType = config.storageType;
          s3 = mkIf (cfg.storageType == "S3") {
            path = config.s3.path;
            awsSecret = config.s3.awsSecret;
          };
        };
      };
    };
  };

  kubernetes.moduleDefinitions.etcd-cluster.module = {name, config, ...}: {
    options = {
      size = mkOption {
        description = "Etcd cluster size";
        type = types.int;
        default = 1;
      };

      version = mkOption {
        description = "Etcd cluster version";
        type = types.str;
        default = "3.1.8";
      };
    };

    config = {
      kubernetes.resources.customResourceDefinitions.etcdclusters = {
        kind = "CustomResourceDefinition";
        apiVersion = "apiextensions.k8s.io/v1beta1";
        metadata.name = "etcdclusters.etcd.database.coreos.com";
        spec = {
          group = "etcd.database.coreos.com";
          version = "v1beta2";
          scope = "Namespaced";
          names = {
            plural = "etcdclusters";
            kind = "EtcdCluster";
            shortNames = ["etcd"];
          };
        };
      };

      kubernetes.customResources.etcdclusters.etcd-cluster = {
        metadata.name = name;
        spec = {
          size = config.size;
          version = config.version;
        };
      };
    };
  };

  kubernetes.moduleDefinitions.etcd-operator.module = {name, config, module, ...}: {
    options = {
      image = mkOption {
        description = "Name of the etcd-operator image to deploy";
        type = types.str;
        default = "quay.io/coreos/etcd-operator:v0.7.2";
      };

      backup = {
        enable = mkEnableOption "Backup operator";
      };

      restore = {
        enable = mkEnableOption "Restore operator";
      };
    };

    config = {
      kubernetes.resources.customResourceDefinitions.etcdrestores = {
        kind = "CustomResourceDefinition";
        apiVersion = "apiextensions.k8s.io/v1beta1";
        metadata.name = "etcdrestores.etcd.database.coreos.com";
        spec = {
          group = "etcd.database.coreos.com";
          version = "v1beta2";
          scope = "Namespaced";
          names = {
            plural = "etcdrestores";
            kind = "EtcdRestore";
          };
        };
      };

      kubernetes.resources.deployments.etcd-operator = {
        metadata.name = "etcd-operator";
        metadata.labels.app = "etcd-operator";
        spec = {
          replicas = 1;
          selector.matchLabels.app = "etcd-operator";
          template = {
            metadata.labels.app = "etcd-operator";
            spec.containers.etcd-operator = {
              image = config.image;
              command = ["etcd-operator"];
              env = {
                MY_POD_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
                MY_POD_NAME.valueFrom.fieldRef.fieldPath = "metadata.name";
              };
            };
          };
        };
      };

      kubernetes.resources.deployments.etcd-backup-operator = mkIf config.backup.enable {
        metadata.name = "etcd-backup-operator";
        metadata.labels.app = "etcd-backup-operator";
        spec = {
          replicas = 1;
          selector.matchLabels.app = "etcd-backup-operator";
          template = {
            metadata.labels.app = "etcd-backup-operator";
            spec.containers.etcd-backup-operator = {
              image = config.image;
              imagePullPolicy = "Always";
              command = ["etcd-backup-operator"];
              env = {
                MY_POD_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
                MY_POD_NAME.valueFrom.fieldRef.fieldPath = "metadata.name";
              };
            };
          };
        };
      };

      kubernetes.resources.deployments.etcd-restore-operator = mkIf config.restore.enable {
        metadata.name = "etcd-restore-operator";
        metadata.labels.app = "etcd-restore-operator";
        spec = {
          replicas = 1;
          selector.matchLabels.app = "etcd-restore-operator";
          template = {
            metadata.labels.app = "etcd-restore-operator";
            spec.containers.etcd-backup-operator = {
              image = config.image;
              imagePullPolicy = "Always";
              command = ["etcd-restore-operator"];
              env = {
                MY_POD_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
                MY_POD_NAME.valueFrom.fieldRef.fieldPath = "metadata.name";
                SERVICE_ADDR.value = "${name}-restore-operator";
              };
            };
          };
        };
      };

      kubernetes.resources.services.etcd-restore-operator = {
        metadata.name = "etcd-restore-operator";
        spec = {
          selector.app = "etcd-restore-operator";
          ports = [{
            protocol = "TCP";
            port = 19999;
          }];
        };
      };

      kubernetes.resources.roleBindings.etcd = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = name;
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "Role";
          name = name;
        };
        subjects = [{
          kind = "ServiceAccount";
          name = "default";
          namespace = module.namespace;
        }];
      };

      kubernetes.resources.roles.etcd = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = name;
        rules = [{
          apiGroups = ["etcd.database.coreos.com"];
          resources = [
            "etcdclusters"
            "etcdbackups"
            "etcdrestores"
          ];
          verbs = ["*"];
        } {
          apiGroups = ["apiextensions.k8s.io"];
          resources = ["customresourcedefinitions"];
          verbs = ["*"];
        } {
          apiGroups = [""];
          resources = [
            "pods"
            "services"
            "endpoints"
            "persistentvolumeclaims"
            "events"
          ];
          verbs = ["*"];
        } {
          apiGroups = ["apps"];
          resources = ["deployments"];
          verbs = ["*"];
        } {
          apiGroups = [""];
          resources = ["secrets"];
          verbs = ["get"];
        }];
      };
    };
  };
}
