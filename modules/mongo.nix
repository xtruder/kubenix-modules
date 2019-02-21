{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

let
  mongodConf = {
    storage.dbPath = "/data/db";
    net.port = 27017;
    net.bindIpAll = true;
    replication.replSetName = config.args.replicaSet;
    security = {
      authorization = if config.args.auth.enable then "enabled" else "disabled";
    } // (optionalAttrs config.args.auth.enable {
      keyFile = "/keydir/key.txt";
    });
  };
in {
  imports = [
    kubenix.k8s
  ];

  options.args = {
    image = mkOption {
      description = "Mongodb image to run";
      type = types.str;
      default = "mongo:3.6";
    };

    replicas = mkOption {
      description = "Number of mongodb replicas to run";
      type = types.int;
      default = 3;
    };

    sidecarImage = mkOption {
      description = "Mongo sidecar image";
      type = types.str;
      default = "cvallance/mongo-k8s-sidecar";
    };

    replicaSet = mkOption {
      description = "Name of the mongo replicaset";
      default = "rs0";
      type = types.str;
    };

    auth = {
      enable = mkEnableOption "mongo RBAC authorization";

      adminUser = mkSecretOption {
        description = "Mongo admin username secret";
        default.key = "username";
      };

      adminPassword = mkSecretOption {
        description = "Mongo admin password secret";
        default.key = "password";
      };	

      key = mkSecretOption {
        description = "Mongo shared secret";
        default.key = "key";
      };
    };

    storage = {
      size = mkOption {
        description = "Mongo storage size";
        type = types.str;
        default = "10Gi";
      };

      class = mkOption {
        description = "Mongodb storage class";
        type = types.nullOr types.str;
        default = null;
      };
    };
  };

  config = {
    submodule = {
      name = "mongo";
      version = "1.0.0";
      description = "";
    };
    kubernetes.api.statefulsets.mongo = {
      metadata.name = name;
      metadata.labels.app = name;

      spec = {
        serviceName = name;
        podManagementPolicy = "Parallel";
        replicas = config.args.replicas;

        template = {
          metadata.labels.app = name;
          spec = {
            serviceAccountName = name;

            containers.mongo = {
              image = config.args.image;
              imagePullPolicy = "Always";
              livenessProbe = {
                exec.command = ["mongo" "--eval" "db.adminCommand('ping')"];
                initialDelaySeconds = 30;
                timeoutSeconds = 5;
              };
              readinessProbe = {
                exec.command = ["mongo" "--eval" "db.adminCommand('ping')"];
                initialDelaySeconds = 5;
                timeoutSeconds = 1;
              };
              command = ["mongod" "--config" "/etc/mongod.conf"];
              ports = [{
                containerPort = 27017;
              }];
              volumeMounts = [{
                name = "datadir";
                mountPath = "/data/db";
              } {
                name = "config";
                mountPath = "/etc/mongod.conf";
                subPath = "mongod.conf";
              } {
                name = "workdir";
                mountPath = "/work-dir";
              }] ++ (optional config.args.auth.enable {
                name = "key";
                mountPath = "/keydir";
                readOnly = true;
              });
            };

            containers.mongo-sidecar = {
              image = config.args.sidecarImage;
              imagePullPolicy = "IfNotPresent";
              env = {
                KUBECTL_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
                KUBE_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
                MONGO_SIDECAR_POD_LABELS.value = "app=${name}";
                MONGO_PORT.value = "27017";
                KUBERNETES_MONGO_SERVICE_NAME.value = name;
              } // (optionalAttrs config.args.auth.enable {
                MONGODB_USERNAME = secretToEnv config.args.auth.adminUser;
                MONGODB_PASSWORD = secretToEnv config.args.auth.adminPassword;
              });
            };

            volumes = {
              config.args.configMap.name = "mongo";
              workdir.emptyDir = {};
              key.secret = mkIf config.args.auth.enable {
                secretName = config.args.auth.key.name;
                defaultMode = k8s.octalToDecimal "0400";
                items = [{
                  key = config.args.auth.key.key;
                  path = "key.txt";
                }];
              };
            };
          };
        };

        volumeClaimTemplates = [{
          metadata.name = "datadir";
          spec = {
            accessModes = ["ReadWriteOnce"];
            storageClassName = mkIf (config.args.storage.class != null) config.args.storage.class;
            resources.requests.storage = config.args.storage.size;
          };
        }];
      };
    };

    kubernetes.api.services.mongo = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        ports = [{
          name = "mongo";
          port = 27017;
        }];
        clusterIP = "None";
        selector.app = name;
      };
    };

    kubernetes.api.configmaps.mongo = {
      metadata.name = name;
      metadata.labels.app = name;

      data."mongod.conf" = builtins.toJSON mongodConf;
    };

    kubernetes.api.serviceaccounts.mongo = {
      metadata.name = name;
      metadata.labels.app = name;
    };

    kubernetes.api.clusterroles.mongo = {
      apiVersion = "rbac.authorization.k8s.io/v1";
      metadata.name = name;
      metadata.labels.app = name;
      rules = [{
        apiGroups = [""];
        resources = [
          "pods"
          ];
          verbs = ["get" "list" "watch"];
        }];
      };

      kubernetes.api.clusterrolebindings.mongo = {
        apiVersion = "rbac.authorization.k8s.io/v1";
        metadata.name = name;
        metadata.labels.app = name;
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "mongo";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = name;
          namespace = module.namespace;
        }];
      };

      kubernetes.api.poddisruptionbudgets.mongo = {
        metadata.name = name;
        metadata.labels.app = name;
        spec.minAvailable = "60%";
        spec.selector.matchLabels.app = name;
      };
    };
  };
}