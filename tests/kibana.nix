{ config, ... }:

{
  require = [./test.nix ../modules/kibana.nix];

  kubernetes.modules.kibana = {
    module = "kibana";
  };
}
