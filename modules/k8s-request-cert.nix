{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

{
  imports = [
    kubenix.k8s
  ];

  options.args = {
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
    submodule = {
      name = "k8s-request-cert";
      version = "1.0.0";
      description = "";
    };
    kubernetes.api = (setAttrByPath config.args.resourcePath {
      initContainers = [{
        name = "request-cert";
        image = "cockroachdb/cockroach-k8s-request-cert:0.3";
        imagePullPolicy = "IfNotPresent";
        command = ["/bin/ash" "-ecx" ''
          /request-cert \
            -namespace=''${POD_NAMESPACE} \
            -certs-dir=/cert -type=node \
            -addresses=${concatStringsSep "," config.args.addresses} \
            -symlink-ca-from=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          chmod -R o+r /cert
        ''];
        env.POD_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
        volumeMounts.cert = {
          name = "k8s-request-cert";
          mountPath = "/cert";
        };
      }];
      containers.mount-cert = mkIf (config.args.mountContainer != null) {
        name = config.args.mountContainer;
        volumeMounts.k8s-request-cert = {
          name = "k8s-request-cert";
          mountPath = "/cert";
        };
      };
      volumes.k8s-request-cert.emptyDir = {};
    });
  }
  {
    kubernetes.api.clusterroles."${name}-k8s-request-cert" = {
      apiVersion = "rbac.authorization.k8s.io/v1beta1";
      metadata.name = "${namespace}-${name}";
      metadata.labels.app = "${namespace}-${name}";
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

    kubernetes.api.clusterrolebindings."${name}-k8s-request-cert" = {
      apiVersion = "rbac.authorization.k8s.io/v1beta1";
      metadata.name = "${namespace}-${name}";
      metadata.labels.app = name;
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "${namespace}-${name}";
      };
      subjects = [{
        kind = "ServiceAccount";
        name = config.args.serviceAccountName;
        namespace = module.namespace;
      }];
    };
  }];
}