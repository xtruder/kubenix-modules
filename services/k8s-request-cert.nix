{ config, lib, k8s, ... }:

with lib;
with k8s;

{
  kubernetes.moduleDefinitions.k8s-request-cert.prefixResources = false;
  kubernetes.moduleDefinitions.k8s-request-cert.module = { name, module, config, ... }: {
    options = {
      resourcePath = mkOption {
        description = "Path to resource where to apply vault-login sidecar";
        type = types.listOf types.str;
      };

      serviceAccountName = mkOption {
        description = "Name of the service account";
        type = types.str;
      };

      mountContainer = mkOption {
        description = "Name of the container where to mount cert";
        type = types.nullOr types.str;
        default = null;
      };

      addresses = mkOption {
        description = "List of k8s server addresses";
        type = types.listOf types.str;
        default = [];
      };
    };

    config = mkMerge [{
      kubernetes.resources = (setAttrByPath config.resourcePath {
        initContainers = [{
          name = "request-cert";
          image = "cockroachdb/cockroach-k8s-request-cert:0.3";
          imagePullPolicy = "IfNotPresent";
          command = ["/bin/ash" "-ecx" ''
            /request-cert \
              -namespace=''${POD_NAMESPACE} \
              -certs-dir=/cert -type=node \
              -addresses=${concatStringsSep "," config.addresses} \
              -symlink-ca-from=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
            chmod -R o+r /cert
          ''];
          env.POD_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
          volumeMounts.cert = {
            name = "k8s-request-cert";
            mountPath = "/cert";
          };
        }];
        containers.mount-cert = mkIf (config.mountContainer != null) {
          name = config.mountContainer;
          volumeMounts.k8s-request-cert = {
            name = "k8s-request-cert";
            mountPath = "/cert";
          };
        };
        volumes.k8s-request-cert.emptyDir = {};
      });
    }
    {
      kubernetes.resources.clusterRoles."${module.name}-k8s-request-cert" = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = "${module.namespace}-${module.name}";
        metadata.labels.app = "${module.namespace}-${module.name}";
        rules = [{
          apiGroups = ["certificates.k8s.io"];
          resources = ["certificatesigningrequests"];
          verbs = ["create" "get" "list" "watch"];
        } {
          apiGroups = [""];
          resources = ["secrets"];
          verbs = ["list"];
        } {
          apiGroups = [""];
          resources = ["secrets"];
          verbs = ["create"];
        } {
          apiGroups = [""];
          resources = ["secrets"];
          verbs = ["update" "get" "patch"];
        }];
      };

      kubernetes.resources.clusterRoleBindings."${module.name}-k8s-request-cert" = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = "${module.namespace}-${module.name}";
        metadata.labels.app = name;
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "${module.namespace}-${module.name}";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = config.serviceAccountName;
          namespace = module.namespace;
        }];
      };
    }];
  };
}
