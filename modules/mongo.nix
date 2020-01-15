{ config, lib, k8s, ... }:

with lib;
with k8s;

{
  kubernetes.moduleDefinitions.mongo.module = { config, module, ... }: let
    mongodConf = {
      storage.dbPath = "/data/db";
      net.port = 27017;
      net.bindIpAll = true;
      replication.replSetName = config.replicaSet;
      security = {
        authorization = if config.auth.enable then "enabled" else "disabled";
      } // (optionalAttrs config.auth.enable {
        keyFile = "/keydir/key.txt";
      });
    };
  in {
    options = {
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
      kubernetes.resources.statefulSets.mongo = {
        metadata.name = module.name;
        metadata.labels.app = module.name;

        spec = {
          selector.matchLabels.app = module.name;
          serviceName = module.name;

          podManagementPolicy = "Parallel";
          replicas = config.replicas;

          template = {
            metadata.labels.app = module.name;
            spec = {
              serviceAccountName = module.name;

              containers.mongo = {
                image = config.image;
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
                }] ++ (optional config.auth.enable {
                  name = "key";
                  mountPath = "/keydir";
                  readOnly = true;
                });
              };

              containers.mongo-sidecar = {
                image = config.sidecarImage;
                imagePullPolicy = "IfNotPresent";
                env = {
                  KUBECTL_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
                  KUBE_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
                  MONGO_SIDECAR_POD_LABELS.value = "app=${module.name}";
                  MONGO_PORT.value = "27017";
                  KUBERNETES_MONGO_SERVICE_NAME.value = module.name;
                } // (optionalAttrs config.auth.enable {
                  MONGODB_USERNAME = secretToEnv config.auth.adminUser;
                  MONGODB_PASSWORD = secretToEnv config.auth.adminPassword;
                });
              };

              volumes = {
                config.configMap.name = "mongo";
                workdir.emptyDir = {};
                key.secret = mkIf config.auth.enable {
                  secretName = config.auth.key.name;
                  defaultMode = k8s.octalToDecimal "0400";
                  items = [{
                    key = config.auth.key.key;
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
              storageClassName = mkIf (config.storage.class != null) config.storage.class;
              resources.requests.storage = config.storage.size;
            };
          }];
        };
      };

      kubernetes.resources.services.mongo = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          ports = [{
            name = "mongo";
            port = 27017;
          }];
          clusterIP = "None";
          selector.app = module.name;
        };
      };

      kubernetes.resources.configMaps.mongo = {
        metadata.name = module.name;
        metadata.labels.app = module.name;

        data."mongod.conf" = builtins.toJSON mongodConf;
      };

      kubernetes.resources.serviceAccounts.mongo = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
      };

      kubernetes.resources.clusterRoles.mongo = {
        apiVersion = "rbac.authorization.k8s.io/v1";
        metadata.name = module.name;
        metadata.labels.app = module.name;
        rules = [{
          apiGroups = [""];
          resources = [
            "pods"
            ];
            verbs = ["get" "list" "watch"];
          }];
        };

        kubernetes.resources.clusterRoleBindings.mongo = {
          apiVersion = "rbac.authorization.k8s.io/v1";
          metadata.name = module.name;
          metadata.labels.app = module.name;
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = "mongo";
          };
          subjects = [{
            kind = "ServiceAccount";
            name = module.name;
            namespace = module.namespace;
          }];
        };

        kubernetes.resources.podDisruptionBudgets.mongo = {
          metadata.name = module.name;
          metadata.labels.app = module.name;
          spec.minAvailable = "60%";
          spec.selector.matchLabels.app = module.name;
        };
      };
    };
  }
