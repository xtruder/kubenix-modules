{ config, ... }:

{
  require = [./test.nix ../modules/metabase.nix];

  kubernetes.modules.metabase = {
    module = "metabase";
  };
}
