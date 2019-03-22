{ args, name, config, lib, pkgs, kubenix, k8s, ...}:

with lib;

{
  imports = [
    kubenix.modules.submodule
    kubenix.modules.k8s
    kubenix.modules.docker
  ];

  options.submodule.args = {
    type = mkOption {
      description = "Whether to deploy as daemonset or deployment";
      type = types.enum ["deployment" "daemonset"];
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
        default = true;
      };

      service = mkOption {
        description = "Name of the default backend services";
        type = types.str;
        default = "${name}-default-http-backend";
      };

      image = mkOption {
        description = "Default backend image to use";
        type = types.str;
        default = "";
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
      default = "${config.kubernetes.namespace}/${name}";
    };

    reportNodeInternalIpAddress = mkOption {
      description = ''
        Set the load-balancer status of Ingress objects to internal Node 
        addresses instead of external.
      '';
      type = types.bool;
      default = false;
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
      default = true;
    };

    minAvailable = mkOption {
      description = "Minimal number of avaliable replicas";
      type = types.int;
      default = if args.replicas <= 1 then 1 else args.replicas - 1;
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
      name = "nginx-ingress-controller";
      version = "1.0.0";
      description = "";
    };

    docker.images.nginx-ingress-controller.image = pkgs.dockerTools.pullImage {
      imageName = "quay.io/kubernetes-ingress-controller/nginx-ingress-controller";
      imageDigest = "sha256:e1292564ba5f1fd75005a4575778523d3309fb5d5d57f6597234c0b1567641f6";
      sha256 = "0g20x7696qbsgyrx7mxkmpyxhpbapc527w51ifbl8c4gzjp01bcj";
      finalImageName = "nginx-ingress-controller";
      finalImageTag = "0.23.0";
    };

    docker.images.default-http-backend.image = pkgs.dockerTools.pullImage {
      imageName = "k8s.gcr.io/defaultbackend";
      imageDigest = "sha256:865b0c35e6da393b8e80b7e3799f777572399a4cff047eb02a81fa6e7a48ed4b";
      sha256 = "0rg0m2b76ypiwdh9jh9zsb0nlz84zjj0yawxky0wmhi521f6pl10";
      finalImageName = "defaultbackend";
      finalImageTag = "1.4";
    };

    kubernetes.api."${args.type}s".nginx-ingress = {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        selector.matchLabels.app = name;
        template = {
          metadata.name = name;
          metadata.labels.app = name;
          metadata.annotations = mkIf args.metrics.enable {
            "prometheus.io/port" = "10254";
            "prometheus.io/scrape" = "true";
          };
          spec = {
            serviceAccountName = mkIf args.rbac.enable name;
            containers.nginx-ingress = {
              image = config.docker.images.nginx-ingress-controller.path;
              args = [
                "/nginx-ingress-controller"
                "--default-backend-service=$(POD_NAMESPACE)/${args.defaultBackend.service}"
                "--election-id=${args.electionId}"
                "--ingress-class=${args.ingressClass}"
                "--configmap=$(POD_NAMESPACE)/${name}"
                "--annotations-prefix=nginx.ingress.kubernetes.io"
              ] ++ (optional (args.publishService != null) 
                "--publish-service=${args.publishService}"
              ) ++ (optional args.reportNodeInternalIpAddress
                "--report-node-internal-ip-address"
              ) ++ (optional args.scope.enable
                "--watch-namespaces=${args.scope.namespace}"
              ) ++ args.extraArgs;
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
              securityContext = {
                allowPrivilegeEscalation = true;
                capabilities = {
                  drop = ["ALL"];
                  add = ["NET_BIND_SERVICE"];
                };
                runAsUser = 33;
              };
              ports = {
                "80" = {
                  name = "http";
                  hostPort = mkIf args.useHostPort 80;
                };
                "443" = {
                  name = "https";
                  hostPort = mkIf args.useHostPort 443;
                };
                "18080" = mkIf args.stats.enable {
                  name = "stats";
                };
                "10254" = mkIf args.metrics.enable {
                  name = "metrics";
                };
              };
              volumeMounts = mkIf (args.customTemplate != null) [{
                name = "nginx-template-volume";
                mountPath = "/etc/nginx/template";
                readOnly = true;
              }];
            };
            volumes.nginx-template-volume = mkIf (args.customTemplate != null) {
              configMap = {
                name = args.customTemplate;
                items = [{
                  key = "nginx.tmpl";
                  path = "nginx.tmpl";
                }];
              };
            };
            terminationGracePeriodSeconds = 60;
          };
        } ;
      } // (optionalAttrs (args.type == "deployment") {
        replicas = args.replicas;
      });
    };
  } {

    kubernetes.api.serviceaccounts.nginx-ingress = mkIf args.rbac.enable {
      metadata.name = name;
      metadata.labels.app = name;
    };

    kubernetes.api.configmaps.nginx-ingress = {
      metadata.name = name;
      metadata.labels.app = name;

      data = {
        enable-vts-status = "${toString args.stats.enable}";
        proxy-set-headers = mkIf (args.headers != {}) "${config.kubernetes.namespace}/${name}-custom-headers";
      } // args.extraConfig;
    };

    kubernetes.api.configmaps.nginx-ingress-headers = mkIf (args.headers != {}) {
      metadata.name = "${name}-custom-headers";
      metadata.labels.app = name;
      data = args.headers;
    };

    kubernetes.api.deployments.default-http-backend = mkIf args.defaultBackend.enable {
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
              image = config.docker.images.default-http-backend.path;
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

    kubernetes.api.services.nginx-ingress-stats = mkIf args.stats.enable {
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

    kubernetes.api.poddisruptionbudgets.nginx-ingress = mkIf (args.type == "deployment") {
      metadata.name = name;
      metadata.labels.app = name;
      spec = {
        selector.matchLabels.app = name;
        minAvailable = args.minAvailable;
      };
    };

    kubernetes.api.roles.nginx-ingress = mkIf args.rbac.enable {
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
        resourceNames = ["${args.electionId}-${args.ingressClass}"];
        verbs = ["get" "update"];
      } {
        apiGroups = [""];
        resources = ["configmaps"];
        verbs = ["create"];
      } {
        apiGroups = [""];
        resources = ["endpoints"];
        verbs = ["get"];
      }];
    };

    kubernetes.api.rolebindings.nginx-ingress = mkIf args.rbac.enable {
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
        namespace = config.kubernetes.namespace;
      }];
    };

    kubernetes.api.clusterroles.nginx-ingress = mkIf args.rbac.enable {
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
        verbs = ["get" "list" "watch"];
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
      }] ++ optional args.scope.enable {
        apiGroups = [""];
        resources = ["namespaces"];
        resourceNames = args.scope.namespace;
        verbs = ["get"];
      };
    };
      
    kubernetes.api.clusterrolebindings.nginx-ingress = mkIf args.rbac.enable {
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
        namespace = config.kubernetes.namespace;
      }];
    };
  }];
}
