{ config, k8s, lib, ... }:

with lib;
with k8s;

{
  kubernetes.moduleDefinitions.secret-claim.module = {config, name, ...}: {
    options = {
      name = mkOption {
        description = "Name of the secret claim";
        type = types.str;
        default = name;
      };

      type = mkOption {
        description = "Type of the secret";
        type = types.enum ["Opaque" "kubernetes.io/tls"];
        default = "Opaque";
      };

      path = mkOption {
        description = "Secret path";
        type = types.str;
      };

      renew = mkOption {
        description = "Renew time in seconds";
        type = types.nullOr types.int;
        default = null;
      };

      data = mkOption {
        type = types.nullOr types.attrs;
        description = "Data to pass to get secrets";
        default = null;
      };
    };

    config = {
      kubernetes.resources.customResourceDefinitions.secret-claims = {
        kind = "CustomResourceDefinition";
        apiVersion = "apiextensions.k8s.io/v1beta1";
        metadata.name = "secretclaims.vaultproject.io";
        spec = {
          group = "vaultproject.io";
          version = "v1";
          scope = "Namespaced";
          names = {
            plural = "secretclaims";
            kind = "SecretClaim";
            shortNames = ["scl"];
          };
        };
      };

      kubernetes.customResources.secret-claims.claim = {
        metadata.name = config.name;
        spec = {
          inherit (config) type path;
        } // (optionalAttrs (config.renew != null) {
          inherit (config) renew;
        }) // (optionalAttrs (config.data != null) {
          inherit (config) data;
        });
      };
    };
  };

  kubernetes.moduleDefinitions.vault-controller.module = {config, name, module, ...}: {
    options = {
      image = mkOption {
        description = "Vault controller image to use";
        type = types.str;
        default = "xtruder/kube-vault-controller:v0.3.0";
      };

      syncPeriod = mkOption {
        type = types.str;
        description = "Secret sync period";
        default = "1m";
      };

      vault = {
        address = mkOption {
          description = "Vault address";
          default = "http://vault:8200";
          type = types.str;
        };

        token = mkSecretOption {
          description = "Vault token";
          default.key = "token";
        };
      };
    };

    config = {
      kubernetes.resources.deployments.vault-controller = {
        metadata.name = "vault-controller";
        metadata.labels.app = "vault-controller";
        spec = {
          replicas = 1;
          selector.matchLabels.app = "vault-controller";
          template = {
            metadata.labels.app = "vault-controller";
            spec.serviceAccountName = "vault-controller";
            spec.containers.vault-controller = {
              image = config.image;
              args = [
                "/kube-vault-controller"
                "--sync-period=${config.syncPeriod}"
                "--namespace=${module.namespace}"
              ];
              env = {
                VAULT_ADDR.value = config.vault.address;
                VAULT_TOKEN = secretToEnv config.vault.token;
              };
              resources = {
                requests.memory = "64Mi";
                requests.cpu = "50m";
                limits.memory = "64Mi";
                limits.cpu = "100m";
              };
            };
          };
        };
      };

      kubernetes.resources.serviceAccounts.vault-controller = {
        metadata.name = name;
        metadata.labels.app = name;
      };

      kubernetes.resources.clusterRoleBindings.vault-controller = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = "${module.namespace}-${module.name}";
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "vault-controller";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = name;
          namespace = module.namespace;
        }];
      };

      kubernetes.resources.clusterRoles.vault-controller = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = "vault-controller";
        rules = [{
          apiGroups = ["vaultproject.io"];
          resources = [
            "secretclaims"
          ];
          verbs = ["get" "list" "watch"];
        } {
          apiGroups = [""];
          resources = ["secrets"];
          verbs = ["get" "watch" "list" "create" "update" "patch" "delete"];
        }];
      };
    };
  };
}
