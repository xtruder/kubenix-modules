{ config, ... }:

{
  require = [./test.nix ../modules/rippled.nix];

  kubernetes.modules.rippled = {
    module = "rippled";
    configuration = {
      storage.class = "ssd";
      nodeSize = "tiny";
    };
  };
}
