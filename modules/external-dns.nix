{ config, name, kubenix, k8s, ...}:

with lib;
with k8s;

{
  imports = [
    kubenix.k8s
  ];

  options.args = {
    image = mkOption {
      description = "Version of grafana to use";
      default = "registry.opensource.zalan.do/teapot/external-dns:v0.4.8";
      type = types.str;
    };

    rbac.enable = mkOption {
      description = "Whether to enable RBAC";
      type = types.bool;
      default = module.namespace != "kube-system";
    };

    source = mkOption {
      description = "Source for DNS entries";
      type = types.enum ["ingress"];
      default = "ingress";
    };

    domainFilter = mkOption {
      description = "Extrnal dns domain filter";
      type = types.str;
    };

    provider = mkOption {
      description = "Name of the provider to use";
      type = types.enum ["google"];
      default = "google";
    };

    google = {
      project = mkOption {
        description = "Name of the google project";
        type = types.str;
      };

      credentials = mkSecretOption {
        description = "Google credentials to use";
        default = null;
      };
    };

    registry = mkOption {
      description = "Type of the registry to use";
      type = types.enum ["txt"];
      default = "txt";
    };

    txt.owner = mkOption {
      description = "Name of the RR set owner";
      type = types.str;
      default = "my-identifier";
    };

    annotationFilter = mkOption {
      description = "Annotations filter (you can bound on ingress class)";
      type = types.nullOr types.str;
      default = null;
      example = "kubernetes.io/ingress.class=nginx-external";
    };

    extraArgs = mkOption {
      description = "Extra arguments";
      type = types.listOf types.str;
      default = [];
    };
  };

  config = {
    submodule = {
      name = "external-dns";
      version = "1.0.0";
      description = "";
    };
    kubernetes.api.deployments.external-dns = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        selector.matchLabels.app = name;
        template = {
          metadata.labels.app = name;
          spec = {
            serviceAccountName = name;
            containers.external-dns = {
              image = config.args.image;
              args = [
                "--source=${config.args.source}"
                "--domain-filter=${config.args.domainFilter}"
                "--provider=${config.args.provider}"
                "--google-project=${config.args.google.project}"
                "--registry=${config.args.registry}"
                "--txt-owner-id=${config.args.txt.owner}"
              ] ++ (optional (config.args.annotationFilter != null)
                "--annotation-filter=${config.args.annotationFilter}")
                ++ config.args.extraArgs;
              env = {
                GOOGLE_APPLICATION_CREDENTIALS =
                  mkIf (config.args.google.credentials != null) {
                    value = "/gcloud/gcloud-credentials.json";
                  };
              };
              volumeMounts."/gcloud" = mkIf (config.args.google.credentials != null) {
                name = "gcloud-credentials";
                readOnly = true;
              };
            };
            volumes.gcloud-credentials = mkIf (config.args.google.credentials != null) {
              secret = {
                secretName = config.args.google.credentials.name;
                items = [{
                  key = config.args.google.credentials.key;
                  path = "gcloud-credentials.json";
                }];
              };
            };
          };
        };
      };
    };

    kubernetes.api.serviceaccounts.external-dns = {
      metadata.name = name;
      metadata.labels.app = name;
    };

    kubernetes.api.clusterroles.external-dns = mkIf config.args.rbac.enable {
      apiVersion = "rbac.authorization.k8s.io/v1beta1";
      metadata.name = name;
      metadata.labels.app = name;
      rules = [{
        apiGroups = [""];
        resources = ["services"];
        verbs = ["get" "watch" "list"];
      } {
        apiGroups = ["extensions"];
        resources = ["ingresses"];
        verbs = ["get" "list" "watch"];
      }];
    };

    kubernetes.api.clusterrolebindings.external-dns = mkIf config.args.rbac.enable {
      apiVersion = "rbac.authorization.k8s.io/v1beta1";
      metadata.name = name;
      metadata.labels.app = name;
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = name;
      };
      subjects = [{
        kind = "ServiceAccount";
        name = name;
        namespace = module.namespace;
      }];
    };
  };
}