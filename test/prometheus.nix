{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.prometheus = {
    module = "prometheus";
    configuration = {
      enableKubernetesScrapers = true;
    };
  };

  kubernetes.modules.prometheus-pushgateway = {
    module = "prometheus-pushgateway";
  };

  kubernetes.modules.prometheus-alertmanager = {
    module = "prometheus-alertmanager";
  };
}
