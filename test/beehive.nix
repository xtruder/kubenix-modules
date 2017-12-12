{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.beehive = {
    module = "beehive";

    configuration.extraPorts = [65100];
  };
}
