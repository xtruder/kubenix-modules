{ config, k8s, ... }:

with k8s;

{
  require = import ../services/module-list.nix;

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
    };
  };

  kubernetes.resources.secrets.influxdb-admin.data = {
    username = toBase64 "admin";
    password = toBase64 "admin";
  };
}
