{ config, ... }:

{
  require = [./test.nix ../modules/rippled.nix];

  kubernetes.modules.rippled = {
    module = "rippled";
    configuration = {
      nodeSize = "tiny";
      storage.class = "ssd";
    };
  };
}
