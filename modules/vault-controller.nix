{ config, k8s, lib, ... }:

with lib;
with k8s;

{
  kubernetes.moduleDefinitions.secret-claim.module = {config, module, ...}: {
    options = {
      name = mkOption {
        description = "Name of the secret claim";
        type = types.str;
        default = module.name;
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
        metadata.name = "secretclaims.vaultproject.io";
        spec = {
          group = "vaultproject.io";
          version = "v1";
          scope = "Namespaced";
          names = {
            plural = "secretclaims";
            singular = "secretclaim";
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

  kubernetes.moduleDefinitions.vault-controller.module = {config, module, ...}: {
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
          default = "https://vault:8200";
          type = types.str;
        };

        token = mkSecretOption {
          description = "Vault token";
          default.key = "token";
        };

        saauth = mkOption {
          description = "Whether to enable kubernetes service account auth";
          type = types.bool;
          default = false;
        };

        role = mkOption {
          description = "Kubernetes service account auth role";
          type = types.str;
          default = "vault-controller";
        };

        caCert = mkOption {
          description = "Vault ca cert secret name";
          type = types.nullOr types.str;
          default = null;
        };
      };

      namespace = mkOption {
        type = types.nullOr types.str;
        description = "Namespace where controller manages secrets";
        default = null;
      };
    };

    config = {
      kubernetes.resources.deployments.vault-controller = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          replicas = 1;
          selector.matchLabels.app = module.name;
          template = {
            metadata.labels.app = module.name;
            spec.serviceAccountName = module.name;
            spec.containers.vault-controller = {
              image = config.image;
              imagePullPolicy = "Always";
              command = [
                "/kube-vault-controller"
                "-sync-period=${config.syncPeriod}"
              ] ++ optionals (config.vault.saauth) [
                "-saauth"
                "-vaultrole=${config.vault.role}"
              ] ++ optionals (config.namespace != null) [
                "-namespace=${config.namespace}"
              ];
              env = {
                VAULT_ADDR.value = config.vault.address;
                VAULT_TOKEN = mkIf (!config.vault.saauth) (secretToEnv config.vault.token);
                VAULT_CACERT.value =
                  if (config.vault.caCert != null)
                  then "/var/lib/vault/ssl/ca.crt"
                  else "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt";
              };
              resources = {
                requests.memory = "64Mi";
                requests.cpu = "50m";
                limits.memory = "64Mi";
                limits.cpu = "100m";
              };
              volumeMounts.ssl = mkIf (config.vault.caCert != null) {
                name = "cert";
                mountPath = "/var/lib/vault/ssl/";
              };
              livenessProbe = mkIf (config.vault.caCert != null) {
                exec.command = ["/bin/sh" "-c" ''
                  if [ ! -f /tmp/ca.crt  ]; then
                    cat /var/lib/vault/ssl/ca.crt > /tmp/ca.crt
                  fi

                  if [ "$(cat /var/lib/vault/ssl/ca.crt)" == "$(cat /tmp/ca.crt)" ]; then
                    exit 0
                  else
                    exit 1
                  fi
                ''];
                periodSeconds = 30;
              };
            };
            spec.volumes.cert = mkIf (config.vault.caCert != null) {
              secret.secretName = config.vault.caCert;
            };
          };
        };
      };

      kubernetes.resources.serviceAccounts.vault-controller = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
      };

      # binding for tokenreview kubernetes API
      kubernetes.resources.clusterRoleBindings.vault-controller-tokenreview-binding = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = "${module.namespace}-${module.name}-tokenreview-binding";
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "system:auth-delegator";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = module.name;
          namespace = module.namespace;
        }];
      };

      kubernetes.resources.clusterRoleBindings.vault-controller = mkIf (config.namespace == null) {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = "${module.namespace}-${module.name}";
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "vault-controller";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = module.name;
          namespace = module.namespace;
        }];
      };

      kubernetes.resources.roleBindings.vault-controller = mkIf (config.namespace != null) {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = module.name;
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "Role";
          name = "vault-controller";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = module.name;
          namespace = module.namespace;
        }];
      };

      kubernetes.resources.clusterRoles.vault-controller = mkIf (config.namespace == null) {
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

      kubernetes.resources.roles.vault-controller = mkIf (config.namespace != null) {
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
