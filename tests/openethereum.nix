{ config, ... }:

{
  require = [./test.nix ../modules/openethereum.nix];

  kubernetes.modules.openethereum = {
    module = "openethereum";
    configuration.chain = "ropsten";
  };
}
