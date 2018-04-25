{ config, k8s, ... }:

with k8s;

{
  require = import ../services/module-list.nix;

  kubernetes.resources.namespaces.monitoring = {};

  kubernetes.modules.prometheus-kubernetes = {
    module = "prometheus-kubernetes";

    namespace = "monitoring";

    configuration = {
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
