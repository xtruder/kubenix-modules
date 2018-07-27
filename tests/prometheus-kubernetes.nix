{ config, k8s, ... }:

with k8s;

{
  require = [
    ./test.nix
    ../modules/prometheus-kubernetes.nix
  ];

  kubernetes.resources.namespaces.monitoring = {};

  kubernetes.modules.k8sprom = {
    module = "prometheus-kubernetes";

    namespace = "monitoring";

    configuration = {
      alerts.enable = true;

      kubernetes.modules.prometheus.configuration = {
        # scrape configs for blackbox exporter
        extraScrapeConfigs = [{
          job_name = "blackbox";
          metrics_path = "/probe";
          static_configs = [{
            targets = [
              "http://prometheus.io"
              "https://prometheus.io"
              "http://google.com"
            ];
          }];
          relabel_configs = [{
            source_labels = ["__address__"];
            target_label = "__param_target";
          } {
            source_labels = ["__param_target"];
            target_label = "instance";
          } {
            target_label = "__address__";
            replacement = "k8sprom-prometheus-blackbox-exporter:9115";
          }];
        }];
      };

      kubernetes.modules.grafana.configuration = {
        rootUrl = "";
        adminPassword.name = "grafana-user";
        db.type = "sqlite3";
      };

      kubernetes.resources.secrets.grafana-user.data = {
        password = toBase64 "root";
      };
    };
  };
}
