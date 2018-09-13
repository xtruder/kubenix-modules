{ config, lib, k8s, pkgs, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.kube-state-metrics.module = {config, module, ...}: {
    options = {
      image = mkOption {
        description = "Image to use for kube-state-metrics";
        type = types.str;
        default = "quay.io/coreos/kube-state-metrics:v1.3.1";
      };
    };

    config = {
      kubernetes.resources.deployments.kube-state-metrics = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        spec = {
          replicas = 1;
          selector.matchLabels.app = module.name;
          template = {
            metadata.name = module.name;
            metadata.labels.app = module.name;
            spec = {
              serviceAccountName = module.name;
              containers.kube-state-metrics = {
                image = config.image;
                ports = [{
                  name = "http-metrics";
                  containerPort = 8080;
                }];
                readinessProbe = {
                  httpGet = {
                    path = "/healthz";
                    port = 8080;
                  };
                  initialDelaySeconds = 5;
                  timeoutSeconds = 5;
                };
                resources = {
                  requests = {
                    memory = "100Mi";
                    cpu = "100m";
                  };
                  limits = {
                    memory = "200Mi";
                    cpu = "200m";
                  };
                };
              };
              containers.addon-resizer = {
                image = "k8s.gcr.io/addon-resizer:1.7";
                resources = {
                  requests = {
                    memory = "30Mi";
                    cpu = "100m";
                  };
                  limits = {
                    memory = "30Mi";
                    cpu = "100m";
                  };
                };
                env = {
                  MY_POD_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
                  MY_POD_NAME.valueFrom.fieldRef.fieldPath = "metadata.name";
                };
                command = [
                  "/pod_nanny"
                  "--container=kube-state-metrics"
                  /* "--cpu=100m"
                  "--extra-cpu=1m"
                  "--memory=100Mi"
                  "--extra-memory=2Mi"
                  "--threshold=5" */
                  "--deployment=${module.name}"
                ];
              };
              /* nodeSelector.node_label_key = "node_label_value"; */
            };
          };
        };
      };

      kubernetes.resources.services.kube-state-metrics = {
        metadata.name = module.name;
        metadata.labels.app = module.name;
        metadata.annotations."prometheus.io/scrape" = "true";
        spec = {
          ports = [{
            name = "http-metrics";
            port = 8080;
            protocol = "TCP";
          }];
          selector.app = module.name;
        };
      };

      kubernetes.resources.serviceAccounts.kube-state-metrics.metadata.name = module.name;

      kubernetes.resources.clusterRoles.kube-state-metrics = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = module.name;
        metadata.labels.app = module.name;
        rules = [{
          apiGroups = [""];
          resources = [
            "nodes"
            "pods"
            "services"
            "resourcequotas"
            "replicationcontrollers"
            "limitranges"
            "persistentvolumeclaims"
            "persistentvolumes"
            "namespaces"
            "endpoints"
            "secrets"
            "confimaps"
          ];
          verbs = ["list" "watch"];
        } {
          apiGroups = ["extensions"];
          resources = [
            "daemonsets"
            "deployments"
            "replicasets"
          ];
          verbs = ["list" "watch"];
        } {
          apiGroups = [ "apps" ];
          resources = [ "statefulsets" ];
          verbs = [ "list" "watch" ];
        } {
          apiGroups = [ "batch" ];
          resources = [ "cronjobs" "jobs" ];
          verbs = [ "list" "watch" ];
        } {
          apiGroups = [ "autoscaling" ];
          resources = [ "horizontalpodautoscalers" ];
          verbs = [ "list" "watch" ];
        }];
      };

      kubernetes.resources.clusterRoleBindings.kube-state-metrics = {
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

      kubernetes.resources.roles.kube-state-metrics-resizer = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = module.name;
        metadata.labels.app = module.name;
        rules = [{
          apiGroups = [""];
          resources = ["pods"];
          resourceNames = ["vault"];
          verbs = ["get"];
        } {
          apiGroups = ["extensions"];
          resources = ["deployments"];
          resourceNames = ["kube-state-metrics"];
          verbs = ["get" "update"];
        }];
      };

      kubernetes.resources.roleBindings.kube-state-metrics = {
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
        }];
      };
    };
  };
}
