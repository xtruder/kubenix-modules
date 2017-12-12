{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.beehive = {
    module = "beehive";
  };
}
