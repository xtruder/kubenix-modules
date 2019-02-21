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
      default = "quay.io/kubernetes-ingress-controller/nginx-ingress-controller:0.12.0";
      type = types.str;
    };

    type = mkOption {
      description = "Whether to deploy as daemonset or deployment";
      type = types.enum ["deployment" "daemonSet"];
      default = "deployment";
    };

    replicas = mkOption {
      description = "Number of grafana replicas to run if running as daemonSet";
      type = types.int;
      default = 1;
    };

    useHostPort = mkOption {
      description = "Whether to listen on host port";
      type = types.bool;
      default = false;
    };

    headers = mkOption {
      description = "Attribute set of extra headers to set";
      type = types.attrs;
      default = {};
    };

    defaultBackend = {
      enable = mkOption {
        description = "Whether to enable default backend";
        type = types.bool;
        default = module.namespace != "kube-system";
      };

      service = mkOption {
        description = "Name of the default backend services";
        type = types.str;
        default =
          if module.namespace == "kube-system"
          then "default-http-backend"
          else "${name}-default-http-backend";
      };

      image = mkOption {
        description = "Default backend image to use";
        type = types.str;
        default = "k8s.gcr.io/defaultbackend:1.3";
      };
    };

    electionId = mkOption {
      description = "Election ID to use for status update";
      type = types.str;
      default = "ingress-controller-leader";
    };

    ingressClass = mkOption {
      description = "Name of the ingress class";
      type = types.str;
      default = "nginx";
    };

    publishService = mkOption {
      description = ''
        Service fronting the ingress controllers. Takes the form namespace/name.
        The controller will set the endpoint records on the ingress objects to reflect those on the service.
      '';
      type = types.nullOr types.str;
      default = "${module.namespace}/${name}";
    };

    scope = {
      enable = mkOption {
        description = "Whether to limit scope to single namespace";
        type = types.bool;
        default = false;
      };

      namespace = mkOption {
        description = "Namespace to limit nginx-controller to";
        type = types.str;
        default = module.namespace;
      };
    };

    autoscaling = {
      enable = mkOption {
        description = "Whether to enable autoscaling";
        type = types.bool;
        default = false;
      };

      minReplicas = mkOption {
        description = "Minimal number of replicas";
        type = types.int;
        default = 1;
      };

      maxReplicas = mkOption {
        description = "Maximal number of replicas";
        type = types.int;
        default = 1;
      };
    };

    stats.enable = mkOption {
      description = "Whether to enable statistic";
      type = types.bool;
      default = false;
    };

    metrics.enable = mkOption {
      description = "Whether to enable prometheus metrics";
      type = types.bool;
      default = false;
    };

    customTemplate = mkOption {
      description = "Name of the custom template configmap";
      type = types.nullOr types.str;
      default = null;
    };

    rbac.enable = mkOption {
      description = "Whether to enable RBAC";
      type = types.bool;
      default = module.namespace != "kube-system";
    };

    minAvailable = mkOption {
      description = "Minimal number of avaliable replicas";
      type = types.int;
      default = if config.args.replicas <= 1 then 1 else config.args.replicas - 1;
    };

    extraArgs = mkOption {
      description = "Nginx ingress extra arguments";
      type = types.listOf types.str;
      default = [];
    };

    extraConfig = mkOption {
      description = "Nginx ingress extra configuration options";
      type = types.attrs;
      default = {};
    };
  };

  config = mkMerge [{
    submodule = {
      name = "nginx-ingress";
      version = "1.0.0";
      description = "";
    };
    kubernetes.api."${config.type}s".nginx-ingress = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        selector.matchLabels.app = name;
        template = {
          metadata.name = name;
          metadata.labels.app = name;
          spec = {
            serviceAccountName = mkIf config.args.rbac.enable name;
            containers.nginx-ingress = {
              image = config.args.image;
              args = [
                "/nginx-ingress-controller"
                "--default-backend-service=${module.namespace}/${config.args.defaultBackend.service}"
                "--election-id=${config.args.electionId}"
                "--ingress-class=${config.args.ingressClass}"
                "--configmap=${module.namespace}/${name}"
              ] ++ (optional (config.args.publishService != null) 
                "--publish-service=${config.args.publishService}"
              ) ++ (optional config.args.scope.enable
                "--watch-namespaces=${config.args.scope.namespace}"
              ) ++ config.args.extraArgs;
              env = {
                POD_NAME.valueFrom.fieldRef.fieldPath = "metadata.name";
                POD_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
              };
              livenessProbe = {
                httpGet = {
                  path = "/healthz";
                  port = 10254;
                  scheme = "HTTP";
                };
                initialDelaySeconds = 10;
                periodSeconds = 10;
                timeoutSeconds = 1;
                successThreshold = 1;
                failureThreshold = 3;
              };
              readinessProbe = {
                httpGet = {
                  path = "/healthz";
                  port = 10254;
                  scheme = "HTTP";
                };
                initialDelaySeconds = 10;
                periodSeconds = 10;
                timeoutSeconds = 1;
                successThreshold = 1;
                failureThreshold = 3;
              };
              ports = {
                "80" = {
                  name = "http";
                  hostPort = mkIf config.args.useHostPort 80;
                };
                "443" = {
                  name = "https";
                  hostPort = mkIf config.args.useHostPort 443;
                };
                "18080" = mkIf config.args.stats.enable {
                  name = "stats";
                };
                "10254" = mkIf config.args.metrics.enable {
                  name = "metrics";
                };
              };
              volumeMounts = mkIf (config.args.customTemplate != null) [{
                name = "nginx-template-volume";
                mountPath = "/etc/nginx/template";
                readOnly = true;
              }];
            };
            volumes.nginx-template-volume = mkIf (config.args.customTemplate != null) {
              configMap = {
                name = config.args.customTemplate;
                items = [{
                  key = "nginx.tmpl";
                  path = "nginx.tmpl";
                }];
              };
            };
            terminationGracePeriodSeconds = 60;
          };
        } ;
      } // (optionalAttrs (config.type == "deployment") {
        replicas = config.args.replicas;
      });
    };
  } {

    kubernetes.api.serviceaccounts.nginx-ingress = mkIf config.args.rbac.enable {
      metadata.name = name;
      metadata.labels.app = name;
    };

    kubernetes.api.configmaps.nginx-ingress = {
      metadata.name = name;
      metadata.labels.app = name;

      data = {
        enable-vts-status = "${toString config.args.stats.enable}";
        proxy-set-headers = mkIf (config.args.headers != {}) "${module.namespace}/${name}-custom-headers";
      } // config.args.extraConfig;
    };

    kubernetes.api.configmaps.nginx-ingress-headers = mkIf (config.args.headers != {}) {
      metadata.name = "${name}-headers";
      metadata.labels.app = name;
      data = config.args.headers;
    };

    kubernetes.api.deployments.default-http-backend = mkIf config.args.defaultBackend.enable {
      metadata.name = "${name}-default-http-backend";
      metadata.labels.app = "${name}-default-http-backend";
      spec = {
        replicas = 1;
        selector.matchLabels.app = "${name}-default-http-backend";

        template = {
          metadata.name = "${name}-default-http-backend";
          metadata.labels.app = "${name}-default-http-backend"; 
          spec = {
            containers.default-http-backend = {
              image = config.args.defaultBackend.image;
              livenessProbe = {
                httpGet = {
                  path = "/healthz";
                  port = 8080;
                  scheme = "HTTP";
                };
                initialDelaySeconds = 30;
                periodSeconds = 5;
              };
              ports."8080" = {};
            };
            terminationGracePeriodSeconds = 60;
          };
        };
      };
    };

    kubernetes.api.services.nginx-ingress = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        type = "LoadBalancer";
        ports = [{
          name = "http";
          port = 80;
        } {
          name = "https";
          port = 443;
        }];
        selector.app = name;
      };
    };

    kubernetes.api.services.nginx-ingress-metrics = mkIf config.args.metrics.enable {
      metadata.name = "${name}-metrics";
      metadata.labels.app = name;
      metadata.annotations = {
        "prometheus.io/scrape" = true;
        "prometheus.io/port" = 10254;
      };
      spec = {
        ports = [{
          name = "metrics";
          port = 10254;
        }];
        selector.app = name;
      };
    };

    kubernetes.api.services.nginx-ingress-stats = mkIf config.args.stats.enable {
      metadata.name = "${name}-stats";
      metadata.labels.app = name;
      spec = {
        ports = [{
          name = "stats";
          port = 18080;
        }];
        spec.selector.app = name;
      };
    };

    kubernetes.api.services.default-http-backend = {
      metadata.name = "${name}-default-http-backend";
      metadata.labels.app = name;
      spec = {
        ports = [{
          name = "http";
          port = 8080;
        }];
        selector.app = "${name}-default-http-backend";
      };
    };

    kubernetes.api.poddisruptionbudgets.nginx-ingress = mkIf (config.args.type == "deployment") {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        selector.matchLabels.app = name;
        minAvailable = config.args.minAvailable;
      };
    };

    kubernetes.api.roles.nginx-ingress = mkIf config.args.rbac.enable {
      apiVersion = "rbac.authorization.k8s.io/v1beta1";
      metadata.name = name;
      metadata.labels.app = name;
      rules = [{
        apiGroups = [""];
        resources = ["configmaps" "namespaces" "pods" "secrets"];
        verbs = ["get"];
      } {
        apiGroups = [""];
        resources = ["configmaps"];
        resourceNames = ["${config.args.electionId}-${config.args.ingressClass}"];
        verbs = ["get" "update"];
      } {
        apiGroups = [""];
        resources = ["configmaps"];
        verbs = ["create"];
      } {
        apiGroups = [""];
        resources = ["endpoints"];
        verbs = ["create" "get" "update"];
      }];
    };

    kubernetes.api.rolebindings.nginx-ingress = mkIf config.args.rbac.enable {
      apiVersion = "rbac.authorization.k8s.io/v1beta1";
      metadata.name = name;
      metadata.labels.app = name;

      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "Role";
        name = name;
      };

      subjects = [{
        kind = "ServiceAccount";
        name = name;
        namespace = module.namespace;
      }];
    };

    kubernetes.api.clusterroles.nginx-ingress = mkIf config.args.rbac.enable {
      apiVersion = "rbac.authorization.k8s.io/v1beta1";
      metadata.name = name;
      metadata.labels.app = name;
      rules = [{
        apiGroups = [""];
        resources = ["configmaps" "endpoints" "nodes" "pods" "secrets"];
        verbs = ["list" "watch"];
      } {
        apiGroups = [""];
        resources = ["nodes"];
        verbs = ["get"];
      } {
        apiGroups = [""];
        resources = ["services"];
        verbs = ["get" "list" "update" "watch"];
      } {
        apiGroups = ["extensions"];
        resources = ["ingresses"];
        verbs = ["get" "list" "watch"];
      } {
        apiGroups = [""];
        resources = ["events"];
        verbs = ["create" "patch"];
      } {
        apiGroups = ["extensions"];
        resources = ["ingresses/status"];
        verbs = ["update"];
      }] ++ optional config.args.scope.enable {
        apiGroups = [""];
        resources = ["namespaces"];
        resourceNames = config.args.scope.namespace;
        verbs = ["get"];
      };
    };
      
    kubernetes.api.clusterrolebindings.nginx-ingress = mkIf config.args.rbac.enable {
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
  }];
}