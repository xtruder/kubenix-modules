{ config, lib, k8s, ... }:

with lib;
with k8s;

{
  # kubenix module that logins to vault using different auth methods like k8s auth
  # and writes token to secret
  kubernetes.moduleDefinitions.vault-login.module = { name, module, config, ... }: {
    options = {
      method = mkOption {
        description = "Login method";
        type = types.enum ["kubernetes"];
        default = "kubernetes";
      };

      vault = {
        address = mkOption {
          description = "Vault address";
          default = "http://vault:8200";
          type = types.str;
        };

        caCert = mkOption {
          description = "Name of the secret for vault cert";
          type = types.nullOr types.str;
          default = null;
        };

        role = mkOption {
          description = "Login role to use";
          type = types.str;
        };
      };

      secretName = mkOption {
        description = "Name of the secret where to write token";
        type = types.str;
        default = name;
      };

      tokenRenewPeriod = mkOption {
        description = "Token renew period";
        type = types.int;
        default = 1800;
      };
    };

    config = {
      kubernetes.resources.deployments.vault-login = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          replicas = 1;
          selector.matchLabels.app = name;
          template = {
            metadata.name = name;
            metadata.labels.app = name;
            spec = {
              serviceAccountName = name;
              initContainers = [{
                name = "vault-login";
                image = "vault";
                imagePullPolicy = "IfNotPresent";
                env = {
                  VAULT_CACERT = mkIf (config.vault.caCert != null) {
                    value = "/etc/certs/vault/ca.crt";
                  };
                  VAULT_ADDR.value = config.vault.address;
                };
                command = ["sh" "-ec" ''
                  vault write -field=token auth/kubernetes/login \
                    role=${config.vault.role} \
                    jwt=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) > /vault/token
                  echo "vault token retrived"
                ''];
                volumeMounts."/etc/certs/vault" = mkIf (config.vault.caCert != null) {
                  name = "vault-cert";
                  mountPath = "/etc/certs/vault";
                };
                volumeMounts."/vault" = {
                  name = "vault-token";
                  mountPath = "/vault";
                };
              } {
                name = "write-token";
                image = "lachlanevenson/k8s-kubectl:v1.9.4";
                imagePullPolicy = "IfNotPresent";
                command = ["sh" "-ec" ''
                  export VAULT_TOKEN=$(cat /vault/token | base64)

                  cat <<EOF | kubectl apply -f -
                  apiVersion: v1
                  kind: Secret
                  metadata:
                    name: ${config.secretName}
                    namespace: ${module.namespace}
                  data:
                    token: $VAULT_TOKEN
                  EOF
                ''];
                volumeMounts = [{
                  name = "vault-token";
                  mountPath = "/vault";
                }];
              }];
              containers.token-renewer = {
                image = "vault";
                imagePullPolicy = "IfNotPresent";
                command = ["sh" "-ec" ''
                  export VAULT_TOKEN=$(cat /vault/token)

                  while true; do
                    echo "renewing vault token"
                    vault token renew >/dev/null
                    sleep ${toString config.tokenRenewPeriod}
                  done
                ''];
                env = {
                  VAULT_CACERT = mkIf (config.vault.caCert != null) {
                    value = "/etc/certs/vault/ca.crt";
                  };
                  VAULT_ADDR.value = config.vault.address;
                };
                volumeMounts."/etc/certs/vault" = mkIf (config.vault.caCert != null) {
                  name = "vault-cert";
                  mountPath = "/etc/certs/vault";
                };
                volumeMounts."/vault" = {
                  name = "vault-token";
                  mountPath = "/vault";
                };
              };
              volumes.vault-cert = mkIf (config.vault.caCert != null) {
                secret.secretName = config.vault.caCert;
              };
              volumes.vault-token.emptyDir = {};
            };
          };
        };
      };

      kubernetes.resources.serviceAccounts.vault-login = {
        metadata.name = name;
        metadata.labels.app = name;
      };

      kubernetes.resources.clusterRoleBindings.vault-login-tokenreview-binding = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = "${module.namespace}-${name}-vault-login";
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "system:auth-delegator";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = name;
          namespace = module.namespace;
        }];
      };

      kubernetes.resources.roles.vault-login = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = name;
        metadata.labels.app = name;
        rules = [{
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
          resourceNames = [config.secretName];
        }];
      };

      kubernetes.resources.roleBindings.vault-login = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = name;
        metadata.labels.app = name;
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "Role";
          name = name;
        };
        subjects = [{
          kind = "ServiceAccount";
          name = name;
        }];
      };
    };
  };
}
