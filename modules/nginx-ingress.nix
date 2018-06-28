{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.nginx-ingress.module = {name, config, module, ...}: {
    options = {
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
            else "${module.name}-default-http-backend";
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
        default = "${module.namespace}/${module.name}";
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
        default = if config.replicas <= 1 then 1 else config.replicas - 1;
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
      kubernetes.resources."${config.type}s".nginx-ingress = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          selector.matchLabels.app = name;
          template = {
            metadata.name = name;
            metadata.labels.app = name;
            spec = {
              serviceAccountName = mkIf config.rbac.enable module.name;
              containers.nginx-ingress = {
                image = config.image;
                args = [
                  "/nginx-ingress-controller"
                  "--default-backend-service=${module.namespace}/${config.defaultBackend.service}"
                  "--election-id=${config.electionId}"
                  "--ingress-class=${config.ingressClass}"
                  "--configmap=${module.namespace}/${module.name}"
                ] ++ (optional (config.publishService != null) 
                  "--publish-service=${config.publishService}"
                ) ++ (optional config.scope.enable
                  "--watch-namespaces=${config.scope.namespace}"
                ) ++ config.extraArgs;
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
                    hostPort = mkIf config.useHostPort 80;
                  };
                  "443" = {
                    name = "https";
                    hostPort = mkIf config.useHostPort 443;
                  };
                  "18080" = mkIf config.stats.enable {
                    name = "stats";
                  };
                  "10254" = mkIf config.metrics.enable {
                    name = "metrics";
                  };
                };
                volumeMounts = mkIf (config.customTemplate != null) [{
                  name = "nginx-template-volume";
                  mountPath = "/etc/nginx/template";
                  readOnly = true;
                }];
              };
              volumes.nginx-template-volume = mkIf (config.customTemplate != null) {
                configMap = {
                  name = config.customTemplate;
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
          replicas = config.replicas;
        });
      };
    } {

      kubernetes.resources.serviceAccounts.nginx-ingress = mkIf config.rbac.enable {
        metadata.name = module.name;
        metadata.labels.app = module.name;
      };

      kubernetes.resources.configMaps.nginx-ingress = {
        metadata.name = module.name;
        metadata.labels.app = module.name;

        data = {
          enable-vts-status = "${toString config.stats.enable}";
          proxy-set-headers = mkIf (config.headers != {}) "${module.namespace}/${module.name}-custom-headers";
        } // config.extraConfig;
      };

      kubernetes.resources.configMaps.nginx-ingress-headers = mkIf (config.headers != {}) {
        metadata.name = "${module.name}-headers";
        metadata.labels.app = module.name;
        data = config.headers;
      };

      kubernetes.resources.deployments.default-http-backend = mkIf config.defaultBackend.enable {
        metadata.name = "${module.name}-default-http-backend";
        metadata.labels.app = "${module.name}-default-http-backend";
        spec = {
          replicas = 1;
          selector.matchLabels.app = "${module.name}-default-http-backend";

          template = {
            metadata.name = "${module.name}-default-http-backend";
            metadata.labels.app = "${module.name}-default-http-backend"; 
            spec = {
              containers.default-http-backend = {
                image = config.defaultBackend.image;
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

      kubernetes.resources.services.nginx-ingress = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          type = "LoadBalancer";
          ports = [{
            name = "http";
            port = 80;
          } {
            name = "https";
            port = 443;
          }];
          selector.app = module.name;
        };
      };

      kubernetes.resources.services.nginx-ingress-metrics = mkIf config.metrics.enable {
        metadata.name = "${module.name}-metrics";
        metadata.labels.app = module.name;
        metadata.annotations = {
          "prometheus.io/scrape" = true;
          "prometheus.io/port" = 10254;
        };
        spec = {
          ports = [{
            name = "metrics";
            port = 10254;
          }];
          selector.app = module.name;
        };
      };

      kubernetes.resources.services.nginx-ingress-stats = mkIf config.stats.enable {
        metadata.name = "${module.name}-stats";
        metadata.labels.app = module.name;
        spec = {
          ports = [{
            name = "stats";
            port = 18080;
          }];
          spec.selector.app = module.name;
        };
      };

      kubernetes.resources.services.default-http-backend = {
        metadata.name = "${module.name}-default-http-backend";
        metadata.labels.app = module.name;
        spec = {
          ports = [{
            name = "http";
            port = 8080;
          }];
          selector.app = "${module.name}-default-http-backend";
        };
      };

      kubernetes.resources.podDisruptionBudgets.nginx-ingress = mkIf (config.type == "deployment") {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          selector.matchLabels.app = module.name;
          minAvailable = config.minAvailable;
        };
      };

      kubernetes.resources.roles.nginx-ingress = mkIf config.rbac.enable {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = module.name;
        metadata.labels.app = module.name;
        rules = [{
          apiGroups = [""];
          resources = ["configmaps" "namespaces" "pods" "secrets"];
          verbs = ["get"];
        } {
          apiGroups = [""];
          resources = ["configmaps"];
          resourceNames = ["${config.electionId}-${config.ingressClass}"];
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

      kubernetes.resources.roleBindings.nginx-ingress = mkIf config.rbac.enable {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = module.name;
        metadata.labels.app = module.name;

        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "Role";
          name = module.name;
        };

        subjects = [{
          kind = "ServiceAccount";
          name = module.name;
          namespace = module.namespace;
        }];
      };

      kubernetes.resources.clusterRoles.nginx-ingress = mkIf config.rbac.enable {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = module.name;
        metadata.labels.app = module.name;
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
        }] ++ optional config.scope.enable {
          apiGroups = [""];
          resources = ["namespaces"];
          resourceNames = config.scope.namespace;
          verbs = ["get"];
        };
      };
        
      kubernetes.resources.clusterRoleBindings.nginx-ingress = mkIf config.rbac.enable {
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
    }];
  };
}
