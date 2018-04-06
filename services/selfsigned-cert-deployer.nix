{ config, lib, ... }:

with lib;

{
  kubernetes.moduleDefinitions.selfsigned-cert-deployer.module = { name, module, config, ... }: {
    options = {
      secretName = mkOption {
        description = "Name of the secret where to store selfsigned certs";
        type = types.str;
      };

      ipAddresses = mkOption {
        type = types.listOf types.str;
        default = [];
      };

      dnsNames = mkOption {
        type = types.listOf types.str;
        default = [];
      };
    };

    config = {
      # create certificate
      kubernetes.modules.selfsigned-cert-deployer = {
        module = "deployer";

        name = module.name;
        namespace = module.namespace;

        configuration.runAsJob = true;
        configuration.configuration = {
          provider.kubernetes = {
            host = "https://kubernetes.default";
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
            subject.common_name = "Root CA";
          };

          resource.tls_private_key.key = {
            algorithm = "ECDSA";
            ecdsa_curve = "P521";
          };

          resource.tls_cert_request.csr = {
            key_algorithm = ''''${tls_private_key.key.algorithm}'';
            private_key_pem = ''''${tls_private_key.key.private_key_pem}'';
            dns_names = config.dnsNames;
            ip_addresses = config.ipAddresses;
            subject.common_name = "cert";
          };

          resource.tls_locally_signed_cert.cert = {
            cert_request_pem = ''''${tls_cert_request.csr.cert_request_pem}'';
            ca_key_algorithm = ''''${tls_private_key.ca.algorithm}'';
            ca_private_key_pem = ''''${tls_private_key.ca.private_key_pem}'';
            ca_cert_pem = ''''${tls_self_signed_cert.ca.cert_pem}'';
            validity_period_hours = 17520;
            early_renewal_hours = 8760;
            allowed_uses = ["server_auth"];
          };

          resource.kubernetes_secret.selfsigned = {
            metadata.name = config.secretName;
            metadata.namespace = module.namespace;
            data = {
              "ca.crt" = ''''${tls_self_signed_cert.ca.cert_pem}'';
              "tls.crt" = ''''${tls_locally_signed_cert.cert.cert_pem}'';
              "tls.key" = ''''${tls_private_key.key.private_key_pem}'';
            };
            type = "kubernetes.io/tls";
          };
        };
      };

      kubernetes.resources.roles.selfsigned-deployer = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = module.name;
        rules = [{
          apiGroups = [""];
          resources = ["secrets"];
          verbs = ["get" "create" "update" "patch" "delete"];
        }];
      };

      kubernetes.resources.roleBindings.selfsigned-deployer = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = module.name;
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "Role";
          name = module.name;
        };
        subjects = [{
          kind = "ServiceAccount";
          name = module.name;
        }];
      };
    };
  };
}
