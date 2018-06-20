{ config, k8s, ... }:

with k8s;

{
  require = [./test.nix ../modules/grafana.nix];

  kubernetes.modules.grafana = {
    module = "grafana";
    configuration = {
      rootUrl = "grafana.default.svc.cluster.local";
      adminPassword.name = "grafana-user";
      db.type = "sqlite3";
      resources = {
        deployments = ../modules/prometheus/deployment-dashboard.json;
      };
    };
  };

  kubernetes.resources.secrets.grafana-user.data = {
    password = toBase64 "root";
  };
}
