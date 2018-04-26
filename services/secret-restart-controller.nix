{ config, lib, k8s, ... }:

with lib;

{
  config.kubernetes.moduleDefinitions.secret-restart-controller.module = {name, config, module, ...}: {
    options = {
      image = mkOption {
        description = "Name of the secret-restart-controller image to use";
        type = types.str;
        default = "xtruder/k8s-secret-restart-controller";
      };

      namespace = mkOption {
        description = "Namespace where to run secret restart controller (if null in all namespaces)";
        type = types.nullOr types.str;
        default = module.namespace;
      };
    };

    config = {
      kubernetes.resources.deployments.secret-restart-controller = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          selector.matchLabels.app = name;
          template = {
            metadata.labels.app = name;
            spec = {
              serviceAccountName = "secret-restart-controller";
              containers.secret-restart-controller = {
                image = config.image;
                command = [
                  "/bin/k8s-secret-restart-controller"
                  "-v=5"
                ] ++ optionals (config.namespace != null) [
                  "-namespace"
                  "$(POD_NAMESPACE)"
                ];
                resources.requests = {
                  cpu = "50m";
                  memory = "100Mi";
                };
              };
            };
          };
        };
      };
      kubernetes.resources.serviceAccounts.secret-restart-controller = {
        metadata.name = name;
        metadata.labels.app = name;
      };
      kubernetes.resources.clusterRoles.secret-restart-controller = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = name;
        metadata.labels.app = name;
        rules = [{
          apiGroups = [""];
          resources = ["secrets" "pods"];
          verbs = ["get" "list" "watch"];
        } {
          apiGroups = [""];
          resources = ["pods/eviction"];
          verbs = ["create"];
        }];
      };
      kubernetes.resources.clusterRoleBindings.secret-restart-controller = {
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
  };
}
