{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.kibana = {
    module = "kibana";
  };
}
