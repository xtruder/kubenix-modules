{ config, k8s, ... }:

with k8s;

{
  require = [./test.nix ../modules/grafana.nix ../modules/influxdb.nix];

  kubernetes.modules.grafana = {
    module = "grafana";
    configuration = {
      rootUrl = "http://grafana.default.svc.cluster.local";
      adminPassword.name = "grafana-user";
      db.type = "sqlite3";
      provisioning.datasources.influxdb = {
        type = "influxdb";
        url = "http://influxdb:8086";
        access = "proxy";
        orgId = 1;
        basicAuth = true;
        user = "admin";
        password = "admin";
        database = "test";
        isDefault = true;
      };
      provisioning.dashboardProviders.default = {
        orgId = 1;
        dashboards.dashboard = ./dashboard.json;
      };
    };
  };

  kubernetes.modules.influxdb = {
    module = "influxdb";
    configuration = {
      auth = {
        enable = true;
        adminUsername = {
          name = "influxdb-admin";
          key = "username";
        };
        adminPassword = {
          name = "influxdb-admin";
          key = "password";
        };
      };

      db = {
        name = "test";
        user = {
          name = "influxdb-user";
          key = "user";
        };
        password = {
          name = "influxdb-user";
          key = "password";
        };
      };
    };
  };

  kubernetes.resources.secrets.grafana-user.data = {
    password = toBase64 "root";
  };

  kubernetes.resources.secrets.influxdb-admin.data = {
    username = toBase64 "admin";
    password = toBase64 "admin";
  };

  kubernetes.resources.secrets.influxdb-user.data = {
    user = toBase64 "user";
    password = toBase64 "password";
  };
}
