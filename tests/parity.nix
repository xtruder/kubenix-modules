{ config, ... }:

{
  require = [./test.nix ../modules/parity.nix];

  kubernetes.modules.parity = {
    module = "parity";
    configuration.chain = "kovan";
  };
}
