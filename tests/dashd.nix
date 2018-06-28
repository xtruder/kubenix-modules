{ config, ... }:

{
  require = [./test.nix ../modules/dashd.nix];

  kubernetes.modules.dashd = {
    module = "dashd";
    configuration.rpcAuth = "";
  };
}
