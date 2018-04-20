{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.dashd = {
    module = "dashd";
  };
}
