{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.redis = {
    module = "redis";
  };
}
