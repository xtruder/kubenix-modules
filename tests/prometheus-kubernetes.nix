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
