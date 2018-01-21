{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.pachyderm.module = {name, config, module, ...}: {
    options = {
      image = mkOption {
        description = "Pachd image to use";
        type = types.str;
        default = "pachyderm/pachd:1.6.6";
      };

      replicas = mkOption {
        type = types.int;
        default = 1;
        description = "Number of pachd replicas to run";
      };

      workerImage = mkOption {
        description = "Name of the image to use for worker";
        type = types.str;
        default = "pachyderm/worker:1.6.6";
      };

      enableUsageMetrics = mkOption {
        description = "Whether to enable usage metrics";
        type = types.bool;
        default = true;
      };

      imagePullSecret = mkOption {
        description = "Name of the secret to use for pulling images";
        type = types.nullOr types.str;
        default = null;
      };

      local = {
        enable = mkOption {
          description = "Whether to use local storage for pachyderm";
          type = types.bool;
          default = false;
        };

        path = mkOption {
          description = "Local storage path";
          type = types.path;
          default = "/var/pachyderm/pachd";
        };
      };

      s3 = {
        enable = mkOption {
          description = "Whether to enable minio storage backend";
          type = types.bool;
          default = false;
        };

        accessKey = mkOption {
          description = "Access key for s3";
          type = types.str;
        };

        secretKey = mkOption {
          description = "Secret key for s3";
          type = types.str;
        };

        bucketName = mkOption {
          description = "Name of the S3 bucket";
          type = types.str;
        };

        endpoint = mkOption {
          description = "S3 endpoint";
          type = types.str;
        };

        secure = mkOption {
          description = "Whether secure connection is needed for S3";
          type = types.bool;
          default = false;
        };

        signature = mkOption {
          description = "Type of the S3 signature to use";
          type = types.enum ["S3v2" "S3v4"];
          default = "S3v4";
        };
      };

      google = {
        enable = mkOption {
          description = "Whether to enable google storage backend";
          type = types.bool;
          default = false;
        };

        bucketName = mkOption {
          description = "Name of the gce bucket to use";
          type = types.str;
        };
      };

      amazon = {
        enable = mkOption {
          description = "Whether to enable amazon storage backend";
          type = types.bool;
          default = false;
        };

        accessKey = mkOption {
          description = "Access key for s3";
          type = types.str;
        };

        secretKey = mkOption {
          description = "Secret key for s3";
          type = types.str;
        };

        bucketName = mkOption {
          description = "Name of the S3 bucket";
          type = types.str;
        };
      };
    };

    config = {
      kubernetes.resources.deployments.pachd = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          replicas = config.replicas;
          selector.matchLabels.app = name;
          template = {
            metadata.name = name;
            metadata.labels.app = name;
            spec = {
              containers.pachd = {
                image = config.image;
                imagePullPolicy = "IfNotPresent";
                securityContext.privileged = true;
                ports = [{
                  name = "api-grpc-port";
                  containerPort = 650;
                  protocol = "TCP";
                } {
                  name = "trace-port";
                  containerPort = 651;
                } {
                  name = "api-http-port";
                  containerPort = 652;
                }];
                env = {
                  PACH_ROOT.value = "/pach";
                  NUM_SHARDS.value = "16";
                  STORAGE_BACKEND.value =
                    if config.local.enable then "LOCAL"
                    else if config.s3.enable then "MINIO"
                    else if config.google.enable then "GOOGLE"
                    else if config.amazon.enable then "AMAZON"
                    else throw "no pachyderm storage enabled";
                  STORAGE_HOST_PATH = mkIf (config.local.enable) {
                    value = config.local.path;
                  };
                  PACHD_POD_NAMESPACE.valueFrom.fieldRef = {
                    apiVersion = "v1";
                    fieldPath = "metadata.namespace";
                  };
                  WORKER_IMAGE.value = config.workerImage;
                  WORKER_SIDECAR_IMAGE.value = config.image;
                  WORKER_IMAGE_PULL_POLICY.value = "IfNotPresent";
                  PACHD_VERSION.value = elemAt (splitString ":" config.image) 1;
                  METRICS.value = if config.enableUsageMetrics then "true" else "false";
                  LOG_LEVEL.value = "info";
                  BLOCK_CACHE_BYTES.value = "0G";
                  PACHYDERM_AUTHENTICATION_DISABLED_FOR_TESTING.value = "false";
                  IMAGE_PULL_SECRET.value = config.imagePullSecret;
                };
                resources.requests = {
                  cpu = "250m";
                  memory = "512M";
                };
                volumeMounts.pachdvol = {
                  name = "pachdvol";
                  mountPath = "/pach";
                };
                volumeMounts.pachyderm-storage-secret = {
                  name = "pachyderm-storage-secret";
                  mountPath = "/pachyderm-storage-secret";
                };
              };
              volumes.pachdvol = if config.local.enable then {
                hostPath.path = config.local.path;
              } else {
                emptyDir = {};
              };
              volumes.pachyderm-storage-secret = {
                secret.secretName = "pachyderm-storage-secret";
              };
              serviceAccountName = name;
            };
          };
        };
      };

      kubernetes.resources.services.pachd = {
        metadata.name = "pachd";
        metadata.labels.app = name;
        spec = {
          ports = [{
            name = "api-grpc-port";
            port = 650;
            targetPort = 650;
          } {
            name = "trace-port";
            port = 651;
            targetPort = 651;
          } {
            name = "api-http-port";
            port = 652;
            targetPort = 652;
          }];
          selector.app = name;
        };
      };

      kubernetes.resources.serviceAccounts.pachyderm = {
        metadata.name = name;
        metadata.labels.app = name;
      };

      kubernetes.resources.secrets.pachyderm-storage-secret = {
        metadata.name = "pachyderm-storage-secret";
        metadata.labels.app = name;
        data = mkMerge [
          (mkIf config.s3.enable {
            minio-id = toBase64 config.s3.accessKey;
            minio-secret = toBase64 config.s3.secretKey;
            minio-bucket = toBase64 config.s3.bucketName;
            minio-endpoint = toBase64 config.s3.endpoint;
            minio-secure = toBase64 (if config.s3.secure then "1" else "0");
            minio-signature = toBase64 config.s3.signature;
          })
          (mkIf config.google.enable {
            google-bucket = toBase64 config.google.bucketName;
          })
          (mkIf config.amazon.enable {
            amazon-bucket = toBase64 config.amazon.bucketName;
            amazon-id = toBase64 config.amazon.accessKey;
            amazon-region = toBase64 config.amazon.region;
            amazon-secret = toBase64 config.amazon.secretKey;
          })
        ];
      };

      kubernetes.resources.clusterRoleBindings.pachyderm = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = "pachyderm";
        metadata.labels.app = "pachyderm";
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "pachyderm";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = name;
          namespace = module.namespace;
        }];
      };

      kubernetes.resources.clusterRoles.pachyderm = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = "pachyderm";
        metadata.labels.app = "pachyderm";
        rules = [{
          apiGroups = [""];
          resources = [
            "nodes"
            "pods"
            "pods/log"
            "endpoints"
          ];
          verbs = ["get" "list" "watch"];
        } {
          apiGroups = [""];
          resources = [
            "replicationcontrollers"
            "services"
          ];
          verbs = ["get" "list" "watch" "create" "update" "delete"];
        } {
          apiGroups = [""];
          resources = [
            "secrets"
          ];
          verbs = ["get" "list" "watch" "create" "update" "delete"];
          resourceNames = ["pachyderm-storage-secret"];
        }]; 
      };
    };
  };
}
