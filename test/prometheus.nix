{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.prometheus = {
    module = "prometheus";
    configuration = {
      replicas = 1;
      alertmanager.enable = true;
    };
  };

  kubernetes.modules.prometheus-pushgateway = {
    module = "prometheus-pushgateway";
  };

  kubernetes.modules.prometheus-alertmanager = {
    module = "prometheus-alertmanager";
  };
}
