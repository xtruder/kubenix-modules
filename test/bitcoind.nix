{ config, ... }:

{
  require = import ../services/module-list.nix;

  kubernetes.modules.bitcoind = {
    module = "bitcoind";
  };
}
