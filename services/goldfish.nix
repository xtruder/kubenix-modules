{ config, lib, k8s, ... }:

with lib;
with k8s;

let
    containerPort = 8000;
in {
  kubernetes.moduleDefinitions.goldfish.module = { name, config, ... }: {
    options = {
      image = mkOption {
        description = "Goldfish image to use";
        type = types.str;
        default = "caiyeon/goldfish";
      };

      replicas = mkOption {
        description = "Number of Goldfish replicas to deploy";
        default = 1;
        type = types.int;
      };

      goldfishConfig = mkOption {
        description = "Goldfish config to use";
        type = types.str;
        default = "";
      };

      tls = {
        disable = mkOption {
          description = "Flag whether to disable TLS for Goldfish";
          type = types.bool;
          default = false;
        };

        autoredirect = mkOption {
          description = "Flag whether to redirect port 80 to 44";
          type = types.bool;
          default = true;
        };
      };

      certificate = {
        local = {
          cert = mkOption {
            description = "The certificate file to use for TLS";
            type = types.string;
            default = "";
          };
          key = mkOption {
            description = "The key file to use for TLS";
            type = types.string;
            default = "";
          };
        };
        pki = mkOption {
          roleName = mkOption {
            description = "Vault pki role name";
            type = types.string;
            default = "";
          };
          commonName = mkOption {
            description = "Common name to use for the certificate";
            type = types.string;
            default = "";
          };
          altNames = mkOption {
            description = "Alterntive names to use for the certificate";
            type = types.listOf types.string;
            default = [];
          };
          ipSans = mkOption {
            description = "";
            type = types.listOf types.string;
            default = [];
          };
        };
        type = mkOption {
          description = "";
          type = types.enum ["local" "pki"];
        };
      };

      vault = {
        defaultUrl = mkOption {
          description = "Vault URL";
          type = types.str;
          default = "https://vault:8300";
        };

        skipTlsVerification = mkOption {
          description = "Flag whether to skip TLS certificate verification (e.g. using self-signed)";
          type = types.bool;
          default = false;
        };

        runtimeConfig = mkOption {
          description = "Vault runtime config";
          type = types.string;
          default = "secret/goldfish";
        };

        appRoleLogin = mkOption {
          description = "Path to app role login";
          type = types.string;
          default = "auth/approle/login";
        };

        appRoleId = mkOption {
          description = "App role id";
          type = types.string;
          default = "goldfish";
        };

        ca = {
          cert = mkOption {
            description = "CA cert to verify Vault's certificate. It should be a path to a PEM-encoded CA cert file";
            type = types.string;
            default = "";
          };
          path = mkOption {
            description = "Path to a CA directory instead of a single cert";
            type = types.string;
            default = "";
          };
        };
      };

      enableMLock = mkOption {
        description = "Whether to lock part or all of the calling process's virtual address space";
        type = types.bool;
        default = false;
      };
    };

    config = {
      kubernetes.resources.deployments.goldfish = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          replicas = config.replicas;
          selector.matchLabels.app = name;
          template = {
            metadata.name = name;
            metadata.labels.app = name;
            spec = {
              containers.vault = {
                image = config.image;
                env =
                let
                  localCert = ''
                      certificate "local" {
                        cert_file = "${config.certificate.local.cert}"
                        key_file  = "${config.certificate.local.key}"
                      }
                  '';
                  pkiCert = ''
                      pki_certificate "pki" {
                        pki_path    = "pki/issue/${config.certificate.pki.roleName}"
                        common_name = "${config.certificate.pki.commonName}"
                        alt_names   = [${concatStringsSep "," (imap0 (i: v: "\"${v}\"") config.certificate.pki.alt_names)}]
                        ip_sans     = [${concatStringsSep "," (imap0 (i: v: "\"${v}\"") config.certificate.pki.ipSans)}]
                      }
                  '';
                in {
                  NODE_EXTRA_CA_CERTS.value = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt";

                  GOLDFISH_CONFIG = ''
                    listener "tcp" {
                      address          = ":${containerPort}"
                      tls_disable      = ${config.tls.disable}
                      tls_autoredirect = ${config.tls.autoredirect}
                      ${if config.tls.disable then "" else (if cfg.certificate.type == "token" then localCert else pkiCert)}
                    }
                    vault {
                      address         = "${vault.defaultUrl}"
                      tls_skip_verify = ${if vault.skipTlsVerification then 1 else 0}
                      runtime_config  = "${config.vault.runtimeConfig}"
                      approle_login   = "${config.vault.appRoleLogin}"
                      approle_id      = "${config.vault.appRoleId}"
                      ca_cert         = "${config.vault.ca.cert}"
                      ca_path         = "${config.vault.ca.path}"
                    }
                    disable_mlock = ${if vault.enableMLock then 1 else 0}
                  '';
                };
                resources = {
                  requests.memory = "50Mi";
                  requests.cpu = "50m";
                  limits.memory = "128Mi";
                  limits.cpu = "500m";
                };
                ports = [{
                  containerPort = 8000;
                  name = "http";
                }];
              };
            };
          };
        };
      };

      kubernetes.resources.services.vault-ui = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          ports = [{
            name = "http";
            port = 80;
            targetPort = 8000;
          }];
          selector.app = name;
        };
      };
    };
  };
}