{ config, k8s, ... }:

let
  vault = "https://vault:8200";
in {
  require = import ../services/module-list.nix;

  kubernetes.modules.etcd.module = "etcd";

  # create dummy certificate for bootstraping vault
  kubernetes.modules.ca-deployer = {
    module = "deployer";

    configuration.runAsJob = true;
    configuration.configuration = {
      provider.kubernetes = {
        host = "https://kubernetes";
        cluster_ca_certificate = ''''${file("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")}'';
        token = ''''${file("/var/run/secrets/kubernetes.io/serviceaccount/token")}''; 
      };

      resource.tls_private_key.ca = {
        algorithm = "ECDSA";
        ecdsa_curve = "P521";
      };

      resource.tls_self_signed_cert.ca = {
        key_algorithm = ''''${tls_private_key.ca.algorithm}'';
        private_key_pem = ''''${tls_private_key.ca.private_key_pem}'';
        is_ca_certificate = true;
        validity_period_hours = 26280;
        early_renewal_hours = 8760;
        allowed_uses = ["cert_signing"];
        subject = {
          common_name = "Dummy Ltd. Root";
        };
      };

      resource.tls_private_key.vault = {
        algorithm = "ECDSA";
        ecdsa_curve = "P521";
      };

      resource.tls_cert_request.vault = {
        key_algorithm = ''''${tls_private_key.vault.algorithm}'';
        private_key_pem = ''''${tls_private_key.vault.private_key_pem}'';
        dns_names = ["vault"];
        ip_addresses = ["127.0.0.1"];
        subject.common_name = "vault";
      };

      resource.tls_locally_signed_cert.vault = {
        cert_request_pem = ''''${tls_cert_request.vault.cert_request_pem}'';
        ca_key_algorithm = ''''${tls_private_key.ca.algorithm}'';
        ca_private_key_pem = ''''${tls_private_key.ca.private_key_pem}'';
        ca_cert_pem = ''''${tls_self_signed_cert.ca.cert_pem}'';
        validity_period_hours = 17520;
        early_renewal_hours = 8760;
        allowed_uses = ["server_auth"];
      };

      resource.kubernetes_secret.vault = {
        metadata.name = "vault-cert";
        data = {
          "ca.crt" = ''''${tls_self_signed_cert.ca.cert_pem}'';
          "tls.key" = ''''${tls_private_key.vault.private_key_pem}'';
          "tls.crt" = ''''${tls_locally_signed_cert.vault.cert_pem}'';
        };
        type = "kubernetes.io/tls";
      };
    };
  };

  kubernetes.resources.roles.ca-deployer = {
    apiVersion = "rbac.authorization.k8s.io/v1beta1";
    rules = [{
      apiGroups = [""];
      resources = ["secrets"];
      verbs = ["get" "create" "update" "patch" "delete"];
    }];
  };

  kubernetes.resources.roleBindings.ca-deployer = {
    apiVersion = "rbac.authorization.k8s.io/v1beta1";
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io";
      kind = "Role";
      name = "ca-deployer";
    };
    subjects = [{
      kind = "ServiceAccount";
      name = "ca-deployer";
    }];
  };

  kubernetes.modules.vault-deployer = {
    module = "deployer";

    configuration.kubernetes.resources.deployments.deployer.spec.template.spec = {
      initContainers= [{
        name = "vault-login";
        image = "vault";
        imagePullPolicy = "IfNotPresent";
        command = ["sh" "-ec" ''
          vault write -address=${vault} -ca-cert=/etc/certs/vault/ca.crt -field=token auth/kubernetes/login role=deployer jwt=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) > /vault/token
          echo "Token retrived"
        ''];
        volumeMounts = [{
          name = "vault-cert";
          mountPath = "/etc/certs/vault";
        } {
          name = "vault-token";
          mountPath = "/vault";
        }];
      }];
      containers.deployer.volumeMounts = [{
        name = "vault-cert";
        mountPath = "/etc/certs/vault";
      } {
        name = "vault-token";
        mountPath = "/vault";
      }];
      containers.token-renewer = {
        image = "vault";
        imagePullPolicy = "IfNotPresent";
        command = ["sh" "-ec" ''
          export VAULT_TOKEN=$(cat /vault/token)

          while true; do
            echo "renewing token"
            vault token renew -address=${vault} -ca-cert=/etc/certs/vault/ca.crt $(cat /vault/token)
            sleep 1800
          done
        ''];
        volumeMounts = [{
          name = "vault-cert";
          mountPath = "/etc/certs/vault";
        } {
          name = "vault-token";
          mountPath = "/vault";
        }];
      };

      volumes.vault-cert.secret.secretName = "vault-cert";
      volumes.vault-token.emptyDir = {};
    };
    configuration.configuration = {
      terraform.backend.etcdv3 = {
        endpoints = ["http://etcd:2379"];
        prefix = "deployer/";
      };

      provider.vault = {
        address = vault;
        token = ''''${file("/vault/token")}'';
        ca_cert_file = "/etc/certs/vault/ca.crt";
      };

      resource.vault_mount.rootca = {
        type = "pki";
        path = "rootca";
        description = "Root CA";
      };

      resource.vault_mount.pki = {
        type = "pki";
        path = "pki";
        description = "Intermeddiate cert";
      };

      # generate root ca
      resource.vault_generic_secret.rootca = {
        path = "rootca/root/generate/internal";
        disable_read = true;
        data_json = builtins.toJSON {
          key_type = "ec";
          key_bits = 256;
          ttl = "87600h"; # 10 years
        };
        depends_on = ["vault_mount.rootca"];
      };

      # generate intermediate cert csr
      resource.vault_generic_secret.ca_csr = {
        path = "pki/intermediate/generate/internal";
        disable_read = true;
        data_json = builtins.toJSON {
          common_name = "example.com";
          key_type = "ec";
          key_bits = 256;
          ttl = "8760h"; # 1 year
        };
        depends_on = ["vault_mount.pki"];
      };

      # sign intermediate cert with root certificate
      resource.vault_generic_secret.ca_sign = {
        path = "rootca/root/sign-intermediate";
        disable_read = true;
        data_json = ''{
          "csr": "''${replace(vault_generic_secret.ca_csr.data["csr"], "\n", "\\n")}",
          "format": "pem_bundle"
        }'';
        depends_on = ["vault_generic_secret.ca_csr"];
      };

      resource.vault_generic_secret.ca = {
        path = "pki/intermediate/set-signed";
        disable_read = true;
        data_json = ''{
          "certificate": "''${replace(vault_generic_secret.ca_sign.data["certificate"], "\n", "\\n")}"
        }'';
        depends_on = ["vault_generic_secret.ca_sign"];
      };

      resource.vault_generic_secret.pki-roles-vault-cert = {
        path = "pki/roles/vault";
        data_json = builtins.toJSON {
          allow_any_name = true;
          allowed_domains = ["vault" "vault.example.com"];
        };
        depends_on = ["vault_generic_secret.ca"];
      };

      resource.vault_audit.logstash = {
        path = "logstash";
        description = "Logstash audit backend";
        type = "socket";
        options = {
          address = "logstash-vault:65100";
          socket_type = "tcp";
        };
      };

      resource.vault_policy.reader = {
        name = "reader";
        policy = ''
          path "secret/*" {
            capabilities = ["read", "list"]
          }

          path "pki/issue/*" {
            capabilities = ["create", "update"]
          }
        '';
      };

      resource.vault_generic_secret.auth_kubernetes_role_vault_controller = {
        path = "auth/kubernetes/role/vault-controller";
        data_json = builtins.toJSON {
          bound_service_account_names = "vault-controller";
          bound_service_account_namespaces = "default";
          policies = ["default" "reader"];
          period = "1h";
        };
        depends_on = ["vault_policy.reader"];
      };
    };
  };

  kubernetes.resources.clusterRoleBindings.vault-deployer-tokenreview-binding = {
    apiVersion = "rbac.authorization.k8s.io/v1beta1";
    metadata.name = "vault-deployer-tokenreview-binding";
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io";
      kind = "ClusterRole";
      name = "system:auth-delegator";
    };
    subjects = [{
      kind = "ServiceAccount";
      name = "vault-deployer";
      namespace = "default";
    }];
  };

  # create dummy certificate for bootstraping vault
  kubernetes.modules.vault-bootstraper = {
    module = "deployer";

    configuration.vars.vault_token.valueFrom.secretKeyRef ={
      name = "vault-root-token";
      key = "token";
    };

    configuration.kubernetes.resources.jobs.deployer.spec.template.spec = {
      containers.deployer.volumeMounts = [{
        name = "vault-cert";
        mountPath = "/etc/certs/vault";
      }];

      volumes.vault-cert.secret.secretName = "vault-cert";
    };

    configuration.runAsJob = true;
    configuration.configuration = {
      variable.vault_token = {};

      provider.vault = {
        address = vault;
        token = ''''${var.vault_token}'';
        ca_cert_file = "/etc/certs/vault/ca.crt";
      };

      resource.vault_auth_backend.kubernetes = {
        type = "kubernetes";
      };

      resource.vault_generic_secret.auth_kubernetes_config = {
        path = "auth/kubernetes/config";
        data_json = ''{
            "kubernetes_host": "https://kubernetes:443",
            "kubernetes_ca_cert": "''${replace(file("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"), "\n", "\\n")}"
          }'';
        depends_on = ["vault_auth_backend.kubernetes"];
      };

      resource.vault_policy.provisioner = {
        name = "provisioner";
        policy = ''
          # Manage auth backends broadly across Vault
          path "auth/*" {
            capabilities = ["create", "read", "update", "delete", "list", "sudo"]
          }

          # List, create, update, and delete auth backends
          path "sys/auth/*" {
            capabilities = ["create", "read", "update", "delete", "sudo"]
          }

          # List existing policies
          path "sys/policy" {
            capabilities = ["read"]
          }

          # Create and manage ACL policies
          path "sys/policy/*" {
            capabilities = ["create", "read", "update", "delete", "list"]
          }

          # List existing audits
          path "sys/audit" {
            capabilities = ["read", "sudo"]
          }

          # Create and manage audit backends
          path "sys/audit/*" {
            capabilities = ["create", "read", "update", "delete", "list", "sudo"]
          }

          path "sys/mounts" {
            capabilities = ["read"]
          }

          path "sys/mounts/*" {
            capabilities = ["create", "read", "update", "delete", "list"]
          }

          # List, create, update, and delete key/value secrets
          path "secret/*" {
            capabilities = ["create", "read", "update", "delete", "list"]
          }

          # List, create, update, and delete root cert
          path "rootca/*" {
            capabilities = ["create", "read", "update", "delete", "list"]
          }

          # List, create, update, and delete intermeddiate cert
          path "pki/*" {
            capabilities = ["create", "read", "update", "delete", "list"]
          }
        '';
      };

      resource.vault_generic_secret.auth_kubernetes_role_vault_deployer = {
        path = "auth/kubernetes/role/deployer";
        data_json = builtins.toJSON {
          bound_service_account_names = "vault-deployer";
          bound_service_account_namespaces = "default";
          policies = ["default" "provisioner"];
          period = "1h";
        };
        depends_on = [
          "vault_generic_secret.auth_kubernetes_config"
          "vault_policy.provisioner"
        ];
      };
    };
  };

  kubernetes.modules.vault = {
    module = "vault";
    configuration = {
      tlsSecret = "vault-cert";
      configuration = {
        storage.etcd = {
          address = "http://etcd:2379";
          etcd_api = "v3";
          ha_enabled = "true";
        };
      };
    };
  };

  kubernetes.modules.vault-controller = {
    module = "vault-controller";
    configuration.vault = {
      address = vault;
      saauth = true;
      caCert = "vault-cert";
    };
  };

  kubernetes.modules.vault-controller-cert-secret-claim = {
    name = "vault-cert";
    module = "secret-claim";
    configuration = {
      type = "kubernetes.io/tls";
      path = "pki/issue/vault";
      renew = 300;
      data = {
        common_name = "vault.example.com";
        ttl = "10m";
        alt_names = "vault,vault.example.com";
        ip_sans = "127.0.0.1";
      };
    };
  };

  kubernetes.modules.logstash = {
    module = "logstash";
    configuration.configuration = ''
      input {
        tcp {
          port => 65100
          codec => "json"
        }
      }

      filter {
        date {
          match => ["time", "ISO8601"]
        }
      }

      output {
        stdout {
          codec => rubydebug
        }
      }
    '';
  };

  kubernetes.resources.services.logstash-vault = {
    spec = {
      ports = [{
        name = "logs";
        port = 65100;
        targetPort = 65100;
      }];
      selector.app = "logstash";
    };
  };
}
