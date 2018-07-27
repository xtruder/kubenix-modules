{ config, ... }:

{
  require = [./test.nix ../modules/prometheus.nix];

  kubernetes.modules.prometheus = {
    module = "prometheus";
    configuration = {
      replicas = 1;
      alertmanager.enable = true;

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
          replacement = "prometheus-blackbox-exporter:9115";
        }];
      }];
    };
  };

  kubernetes.modules.prometheus-pushgateway = {
    module = "prometheus-pushgateway";
  };

  kubernetes.modules.prometheus-alertmanager = {
    module = "prometheus-alertmanager";
  };

  kubernetes.modules.prometheus-blackbox-exporter = {
    module = "prometheus-blackbox-exporter";
  };
}
