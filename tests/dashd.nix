{ config, ... }:

{
  require = [./test.nix ../modules/dashd.nix];

  kubernetes.modules.my-dashd = {
    module = "dashd";
    configuration.rpcAuth = "";
  };
}
