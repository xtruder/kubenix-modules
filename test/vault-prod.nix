{ config, k8s, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.etcd.module = "etcd";

  # the following certs must be manually generated and secrets created in etcd
  kubernetes.modules.ca-deployer = {
    module = "deployer";

    configuration.configuration = {
      provider.kubernetes = {
        host = "https://kubernetes";
        cluster_ca_certificate = ''''${file("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")}'';
        token = ''''${file("/var/run/secrets/kubernetes.io/serviceaccount/token")}''; 
      };

      terraform.backend.etcdv3 = {
        endpoints = ["http://etcd:2379"];
        prefix = "terraform-state/";
        lock = true;
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
          common_name = "Example Ltd. Root";
          organization = "Example, Ltd";
          organizational_unit = "Department of Certificate Authority";
          street_address = ["5879 Cotton Link"];
          locality = "Pirate Harbor";
          province = "CA";
          country = "UK";
          postal_code = "95559-1227";
        };
      };

      resource.tls_private_key.vault = {
        algorithm = "ECDSA";
        ecdsa_curve = "P521";
      };

      resource.tls_cert_request.vault = {
        key_algorithm = ''''${tls_private_key.vault.algorithm}'';
        private_key_pem = ''''${tls_private_key.vault.private_key_pem}'';
        dns_names = ["vault.example.com"];
        ip_addresses = ["127.0.0.1"];

        subject = {
          common_name = "vault.example.net";
          organization = "Example, Inc";
          organizational_unit = "VaultOps";
        };
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
        metadata.name = "vault-ca";
        data = {
          "ca.crt" = ''''${tls_self_signed_cert.ca.cert_pem}'';
          "vault.key" = ''''${tls_private_key.vault.private_key_pem}'';
          "vault.crt" = ''''${tls_locally_signed_cert.vault.cert_pem}'';
        };
        type = "Opaque";
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

  kubernetes.modules.vault = {
    module = "vault";
    configuration = {
      tlsSecret = "vault-ca";
      healthPort = 8400;
      configuration = {
        storage.etcd = {
          address = "http://etcd:2379";
          etcd_api = "v3";
          ha_enabled = "true";
        };
        listener = [{
          tcp = {
            address = "0.0.0.0:8200";
            tls_cert_file = "/var/lib/vault/ssl/vault.crt";
            tls_key_file = "/var/lib/vault/ssl/vault.key";
          };
        } {
          tcp = {
            address = "0.0.0.0:8400";
            tls_disable = true;
          };
        }];
      };
    };
  };
}
