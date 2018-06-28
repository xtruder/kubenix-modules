{ config, k8s, ... }:

let
  vault = "https://vault:8300";
  namespace = "vault";
in {
  require = import ../../modules/module-list.nix;

  kubernetes.resources.namespaces."${namespace}" = {};

  kubernetes.modules.etcd = {
    inherit namespace;
  };

  kubernetes.modules.selfsigned-cert-deployer = {
    inherit namespace;
    configuration.secretName = "vault-cert";
  };

  kubernetes.modules.vault = {
    inherit namespace;

    configuration = {
      tls.secret = "vault-cert";
      configuration = {
        storage.etcd = {
          address = "http://etcd:2379";
          etcd_api = "v3";
          ha_enabled = "true";
        };
      };
    };
  };

  kubernetes.modules.vault-controller-cert-secret-claim = {
    inherit namespace;
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

  kubernetes.modules.vault-controller = {
    inherit namespace;
    configuration.vault = {
      address = vault;
      saauth = true;
    };
  };

  kubernetes.modules.secret-restart-controller = {
    inherit namespace;
  };

  kubernetes.modules.vault-bootstraper = {
    inherit namespace;

    module = "deployer";

    configuration.vars.vault_token.valueFrom.secretKeyRef ={
      name = "vault-root-token";
      key = "token";
    };

    configuration.runAsJob = true;
    configuration.configuration = {
      variable.vault_token = {};

      provider.vault = {
        address = vault;
        token = ''''${var.vault_token}'';
        ca_cert_file = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt";
      };

      resource.vault_auth_backend.kubernetes = {
        type = "kubernetes";
      };

      resource.vault_generic_secret.auth_kubernetes_config = {
        path = "auth/kubernetes/config";
        data_json = ''{
            "kubernetes_host": "https://kubernetes.default:443",
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
          bound_service_account_namespaces = namespace;
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

  kubernetes.modules.vault-deployer = {
    inherit namespace;

    module = "deployer";

    configuration.kubernetes.modules.vault-login = {
      module = "vault-login-sidecar";

      configuration = {
        resourcePath = ["deployments" "deployer" "spec" "template" "spec"];
        serviceAccountName = "vault-deployer";
        mountContainer = "deployer";
        vault = {
          address = vault;
          role = "deployer";
        };
        tokenRenewPeriod = 60;
      };
    };

    configuration.configuration = {
      terraform.backend.etcdv3 = {
        endpoints = ["http://etcd:2379"];
        prefix = "vault-deployer/";
      };

      provider.vault = {
        address = vault;
        token = ''''${file("/vault/token")}'';
        ca_cert_file = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt";
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
          bound_service_account_namespaces = namespace;
          policies = ["default" "reader"];
          period = "1h";
        };
        depends_on = ["vault_policy.reader"];
      };
    };
  };

  kubernetes.modules.logstash = {
    inherit namespace;

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
    metadata.namespace = namespace;

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
