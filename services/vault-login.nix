{ config, lib, k8s, ... }:

with lib;
with k8s;

{
  # kubenix module that implements vault login sidecar that 
  kubernetes.moduleDefinitions.vault-login-sidecar.prefixResources = false;
  kubernetes.moduleDefinitions.vault-login-sidecar.module = { name, module, config, ... }: {
    options = {
      resourcePath = mkOption {
        description = "Path to resource where to apply vault-login sidecar";
        type = types.listOf types.str;
      };

      serviceAccountName = mkOption {
        description = "Name of the service account that login role applies to";
        type = types.str;
      };

      mountContainer = mkOption {
        description = "Name of the container where to mount sidecar";
        type = types.nullOr types.str;
        default = null;
      };

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

      tokenRenewPeriod = mkOption {
        description = "Token renew period";
        type = types.int;
        default = 1800;
      };
    };

    config = mkMerge [{
      kubernetes.resources = (setAttrByPath config.resourcePath {
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
        }];
        containers.vault-token-mount = mkIf (config.mountContainer != null) {
          name = config.mountContainer;
          volumeMounts."/vault" = {
            name = "vault-token";
            mountPath = "/vault";
          };
        };
        containers.vault-token-renewer = {
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
      });
    }
    {
      kubernetes.resources.clusterRoleBindings."${name}" = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = name;
        metadata.labels.app = name;
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "system:auth-delegator";
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
