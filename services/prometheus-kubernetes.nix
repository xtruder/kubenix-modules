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
            "prometheus.rules" = ./prometheus/prometheus.rules;
          };
          alerts = mkIf config.alerts.enable {
            "kube-controller-manager.alerts" = ./prometheus/kube-controller-manager.rules;
            "general.alerts" = ./prometheus/general.rules;
            "etcd3.alerts" = ./prometheus/etcd3.rules;
            "job.alerts" = ./prometheus/job.rules;
            "node.alerts" = ./prometheus/node.rules;
            "alertmanager.alerts" = ./prometheus/alertmanager.rules;
            "kube-scheduler.alerts" = ./prometheus/kube-scheduler.rules;
            "kubelet.alerts" = ./prometheus/kubelet.rules;
            "kube-state-metrics.alerts" = ./prometheus/kube-state-metrics.rules;
            "kube-apiserver.alerts" = ./prometheus/kube-apiserver.rules;
            "kubernetes.alerts" = ./prometheus/kubernetes.rules;
          };
          extraScrapeConfigs = loadYAML ./prometheus/scrapeconfigs.yaml;
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
          "deployment-dashboard.json" = ./prometheus/deployment-dashboard.json;
          "kubernetes-capacity-planing-dashboard.json" = ./prometheus/kubernetes-capacity-planing-dashboard.json;
          "kubernetes-cluster-health-dashboard.json" = ./prometheus/kubernetes-cluster-health-dashboard.json;
          "kubernetes-cluster-status-dashboard.json" = ./prometheus/kubernetes-cluster-status-dashboard.json;
          "kubernetes-cluster-usage-dashboard.json" = ./prometheus/kubernetes-cluster-usage-dashboard.json;
          "kubernetes-control-plane-status-dashboard.json" = ./prometheus/kubernetes-control-plane-status-dashboard.json;
          "kubernetes-resource-requests-dashboard.json" = ./prometheus/kubernetes-resource-requests-dashboard.json;
          "nodes-dashboard.json" = ./prometheus/nodes-dashboard.json;
          "pods-dashboard.json" = ./prometheus/pods-dashboard.json;
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
    };
  };
}
