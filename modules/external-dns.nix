{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.external-dns.module = {name, config, module, ...}: {
    options = {
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
      kubernetes.resources.deployments.external-dns = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          selector.matchLabels.app = module.name;
          template = {
            metadata.labels.app = module.name;
            spec = {
              serviceAccountName = module.name;
              containers.external-dns = {
                image = config.image;
                args = [
                  "--source=${config.source}"
                  "--domain-filter=${config.domainFilter}"
                  "--provider=${config.provider}"
                  "--google-project=${config.google.project}"
                  "--registry=${config.registry}"
                  "--txt-owner-id=${config.txt.owner}"
                ] ++ (optional (config.annotationFilter != null)
                  "--annotation-filter=${config.annotationFilter}")
                  ++ config.extraArgs;
                env = {
                  GOOGLE_APPLICATION_CREDENTIALS =
                    mkIf (config.google.credentials != null) {
                      value = "/gcloud/gcloud-credentials.json";
                    };
                };
                volumeMounts."/gcloud" = mkIf (config.google.credentials != null) {
                  name = "gcloud-credentials";
                  readOnly = true;
                };
              };
              volumes.gcloud-credentials = mkIf (config.google.credentials != null) {
                secret = {
                  secretName = config.google.credentials.name;
                  items = [{
                    key = config.google.credentials.key;
                    path = "gcloud-credentials.json";
                  }];
                };
              };
            };
          };
        };
      };

      kubernetes.resources.serviceAccounts.external-dns = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
      };

      kubernetes.resources.clusterRoles.external-dns = mkIf config.rbac.enable {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = module.name;
        metadata.labels.app = module.name;
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

      kubernetes.resources.clusterRoleBindings.external-dns = mkIf config.rbac.enable {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = module.name;
        metadata.labels.app = module.name;
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = module.name;
        };
        subjects = [{
          kind = "ServiceAccount";
          name = module.name;
          namespace = module.namespace;
        }];
      };
    };
  };
}
