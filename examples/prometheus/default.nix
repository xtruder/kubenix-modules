{ config, k8s, ... }:

with k8s;

{
  require = import ../../modules/module-list.nix;

  kubernetes.modules.prometheus = {
    module = "prometheus";
    configuration = {
      replicas = 1;
      alerts = {
        "gh_wallet_balance.alerts" = {
          groups = [
            {
              name = "Monitoring";
              rules = [
                {
                  alert = "Monitoring_NativeHotWalletBitcoin";
                  expr = ''gh_wallet_balance{network="bitcoin", type="hot", currency="BTC"} > 1'';
                  for = "1m";
                  labels.severity = "warning";
                  annotations = {
                    description = "Native hot wallet check for Bitcoin";
                    summary = "{{$labels.vaultUuid}} {{$labels.currency}}";
                  };
                }
              ];
            }
          ];
        };
      };
      extraScrapeConfigs = [
        {
          job_name = "prometheus-pushgateway";
          static_configs = [{
            targets = ["prometheus-pushgateway:9091"];
          }];
        }
      ];
      alertmanager.enable = true;
    };
  };

  kubernetes.modules.prometheus-pushgateway = {
    module = "prometheus-pushgateway";
  };

  kubernetes.modules.prometheus-alertmanager = {
    module = "prometheus-alertmanager";
    configuration = {
      replicas = 1;
      receivers = {
        default = {
          type = "hipchat";
          options = {
            auth_token = "v57HTiMY6gOwxCfn8ejfC8eb0oWghUyWGWvwAkqY";
            room_id = 4155122;
            message_format = "html";
            notify = true;
          };
        };
      };
    };
  };

  kubernetes.modules.grafana = {
    module = "grafana";
    configuration = {
      rootUrl = "";
      adminPassword.name = "grafana-user";
      db.type = "sqlite3";
      resources = {
        "deployment-dashboard.json" = ../../modules/prometheus/deployment-dashboard.json;
        "hot-dashboard.json" = ./hot-dashboard.json;
        "prom-datasource.json" = {
          name = "prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://prometheus:9090";
        };
      };
    };
  };

  kubernetes.resources.secrets.grafana-user.data = {
    password = toBase64 "root";
  };
}
