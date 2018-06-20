{ config, ... }:

{
  require = [./test.nix ../modules/beehive.nix];

  kubernetes.modules.beehive = {
    module = "beehive";

    configuration.extraPorts = [65100];
  };
}
