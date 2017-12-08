{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.parity = {
    module = "parity";
  };
}
