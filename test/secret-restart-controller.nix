{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.secret-restart-controller = {
    module = "secret-restart-controller";
  };
}
