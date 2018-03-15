{ config, k8s, ... }:

{
  require = import ../../services/module-list.nix;

  # create certificate
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
        metadata.name = "vault";
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
      resourceNames = ["vault"];
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
}
