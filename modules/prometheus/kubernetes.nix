{ config, lib, k8s, pkgs, ... }:

with lib;

let
  loadYAML = path: (builtins.fromJSON (builtins.readFile (pkgs.runCommand "yaml-to-json" {
  } "${pkgs.remarshal}/bin/remarshal -i ${path} -if yaml -of json > $out")));
in {
  config.kubernetes.moduleDefinitions.prometheus-kubernetes.module = {name, config, module, ...}: {
    options = {
      alerts.enable = mkOption {
        description = "Enable predefined alerts";
        type = types.bool;
        default = true;
      };
    };

    config = {
      kubernetes.modules.prometheus = {
        name = "${name}-prometheus";
        module = "prometheus";
        namespace = module.namespace;
        configuration = {
          rules = {
            "prometheus.rules" = ./rules/prometheus.rules;
          };
          alerts = mkIf config.alerts.enable {
            "kube-controller-manager.alerts" = ./rules/kube-controller-manager.rules;
            "general.alerts" = ./rules/general.rules;
            "etcd3.alerts" = ./rules/etcd3.rules;
            "job.alerts" = ./rules/job.rules;
            "node.alerts" = ./rules/node.rules;
            "alertmanager.alerts" = ./rules/alertmanager.rules;
            "kube-scheduler.alerts" = ./rules/kube-scheduler.rules;
            "kubelet.alerts" = ./rules/kubelet.rules;
            "kube-state-metrics.alerts" = ./rules/kube-state-metrics.rules;
            "kube-apiserver.alerts" = ./rules/kube-apiserver.rules;
            "kubernetes.alerts" = ./rules/kubernetes.rules;
          };
          extraScrapeConfigs = loadYAML
            (builtins.toFile "scrapeconfigs.yaml"  (
              builtins.replaceStrings ["prometheus-blackbox-exporter"] ["${name}-prometheus-blackbox-exporter"]
                (builtins.readFile ./scrapeconfigs.yaml)));
        };
      };

      kubernetes.modules.prometheus-alertmanager = {
        name = "${name}-prometheus-alertmanager";
        module = "prometheus-alertmanager";
        namespace = module.namespace;
        configuration = mkDefault {
          route.receiver = "default";
          receivers.default = {};
        };
      };

      kubernetes.modules.prometheus-pushgateway = {
        name = "${name}-prometheus-pushgateway";
        module = "prometheus-pushgateway";
        namespace = module.namespace;
      };

      kubernetes.modules.grafana = {
        name = "${name}-grafana";
        module = "grafana";
        namespace = module.namespace;
        configuration.resources = {
          "deployment-dashboard.json" = ./dashboards/deployment-dashboard.json;
          "kubernetes-capacity-planing-dashboard.json" = ./dashboards/kubernetes-capacity-planing-dashboard.json;
          "kubernetes-cluster-health-dashboard.json" = ./dashboards/kubernetes-cluster-health-dashboard.json;
          "kubernetes-cluster-status-dashboard.json" = ./dashboards/kubernetes-cluster-status-dashboard.json;
          "kubernetes-cluster-usage-dashboard.json" = ./dashboards/kubernetes-cluster-usage-dashboard.json;
          "kubernetes-control-plane-status-dashboard.json" = ./dashboards/kubernetes-control-plane-status-dashboard.json;
          "kubernetes-resource-requests-dashboard.json" = ./dashboards/kubernetes-resource-requests-dashboard.json;
          "nodes-dashboard.json" = ./dashboards/nodes-dashboard.json;
          "pods-dashboard.json" = ./dashboards/pods-dashboard.json;
          "prometheus-datasource.json" = {
            access = "proxy";
            basicAuth = false;
            name = "prometheus";
            type = "prometheus";
            url = "http://${name}-prometheus:9090";
          };
        };
      };

      kubernetes.modules.prometheus-node-exporter = {
        name = "${name}-prometheus-node-exporter";
        module = "prometheus-node-exporter";
        namespace = module.namespace;
        configuration = {
          extraPaths = {
            rootfs.hostPath = "/";
          };
        };
      };

      kubernetes.modules.kube-state-metrics = {
        name = "${name}-kube-state-metrics";
        module = "kube-state-metrics";
        namespace = module.namespace;
      };

      kubernetes.modules.prometheus-blackbox-exporter = {
        name = "${name}-prometheus-blackbox-exporter";
        module = "prometheus-blackbox-exporter";
        namespace = module.namespace;
      };
    };
  };
}
