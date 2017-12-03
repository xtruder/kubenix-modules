{ config, lib, k8s, ... }:

with k8s;
with lib;

let
  hasModuleType = type:
    (filterAttrs (name: config: config.module == type) config.kubernetes.modules) != {};
in mkMerge [{
  kubernetes.moduleDefinitions.etcd-cluster.module = {name, config, ...}: {
    options = {
      size = mkOption {
        description = "Etcd cluster size";
        type = types.int;
        default = 3;
      };

      version = mkOption {
        description = "Etcd cluster version";
        type = types.str;
        default = "3.1.8";
      };

      namespace = mkOption {
        description = "Namespace where to deploy etcd cluster";
        type = types.str;
        default = "default";
      };

      backup = {
        interval = mkOption {
          description = "Backup interval in seconds";
          type = types.int;
          default = 30;
        };

        maxBackups = mkOption {
          description = "Number of backups to keep";
          type = types.int;
          default = 5;
        };

        storageType = mkOption {
          description = "Type of the storage";
          type = types.enum ["S3"];
          default = "S3";
        };
      };
    };

    config = {
      kubernetes.customResources.etcdclusters.etcd-cluster = {
        metadata.name = name;
        metadata.namespace = config.namespace;
        spec = {
          size = config.size;
          version = config.version;
          backup = {
            backupIntervalInSecond = config.backup.interval;
            maxBackups = config.backup.maxBackups;
            storageType = config.backup.storageType;
          };
        };
      };
    };
  };

  kubernetes.moduleDefinitions.etcd-operator.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Name of the etcd-operator image to deploy";
        type = types.str;
        default = "quay.io/coreos/etcd-operator:v0.7.0";
      };

      namespace = mkOption {
        description = "Namespace where to deploy etcd operator";
        type = types.str;
        default = "default";
      };
    };

    config = {
      kubernetes.resources.deployments.etcd-operator = {
        metadata.name = "etcd-operator";
        metadata.namespace = config.namespace;
        metadata.labels.app = "etcd-operator";
        spec = {
          replicas = 1;
          template = {
            metadata.labels.app = "etcd-operator";
            metadata.labels.name = name;
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

      kubernetes.resources.deployments.etcd-backup-operator = {
        metadata.name = "etcd-backup-operator";
        metadata.namespace = config.namespace;
        metadata.labels.app = "etcd-backup-operator";
        spec = {
          replicas = 1;
          template = {
            metadata.labels.app = "etcd-backup-operator";
            metadata.labels.name = name;
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

      kubernetes.resources.deployments.etcd-restore-operator = {
        metadata.name = "etcd-restore-operator";
        metadata.namespace = config.namespace;
        metadata.labels.app = "etcd-restore-operator";
        spec = {
          replicas = 1;
          template = {
            metadata.labels.app = "etcd-restore-operator";
            metadata.labels.name = name;
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
        metadata.namespace = config.namespace;
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
        metadata.namespace = config.namespace;
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "Role";
          name = name;
        };
        subjects = [{
          kind = "ServiceAccount";
          name = "default";
          namespace = config.namespace;
        }];
      };

      kubernetes.resources.roles.etcd = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = name;
        metadata.namespace = config.namespace;
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
} (mkIf (hasModuleType "etcd-cluster") {
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
})]
