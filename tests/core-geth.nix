{ config, ... }:

{
  require = [./test.nix ../modules/core-geth.nix];

  kubernetes.modules.core-geth = {
    module = "core-geth";
    configuration = {
      chain = "ethereum";
      http.enable = true;
    };
  };
}
