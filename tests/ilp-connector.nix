{ config, k8s, ... }:

with k8s;

{
  require = [./test.nix ../modules/ilp-connector.nix];

  kubernetes.modules.ilp-connector = {
    module = "ilp-connector";

    configuration = {};
  };
}