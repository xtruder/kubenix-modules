{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

{
  imports = [
    kubenix.k8s
  ];

  options.args = {
    image = mkOption {
      description = "Goldfish image to use";
      type = types.str;
      default = "caiyeon/goldfish:0.9.0";
    };

    replicas = mkOption {
      description = "Number of Goldfish replicas to deploy";
      default = 1;
      type = types.int;
    };

    configuration = mkOption {
      description = "Goldfish configuration to use";
      type = mkOptionType {
        name = "deepAttrs";
        description = "deep attribute set";
        check = isAttrs;
        merge = loc: foldl' (res: def: recursiveUpdate res def.value) {};
      };
    };

    tls = {
      disable = mkOption {
        description = "Flag whether to disable TLS for Goldfish";
        type = types.bool;
        default = false;
      };

      autoredirect = mkOption {
        description = "Flag whether to redirect port 80 to 443";
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
      pki = {
        roleName = mkOption {
          description = "Vault pki role name";
          type = types.string;
          default = "goldfish";
        };
        commonName = mkOption {
          description = "Common name to use for the certificate";
          type = types.string;
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
        description = "Type of cert to use, local mounted or dynamic from vault";
        type = types.enum ["local" "pki"];
        default = "pki";
      };
    };

    vault = {
      address = mkOption {
        description = "Vault URL";
        type = types.str;
        default = "https://vault:8200";
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
          default = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt";
        };
        path = mkOption {
          description = "Path to a CA directory instead of a single cert";
          type = types.string;
          default = "";
        };
      };
    };

    disableMLock = mkOption {
      description = "Whether to lock part or all of the calling process's virtual address space";
      type = types.bool;
      default = false;
    };
  };

  config = {
    submodule = {
      name = "goldfish";
      version = "1.0.0";
      description = "";
    };
    configuration = let
      b2s = value: if value then 1 else 0;

      localCert = {
        certificate.local = {
          cert_file = config.args.certificate.local.cert;
          key_file  = config.args.certificate.local.key;
        };
      };
      pkiCert = {
        pki_certificate.pki = {
          pki_path    = "pki/issue/${config.args.certificate.pki.roleName}";
          common_name = config.args.certificate.pki.commonName;
          alt_names   = config.args.certificate.pki.altNames;
          ip_sans     = config.args.certificate.pki.ipSans;
        };
      };
    in {
      listener.tcp = {
        address          = ":8000";
        tls_disable      = b2s config.args.tls.disable;
        tls_autoredirect = b2s config.args.tls.autoredirect;
      } // (optionalAttrs (!config.args.tls.disable) (if config.args.certificate.type == "local" then localCert else pkiCert));
      vault = {
        address         = config.args.vault.address;
        tls_skip_verify = b2s config.args.vault.skipTlsVerification;
        runtime_config  = config.args.vault.runtimeConfig;
        approle_login   = config.args.vault.appRoleLogin;
        approle_id      = config.args.vault.appRoleId;
        ca_cert         = config.args.vault.ca.cert;
        ca_path         = config.args.vault.ca.path;
      };
      disable_mlock     = b2s config.args.disableMLock;
    };

    kubernetes.api.deployments.goldfish = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        replicas = config.args.replicas;
        selector.matchLabels.app = name;
        template = {
          metadata.name = name;
          metadata.labels.app = name;
          spec = {
            containers.goldfish = {
              image = config.args.image;
              env.GOLDFISH_CONFIG.value = builtins.toJSON config.args.configuration;
              securityContext.capabilities.add = ["IPC_LOCK"];
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

    kubernetes.api.services.vault-ui = {
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
}