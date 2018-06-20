{ config, ... }:

{
  require = [./test.nix ../modules/secret-restart-controller.nix];

  kubernetes.modules.secret-restart-controller = {
    module = "secret-restart-controller";
    configuration.namespace = null;
  };
}
