{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

{
  imports = [
    kubenix.k8s
  ];

  options.args = {
    image = mkOption {
      description = "Image to use for argo tunnel";
      default = "gcr.io/stackpoint-public/argot:0.5.1";
      type = types.str;
    };

    replicas = mkOption {
      description = "Number of argo tunnel replicas to run";
      type = types.int;
      default = 3;
    };

    extraArgs = mkOption {
      description = "Argo tunnel extra arguments";
      type = types.listOf types.str;
      default = [];
    };
  };

  config = {
    submodule = {
      name = "argo-ingress-controller";
      version = "1.0.0";
      description = "";
    };
    kubernetes.api.deployments.argo-ingress-controller = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        selector.matchLabels.app = name;
        replicas = config.args.replicas;
        template = {
          metadata.name = name;
          metadata.labels.app = name;
          spec = {
            affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution = [{
              weight = 100;
              podAffinityTerm.labelSelector.matchExpressions = [{
                key = "app";
                operator = "In";
                values = [name];
              }];
              podAffinityTerm.topologyKey = "kubernetes.io/hostname";
            }];

            containers.argot = {
              image = config.args.image;
              imagePullPolicy = "IfNotPresent";
              args = [
                "argot"
                "-v=6"
                "-namespace"
                module.namespace
              ] ++ config.args.extraArgs;
              resources.requests = {
                cpu = "100m";
                memory = "128Mi";
              };
              resources.limits = {
                cpu = "100m";
                memory = "128Mi";
              };
            };
            serviceAccountName = name;
          };
        };
      };
    };

    kubernetes.api.serviceaccounts.argo-ingress-controller = {
      metadata.name = name;
      metadata.labels.app = name;
    };

    kubernetes.api.clusterroles.argo-ingress-controller = {
      apiVersion = "rbac.authorization.k8s.io/v1beta1";
      metadata.name = name;
      metadata.labels.app = name;
      rules = [{
        apiGroups = [""];
        resources = ["secrets"];
        verbs = ["get"];
      } {
        apiGroups = ["" "extensions"];
        resources = ["ingresses" "services" "endpoints"];
        verbs = ["list" "get" "watch"];
      } {
        apiGroups = ["extensions"];
        resources = ["ingresses/status"];
        verbs = ["get" "update"];
      }];
    };
      
    kubernetes.api.clusterrolebindings.argo-ingress-controller = {
      apiVersion = "rbac.authorization.k8s.io/v1beta1";
      metadata.name = name;
      metadata.labels.app = name;

      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = name;
      };

      subjects = [{
        kind = "ServiceAccount";
        name = name;
        namespace = module.namespace;
      }];
    };
  };
}