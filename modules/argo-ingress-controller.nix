{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.argo-ingress-controller.module = {config, module, ...}: {
    options = {
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
      kubernetes.resources.deployments.argo-ingress-controller = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          selector.matchLabels.app = module.name;
          replicas = config.replicas;
          template = {
            metadata.name = module.name;
            metadata.labels.app = module.name;
            spec = {
              affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution = [{
                weight = 100;
                podAffinityTerm.labelSelector.matchExpressions = [{
                  key = "app";
                  operator = "In";
                  values = [module.name];
                }];
                podAffinityTerm.topologyKey = "kubernetes.io/hostname";
              }];

              containers.argot = {
                image = config.image;
                imagePullPolicy = "IfNotPresent";
                args = [
                  "argot"
                  "-v=6"
                  "-namespace"
                  module.namespace
                ] ++ config.extraArgs;
                resources.requests = {
                  cpu = "100m";
                  memory = "128Mi";
                };
                resources.limits = {
                  cpu = "100m";
                  memory = "128Mi";
                };
              };
              serviceAccountName = module.name;
            };
          };
        };
      };

      kubernetes.resources.serviceAccounts.argo-ingress-controller = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
      };

      kubernetes.resources.clusterRoles.argo-ingress-controller = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = module.name;
        metadata.labels.app = module.name;
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
        
      kubernetes.resources.clusterRoleBindings.argo-ingress-controller = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = module.name;
        metadata.labels.app = module.name;

        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = module.name;
        };

        subjects = [{
          kind = "ServiceAccount";
          name = module.name;
          namespace = module.namespace;
        }];
      };
    };
  };
}
