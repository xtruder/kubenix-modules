{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.rippled = {
    module = "rippled";
  };
}
